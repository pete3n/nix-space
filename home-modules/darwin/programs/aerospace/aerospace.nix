# AeroSpace tiling window manager for macOS.
#   https://nikitabobko.github.io/AeroSpace/guide
#
# The darwin counterpart to nixSpace.hyprland: compositor-level bindings and
# layout, with application launchers reading the terminals and launchers
# modules rather than naming a terminal themselves.
#
# ENVIRONMENT: GUI applications AeroSpace launches inherit launchd's
# environment, not a shell's, so nothing from the Nix profile is on PATH. That
# is why every command here is a store path, and why the tmux launcher sources
# the profile scripts before exec — the shell tmux spawns would otherwise be
# bare. The structural fix is a login shell in the terminal's own config,
# which makes the sourcing unnecessary everywhere; see tmuxSession below.
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

  cfg = config.nixSpace.aerospace;
  terminals = config.nixSpace.programs.terminals;

  sketchybarOn = config.nixSpace.sketchybar.enable or false;

  # Close the focused window, unless it is a tmux session — then detach, so
  # the session survives. Detected by the window title, which the tmux module
  # prefixes with "tmux:".
  smartClose = pkgs.writeShellApplication {
    name = "aerospace-smart-close";
    runtimeInputs = with pkgs; [
      aerospace
      gnugrep
      tmux
    ];
    text = # sh
      ''
        _focused="$(aerospace list-windows --focused --format "%{app-name} %{window-title}")"
        if printf '%s' "''${_focused}" | grep -q "tmux:"; then
          tmux detach-client
        else
          aerospace close
        fi
      '';
  };

  toggleSketchybar = pkgs.writeShellApplication {
    name = "aerospace-toggle-sketchybar";
    runtimeInputs = with pkgs; [
      gnugrep
      sketchybar
    ];
    text = # sh
      ''
        if sketchybar --query bar | grep -q '"hidden": "off"'; then
          sketchybar --bar hidden=on
        else
          sketchybar --bar hidden=off
        fi
      '';
  };

  toggleScratchpad = pkgs.writeShellApplication {
    name = "aerospace-toggle-scratchpad";
    runtimeInputs = [ pkgs.aerospace ];
    text = # sh
      ''
        if [ "$(aerospace list-workspaces --focused)" = "${cfg.scratchpadWorkspace}" ]; then
          aerospace workspace-back-and-forth
        else
          aerospace workspace ${cfg.scratchpadWorkspace}
        fi
      '';
  };

  # Sources the Nix profile before exec, so the shell tmux spawns has the
  # environment a login shell would. See the header.
  tmuxSession = pkgs.writeShellApplication {
    name = "aerospace-tmux-session";
    runtimeInputs = [ pkgs.tmux ];
    text = # sh
      ''
        # shellcheck disable=SC1091
        [ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ] \
          && . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        # shellcheck disable=SC1091
        [ -r "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh" ] \
          && . "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
        exec tmux new-session -A -s ${cfg.tmuxSessionName}
      '';
  };

  # Workspace bindings, generated. cmd-N focuses workspace N, cmd-shift-N
  # moves the focused window there.
  workspaceBinds = lib.listToAttrs (
    lib.concatMap (n: [
      (lib.nameValuePair "cmd-${toString n}" "workspace ${toString n}")
      (lib.nameValuePair "cmd-shift-${toString n}" "move-node-to-workspace ${toString n}")
    ]) (lib.range 1 cfg.workspaces)
  );

  exec = cmd: "exec-and-forget ${cmd}";
in
{
  options.nixSpace.aerospace = {
    enable = mkEnableOption "the AeroSpace tiling window manager";

    workspaces = mkOption {
      type = types.ints.between 1 9;
      default = 5;
      description = ''
        Number of numbered workspaces, bound to cmd-1 through cmd-N.

        Capped at 9 because cmd-0 is not generated — AeroSpace has no
        convention for it the way Hyprland's workspace 10 has.
      '';
    };

    scratchpadWorkspace = mkOption {
      type = types.str;
      default = "S";
      description = ''
        Name of the scratchpad workspace. cmd-s toggles to it and back;
        cmd-shift-s sends the focused window there.
      '';
    };

    tmuxSessionName = mkOption {
      type = types.str;
      default = "main";
      description = ''
        Session cmd-t attaches to or creates. Matches the Hyprland bundle's
        default so the same muscle memory lands in the same session.
      '';
    };

    gaps = mkOption {
      type = types.ints.unsigned;
      default = 5;
      description = ''
        Pixels between windows and from the screen edge. One value for all
        six of AeroSpace's gap settings — they are rarely wanted different,
        and settings.gaps can override any individually.
      '';
    };

    sketchybarToggle = mkOption {
      type = types.bool;
      default = sketchybarOn;
      defaultText = lib.literalExpression "config.nixSpace.sketchybar.enable";
      description = ''
        Bind cmd-w to toggle sketchybar. Defaults to whether sketchybar is
        enabled, so the binding does not exist on a host without a bar to
        toggle.
      '';
    };

    extraBindings = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        cmd-b = "exec-and-forget open -a Firefox";
      };
      description = ''
        Additional main-mode bindings, merged over the defaults. A key
        defined here replaces the default binding for that key.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "nixSpace.aerospace is a macOS window manager and cannot be enabled on ${pkgs.stdenv.hostPlatform.system}.";
      }
    ];

    programs.aerospace = {
      enable = true;
      launchd.enable = true;

      settings = {
        gaps = {
          inner.horizontal = cfg.gaps;
          inner.vertical = cfg.gaps;
          outer.left = cfg.gaps;
          outer.bottom = cfg.gaps;
          outer.top = cfg.gaps;
          outer.right = cfg.gaps;
        };

        mode.main.binding =
          {
            # Launchers read the terminals and launchers modules rather than
            # naming a terminal, so switching the primary terminal moves
            # these with it.
            cmd-enter = exec terminals.primaryCommand;
            cmd-r = exec "${terminals.primaryCommand} -e ${config.nixSpace.programs.launchers.primaryCommand}";
            cmd-t = exec "${terminals.primaryCommand} -e ${lib.getExe tmuxSession}";
            cmd-shift-q = exec (lib.getExe smartClose);

            cmd-f = "fullscreen";
            cmd-h = "focus left";
            cmd-j = "focus down";
            cmd-k = "focus up";
            cmd-l = "focus right";
            cmd-shift-h = "move left";
            cmd-shift-j = "move down";
            cmd-shift-k = "move up";
            cmd-shift-l = "move right";

            cmd-s = exec (lib.getExe toggleScratchpad);
            cmd-shift-s = "move-node-to-workspace ${cfg.scratchpadWorkspace}";

            cmd-slash = "layout tiles horizontal vertical";
            cmd-comma = "layout accordion horizontal vertical";
          }
          // workspaceBinds
          // lib.optionalAttrs cfg.sketchybarToggle {
            cmd-w = exec (lib.getExe toggleSketchybar);
          }
          // cfg.extraBindings;
      };
    };
  };
}
