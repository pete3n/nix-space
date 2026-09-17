# Laptop lid event daemon.
#
# Used to provide fine-grain control of laptop lid events without a desktop
# environment. It is designed to be paired with hyprlidmon to provide a user
# space interface. It polls /proc/acpi/button/lid/*/state and writes an event file
# to /run/lidmond/events and runs configured commands.
#
# Why use this over something like logind? Logind's lid handling is all-or-nothing
# per state and cannot take actions like "blank the panel but stay awake while on AC".
# Enabling this module sets logind to ignore lid events so that lidmond can
# control them; an assertion catches anything else overriding that.
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
    mkDefault
    mkIf
    types
    ;

  cfg = config.nixSpace.services.lidmond;

  stateDir = "/run/lidmond";

  # Rules are handed to the script as data rather than unrolled into generated
  # shell. One field per line, `end` closes a rule, and the value is everything
  # after the first space. Parsed by handle_lid_closed in lidmond.sh.
  rulesFile = pkgs.writeText "lidmond-rules" (
    lib.concatMapStrings (
      rule:
      lib.concatMapStrings (cond: "cond ${cond}\n") rule.cond
      + lib.concatMapStrings (cmd: "close ${cmd}\n") rule.closeCmd
      + lib.concatMapStrings (cmd: "open ${cmd}\n") rule.openCmd
      + "end\n"
    ) cfg.rules
  );

  lidmond = pkgs.writeShellApplication {
    name = "lidmond";
    # The wrapper prepends these to PATH, so they also resolve when
    # `lidmond --backlight-off` is invoked manually or from a rule.
    runtimeInputs = with pkgs; [
      brightnessctl
      coreutils
      gawk
    ];

    text = # sh
    ''
      ACCESS_GROUP="${cfg.accessGroup}"
      BACKLIGHT_DEVICE="${toString cfg.backlightDevice}" # Empty when null
      CLOSE_BRIGHTNESS_FILE="${stateDir}/close_brightness"
      DEFAULT_RESTORE_BRIGHTNESS="50"
      EVENT_DIR="${stateDir}/events"
      LID_CLOSED_DEFAULT_CMD=${lib.escapeShellArg cfg.lidClosedDefaultCmd}
      LID_OPENED_DEFAULT_CMD=${lib.escapeShellArg cfg.lidOpenedDefaultCmd}
      LOG_TO_JOURNAL="${lib.boolToString cfg.logToJournal}"
      OPEN_CMDS_FILE="${stateDir}/open_cmds"
      POLL_INTERVAL_SECONDS="${toString cfg.pollIntervalSeconds}"
      RULES_FILE="${rulesFile}"
      RUNTIME_SHELL="${pkgs.runtimeShell}"
    ''
    + builtins.readFile ./lidmond.sh;
  };
in
{
  options.nixSpace.services.lidmond = {
    enable = mkEnableOption "lidmond lid event handler";

    accessGroup = mkOption {
      type = types.str;
      default = "lidmond";
      example = "wheel";
      description = ''
        Group granted read access to lidmond state and events under
        /run/lidmond/events. User-session consumers read those files.

        The group is created automatically only when this is left at the
        default. Any other value must name a group that already exists, or the
        unit fails to start.
      '';
    };

    lidClosedDefaultCmd = mkOption {
      type = types.str;
      default = "systemctl suspend";
      description = "Command run on lidClosed when no rule matches.";
    };

    lidOpenedDefaultCmd = mkOption {
      type = types.str;
      default = ":";
      description = "Command run on lidOpened when no stored openCmd applies.";
    };

    rules = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            cond = mkOption {
              type = types.listOf (types.enum [ "extPower" ]);
              default = [ ];
              example = [ "extPower" ];
              description = "Condition list, ANDed together. Currently supports: extPower.";
            };
            closeCmd = mkOption {
              type = types.listOf types.str;
              default = [ ];
              example = [ "lidmond --backlight-off" ];
              description = "Commands run when lidClosed and this rule matches.";
            };
            openCmd = mkOption {
              type = types.listOf types.str;
              default = [ ];
              example = [ "lidmond --backlight-on" ];
              description = "Commands run on the next lidOpened, after a matching close.";
            };
          };
        }
      );

      default = [
        {
          cond = [ "extPower" ];
          closeCmd = [ "lidmond --backlight-off" ];
          openCmd = [ "lidmond --backlight-on" ];
        }
      ];

      description = ''
        Rules evaluated on lidClosed, in order. First match wins.

        Conditions:
          - "extPower": any /sys/class/power_supply/*/online reads 1

        Event files are written to /run/lidmond/events regardless of which
        rule matches; rules control additional actions only.

        Commands may not contain newlines.
      '';
    };

    pollIntervalSeconds = mkOption {
      type = types.number;
      default = 1;
      description = "Interval between lid state polls, in seconds.";
    };

    logToJournal = mkOption {
      type = types.bool;
      default = true;
      description = "Emit log lines to journald.";
    };

    backlightDevice = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "amdgpu_bl0";
      description = ''
        brightnessctl device to control. Null auto-detects, preferring
        amdgpu_bl0 then intel_backlight, then the first responsive backlight
        class device.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion =
          let
            login = config.services.logind.settings.Login or { };
          in
          (login.HandleLidSwitch or null) == "ignore"
          && (login.HandleLidSwitchDocked or null) == "ignore"
          && (login.HandleLidSwitchExternalPower or null) == "ignore";
        message = ''
          nixSpace.services.lidmond is enabled, but systemd-logind still handles
          lid events. Both acting on the same transition is a race.

          This module sets these to "ignore" by default, so something else in
          the configuration is overriding one of:
            services.logind.settings.Login.HandleLidSwitch
            services.logind.settings.Login.HandleLidSwitchDocked
            services.logind.settings.Login.HandleLidSwitchExternalPower
        '';
      }
      {
        # The rules file is line oriented, so a newline inside a command would
        # silently split it into two.
        assertion = lib.all (cmd: !lib.hasInfix "\n" cmd) (
          lib.concatMap (rule: rule.closeCmd ++ rule.openCmd) cfg.rules
        );
        message = "nixSpace.services.lidmond.rules: closeCmd and openCmd entries must not contain newlines.";
      }
    ];

    # mkDefault rather than mkForce: an explicit conflicting value elsewhere
    # should trip the assertion above, not be silently overridden.
    services.logind.settings.Login = {
      HandleLidSwitch = mkDefault "ignore";
      HandleLidSwitchDocked = mkDefault "ignore";
      HandleLidSwitchExternalPower = mkDefault "ignore";
    };

    users.groups = mkIf (cfg.accessGroup == "lidmond") {
      lidmond = { };
    };

    systemd.services.lidmond = {
      description = "laptop lid event daemon";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" ];
      path = [ lidmond ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${lidmond}/bin/lidmond";
        Restart = "always";
        RestartSec = 1;
        UMask = "0027";

        # RuntimeDirectory owns these paths: it creates them on start and
        # removes them on stop.
        RuntimeDirectory = "lidmond lidmond/events";
        RuntimeDirectoryMode = "2750";

        Group = cfg.accessGroup;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        ReadWritePaths = [
          stateDir
          "/sys/class/backlight"
        ];
        ReadOnlyPaths = [
          "/proc/acpi"
          "/sys/class/power_supply"
        ];
      };
    };
  };
}
