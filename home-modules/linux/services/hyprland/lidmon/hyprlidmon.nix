# Hyprland user agent module for laptop lid events.
#
# Companion to the lidmond system-module service: lidmond watches the ACPI lid state
# as root and writes event files; this agent reads them inside the Hyprland
# session and acts on them. The split exists because reading /proc/acpi needs
# root while hyprctl needs the user's session — neither side can do both.
#
# The event files are the interface. This module does not talk to lidmond
# directly, so a different producer writing the same format would work.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;

  cfg = config.nixSpace.services.hyprlidmon;
  hyprCfg = config.nixSpace.hyprland;

  hyprPkg =
    if config.wayland.windowManager.hyprland.finalPackage != null then
      config.wayland.windowManager.hyprland.finalPackage
    else
      pkgs.hyprland;

  # Shared machine-state detection, concatenated into both scripts after their
  # headers. Both headers must define INTERNAL_DISPLAY and STATE_DIR.
  stateFunctions = builtins.readFile ./hyprlidmon-state.sh;

  # Rules are handed to the daemon as data rather than unrolled into generated
  # shell; same format as lidmond's rules file. Parsed by handle_lid_closed.
  rulesFile = pkgs.writeText "hyprlidmon-rules" (
    lib.concatMapStrings (
      rule:
      lib.concatMapStrings (cond: "cond ${cond}\n") rule.cond
      + lib.concatMapStrings (cmd: "close ${cmd}\n") rule.closeCmd
      + lib.concatMapStrings (cmd: "open ${cmd}\n") rule.openCmd
      + "end\n"
    ) cfg.rules
  );

  # The daemon. Waits for the event directory itself, so the former
  # hyprlidmon-wait and hyprlidmon-wrapper binaries are folded in.
  hyprlidmon = pkgs.writeShellApplication {
    name = "hyprlidmon";
    runtimeInputs = with pkgs; [
      hyprPkg
      coreutils
      jq
    ];

    text = # sh
    ''
      EVENT_DIR="${cfg.eventDir}"
      INTERNAL_DISPLAY="${cfg.intDisplay}"
      LID_CLOSED_DEFAULT_CMD=${lib.escapeShellArg cfg.lidClosedDefaultCmd}
      LID_OPENED_DEFAULT_CMD=${lib.escapeShellArg cfg.lidOpenedDefaultCmd}
      LOG_TO_JOURNAL="${lib.boolToString cfg.logToJournal}"
      POLL_INTERVAL_SECONDS="${toString cfg.pollIntervalSeconds}"
      RULES_FILE="${rulesFile}"
      RUNTIME_SHELL="${pkgs.runtimeShell}"
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/hyprlidmon"
      WAIT_INTERVAL_SECONDS="5"
      WAIT_TIMEOUT_SECONDS="${toString cfg.waitTimeoutSeconds}"
    ''
    + stateFunctions
    + builtins.readFile ./hyprlidmon.sh;
  };

  # Suspend blocker: a one-shot command, not a daemon. Bind it in place of
  # `systemctl suspend`. Each blocker list becomes one space-joined element.
  hyprSuspendBlocker = pkgs.writeShellApplication {
    name = "hypr-suspend-blocker";
    runtimeInputs = with pkgs; [
      hyprPkg
      coreutils
      jq
      systemd
    ];

    text = # sh
    ''
      INTERNAL_DISPLAY="${cfg.intDisplay}"
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/hyprlidmon"
      ${lib.toShellVar "SUSPEND_BLOCKERS" (map (lib.concatStringsSep " ") cfg.suspendBlockers)}
    ''
    + stateFunctions
    + builtins.readFile ./hypr-suspend-blocker.sh;
  };
in
{
  options.nixSpace.services.hyprlidmon = {
    enable = mkEnableOption "lidmond user agent" // {
      default = true;
      description = "lidmond Hyprland user agent";
    };

    eventDir = mkOption {
      type = types.str;
      default = "/run/lidmond/events";
      description = ''
        Directory holding event files written by the lidmond system service.

        Must match nixSpace.services.lidmond's own runtime directory. Nothing
        checks the two agree — a mismatch presents as the agent waiting
        forever with the "still waiting" message.
      '';
    };

    waitTimeoutSeconds = mkOption {
      type = types.ints.unsigned;
      default = 60;
      description = ''
        How long to wait for the lidmond event directory before failing, or 0
        to wait forever. The agent requires it.
      '';
    };

    pollIntervalSeconds = mkOption {
      type = types.number;
      default = 1;
      description = ''
        Interval between event directory scans.

        A poll rather than an inotify watch: the directory may not exist when
        the agent starts, and re-establishing a watch across that is more
        machinery than a one-second sleep is worth.
      '';
    };

    logToJournal = mkOption {
      type = types.bool;
      default = true;
      description = "Emit log lines to the user journal.";
    };

    lidClosedDefaultCmd = mkOption {
      type = types.str;
      default = ":";
      example = "loginctl lock-session";
      description = "Command run on lidClosed when no rule matches.";
    };

    lidOpenedDefaultCmd = mkOption {
      type = types.str;
      default = ":";
      description = ''
        Command run on lidOpened, after any stored open commands.

        Note this is not symmetric with lidClosedDefaultCmd: it runs
        unconditionally rather than only when nothing else did.
      '';
    };

    intDisplay = mkOption {
      type = types.str;
      default = "auto";
      example = "eDP-1";
      description = ''
        Hyprland name of the internal panel, or "auto" to detect it.

        Auto-detection matches an eDP- or LVDS- prefix, then falls back to a
        lone disabled monitor. The result is cached, because a disabled panel
        does not appear in hyprctl output.
      '';
    };

    suspendBlockers = mkOption {
      type = types.listOf (
        types.listOf (
          types.enum [
            "lidOpen"
            "lidClosed"
            "extDisplay"
            "extPower"
            "onBattery"
          ]
        )
      );
      default = [
        [
          "extPower"
        ]
      ];
      example = [
        [ "extPower" ]
        [
          "extDisplay"
          "lidClosed"
        ]
      ];
      description = ''
        Conditions under which `hypr-suspend-blocker` refuses to suspend.

        A list of lists: Every condition within a list must hold for that list
        to match, and suspend is blocked if ANY list matches. So the example
        above blocks on AC power, or when docked with the lid shut.

        An empty list never blocks, so the command is a plain
        `systemctl suspend` passthrough.

        Bind `hypr-suspend-blocker` in place of `systemctl suspend`. It also
        takes --print to dump the detected state and --dry-run to report the
        decision without acting.
      '';
    };

    rules = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            cond = mkOption {
              type = types.listOf (
                types.enum [
                  "extPower"
                  "extDisplay"
                ]
              );
              default = [ ];
              description = "Conditions, ANDed together. An empty list always matches.";
            };
            closeCmd = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Commands run when this rule matches on lidClosed.";
            };
            openCmd = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Commands stored at close time and run on the next lidOpened.";
            };
          };
        }
      );
      default = [
        {
          cond = [
            "extPower"
            "extDisplay"
          ];
          closeCmd = [ "--int-display-disable" ];
          openCmd = [ "--int-display-enable" ];
        }
        {
          cond = [
            "extPower"
          ];
          closeCmd = [ "--int-display-disable" ];
          openCmd = [ "--int-display-enable" ];
        }
      ];
      description = ''
        Rules evaluated on lidClosed, in order. First match wins, so order
        them most specific first.

        openCmd is deferred rather than evaluated at open time because the
        docked state is known at CLOSE — by the time the lid opens, the
        external display may already be gone.

        Two internal switches are recognised alongside shell commands:
          --int-display-disable
          --int-display-enable

        Commands may not contain newlines.
      '';
      example = lib.literalExpression ''
        [
          {
            # Docked: on AC with an external display, blank the panel
            cond = [ "extPower" "extDisplay" ];
            closeCmd = [ "loginctl lock-session" "--int-display-disable" ];
            openCmd = [ "--int-display-enable" ];
          }
          {
            # On AC, no external display
            cond = [ "extPower" ];
            closeCmd = [ "loginctl lock-session" ];
          }
        ]
      '';
    };
  };

  config = mkIf (hyprCfg.enable && cfg.enable) {
    assertions = [
      {
        # Both in one list can never match, so the list is dead weight that
        # looks meaningful.
        assertion = lib.all (l: !(lib.elem "lidOpen" l && lib.elem "lidClosed" l)) cfg.suspendBlockers;
        message = "nixSpace.services.hyprlidmon.suspendBlockers: a list cannot contain both lidOpen and lidClosed.";
      }
      {
        assertion = lib.all (l: !(lib.elem "extPower" l && lib.elem "onBattery" l)) cfg.suspendBlockers;
        message = "nixSpace.services.hyprlidmon.suspendBlockers: a list cannot contain both extPower and onBattery.";
      }
      {
        # The rules file is line oriented, so a newline inside a command would
        # silently split it into two.
        assertion = lib.all (cmd: !lib.hasInfix "\n" cmd) (
          lib.concatMap (rule: rule.closeCmd ++ rule.openCmd) cfg.rules
        );
        message = "nixSpace.services.hyprlidmon.rules: closeCmd and openCmd entries must not contain newlines.";
      }
    ];

    home.packages = [
      hyprlidmon
      hyprSuspendBlocker
    ];

    systemd.user.services.hyprlidmon = {
      Unit = {
        Description = "lidmond Hyprland user agent";
        After = [ "hyprland-session.target" ];
        PartOf = [ "hyprland-session.target" ];

        # Paired with Restart = "on-failure" below: three failures inside ten
        # minutes and systemd stops retrying, leaving the unit in `failed`
        # where a status check will show it.
        StartLimitIntervalSec = 600;
        StartLimitBurst = 3;
      };
      Service = {
        Type = "simple";
        ExecStart = "${hyprlidmon}/bin/hyprlidmon";

        # on-failure with a rate limit, not always/1s.
        #
        # The agent EXITS non-zero when the lidmond event directory never
        # appears. Under Restart = "always" that becomes a restart loop
        # once per second — the unit still looks like it is doing something,
        # which is the failure mode the bounded wait was meant to remove.
        #
        # StartLimit lets systemd give up: after 3 failures in 10 minutes the
        # unit enters `failed` and stays there, so `systemctl --user status`
        # reports the problem instead of an endlessly restarting service.
        Restart = "on-failure";
        RestartSec = 10;

        # PassEnvironment forwards from SYSTEMD's environment, which only has
        # these after Hyprland's start hook runs
        # dbus-update-activation-environment. A service starting before that
        # import gets nothing — which is why the agent also resolves the
        # signature from $XDG_RUNTIME_DIR/hypr itself.
        PassEnvironment = [
          "HYPRLAND_INSTANCE_SIGNATURE"
          "XDG_RUNTIME_DIR"
          "WAYLAND_DISPLAY"
        ];
      };

      # WantedBy hyprland-session.target, not default.target: the agent is
      # useless without a compositor, and PartOf above stops it outliving one.
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    home.activation.restartHyprlidmon = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if $DRY_RUN_CMD systemctl --user is-active --quiet hyprlidmon 2>/dev/null; then
        $DRY_RUN_CMD systemctl --user restart hyprlidmon
      fi
    '';
  };
}
