# zellij multiplexer module.
#
# zellij has structural differences from tmux:
#
#   Modes are used in place of the Ctrl-b prefix.
#		zellij has Ctrl-p for pane, Ctrl-t for tab, and so on.
# 	It ships a tmux-compatible mode reached with Ctrl-b, which the
#   keybindings option selects, but the modes are the underlying mechanism,
#   and some keys behave differently.
#
#   The status bar is a layout, not a format string. Which bar you get depends
#   on which plugin panes a layout loads, so there is no equivalent of
#   status-left and the session name and zoom marker have no counterpart.
#
#   Persistence is built in. session_serialization replaces resurrect and
#   continuum. It restores the layout: panes, tabs, directories, but not the
#   processes that were running.
#
# Keybinds go in extraConfig as raw KDL. home-manager's settings option runs
# through a KDL generator using _props/_args/_children conventions, and a bind
# directive expressed that way is unreadable, extraConfig exists for exactly
# this case (home-manager issue #4659).
#
# The shell hooks are separate files from tmux's, not a shared one with
# branches: zellij cannot report its current tab name, so the ssh wrapper
# cannot save-and-restore, and there is no automatic-rename-format, so the
# prompt hook cannot fall back to the running command.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.multiplexers.zellij;
  clr = cfg.colors;

  # Layout deciding which status plugins load. The bar is panes in a tab
  # template, not a setting, which is why statusBar generates this.
  tabTemplate = {
    default = ''
      layout { 
      	default_tab_template {
      		pane size=1 borderless=true {
      			plugin location="zellij:tab-bar"
      		}
      		children
      		pane size=2 borderless=true {
      			plugin location="zellij:status-bar"
      		}
      	}
      }
    '';

    compact = ''
      layout { 
      	default_tab_template {
      		children
      		pane size=1 borderless=true {
      			plugin location="zellij:compact-bar"
      		}
      	}
      }
    '';

    none = ''
      layout { 
      	default_tab_template {
      		children
      	}
      }
    '';
  };
in
{
  options.nixSpace.programs.multiplexers.zellij = {
    enable = lib.mkEnableOption "zellij";

    keybindings = lib.mkOption {
      type = lib.types.enum [
        "tmux"
        "default"
      ];
      default = "default";
      description = ''
        Which keybinding scheme to use.

        "tmux" clears zellij's modal bindings so Ctrl-p and Ctrl-t reach the
        running program, and leaves Ctrl-b as the single entry point. This is
        NOT fully compatible with tmux. This is a mode not a prefix, so a second 
        keypress stays in it until an action or Escape.

        "default" keeps the native modes, which is what zellij's own help
        text and documentation describe.
      '';
    };

    defaultMode = lib.mkOption {
      type = lib.types.enum [
        "normal"
        "locked"
      ];
      default = "normal";
      description = ''
        Mode zellij starts in.

        "locked" passes every key through to the running program except the
        unlock binding, this allwos running an editor with its own Ctrl-based 
        bindings, which zellij otherwise intercepts.
      '';
    };

    statusBar = lib.mkOption {
      type = lib.types.enum [
        "default"
        "compact"
        "none"
      ];
      default = "compact";
      description = ''
        Which status plugins to load.

        Implemented as a layout rather than a setting: the bar is a pane in a
        tab template, so choosing one means choosing which plugin panes exist.

        "default" is two rows: a tab bar and a mode line whose second row is
        a keybinding cheatsheet. "compact" is one row combining both. "none"
        reclaims the space at the cost of no visible tab list.
      '';
    };

    paneFrames = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Draw a frame around every pane.

        Off by default: frames take a full character cell on each side, so a
        vertical split loses two columns to borders that colour alone conveys.
      '';
    };

    mouse = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable mouse selection, scrolling, and pane focus.";
    };

    scrollback = lib.mkOption {
      type = lib.types.ints.positive;
      default = 50000;
      description = ''
        Scrollback lines PER PANE.

        Matches the tmux module's historyLimit, but note the units differ in
        effect: this is held per pane in memory, so a session with many panes
        multiplies it.
      '';
    };

    sessionSerialization = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Save session layout to disk and restore it on resume.

        Built in, where tmux needs resurrect and continuum.
      '';
    };

    copyCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if pkgs.stdenv.hostPlatform.isDarwin then "pbcopy" else "wl-copy";
      defaultText = lib.literalMD "`pbcopy` on Darwin, `wl-copy` otherwise.";
      description = ''
        Command a copy sends its selection to, or null for zellij's OSC 52
        handling.

        OSC 52 works over ssh where a local command cannot, but needs terminal
        support and silently copies nothing where it is absent.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start zellij automatically on every interactive shell.

        Off by default, and note this differs from tmux's shell integration:
        zellij's generates an auto-start script, so enabling it means every
        new shell tries to start or attach a session. A shell opened INSIDE
        zellij is handled, but anything else spawning a shell, such as a script, 
        or editor's terminal gets a session too.
      '';
    };

    attachExisting = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        When auto-starting, attach to an existing session rather than
        creating another.

        Only read when autoStart is on; upstream warns if set without it.
      '';
    };

    tabTitle = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Rename the tab to the current directory on every prompt.

        Less capable than the tmux equivalent: zellij has no
        automatic-rename-format, so a tab keeps this name even while another
        command runs in it.
      '';
    };

    sshRename = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Rename the tab to the ssh destination for the duration of a
        connection.

        Cannot restore the previous name because zellij offers no way to read a
        tab's name. It sets the working directory on exit, which is what
        the prompt hook would set anyway.
      '';
    };

    colors = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        black = "#282c34";
        red = "#e06c75";
        green = "#98c379";
        yellow = "#e5c07b";
        blue = "#61afef";
        magenta = "#c678dd";
        cyan = "#56b6c2";
        white = "#abb2bf";
        orange = "#d19a66";
      };
      description = ''
        Theme palette, One Dark by default and matching the tmux module's.

        zellij takes nine named colours rather than a foreground and
        background pair. It includes "orange", which has no ANSI equivalent
        and colours the mode indicator.
      '';
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Raw KDL appended to config.kdl, after the keybinds above.";
    };

    extraSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra settings merged over the ones above.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = lib.optional (cfg.copyCommand == "wl-copy") pkgs.wl-clipboard;

    xdg.configFile = lib.mkMerge [
      (lib.mkIf cfg.sshRename {
        "shell/zellij-ssh-rename.sh".source = ./ssh-rename.sh;
      })
      (lib.mkIf cfg.tabTitle {
        "shell/zellij-tab-title.sh".source = ./tab-title.sh;
      })
    ];

    nixSpace.programs.shells.initExtra = lib.mkMerge [
      (lib.mkIf cfg.sshRename ''
        [ -r "${config.xdg.configHome}/shell/zellij-ssh-rename.sh" ] \
          && . "${config.xdg.configHome}/shell/zellij-ssh-rename.sh"
      '')

      (lib.mkIf cfg.tabTitle ''
        [ -r "${config.xdg.configHome}/shell/zellij-tab-title.sh" ] \
          && . "${config.xdg.configHome}/shell/zellij-tab-title.sh"

        if [ -n "''${BASH_VERSION:-}" ]; then
          PROMPT_COMMAND="''${PROMPT_COMMAND:+''${PROMPT_COMMAND}; }_ns_zellij_tab_title"
        elif [ -n "''${ZSH_VERSION:-}" ]; then
          precmd_functions+=(_ns_zellij_tab_title)
        fi
      '')
    ];

    programs.zellij = {
      enable = true;

      # Auto-start (not integration in tmux's sense): see the autoStart
      # option. Off unless asked for.
      enableBashIntegration = cfg.autoStart;
      enableZshIntegration = cfg.autoStart;
      attachExistingSession = lib.mkIf cfg.autoStart cfg.attachExisting;

      # The dedicated themes option, which writes themes/<name>.kdl, rather
      # than an inline themes block in settings.
      themes.nixspace = {
        themes.nixspace = {
          fg = clr.white;
          bg = clr.black;
          inherit (clr) black;
          inherit (clr) red;
          inherit (clr) green;
          inherit (clr) yellow;
          inherit (clr) blue;
          inherit (clr) magenta;
          inherit (clr) cyan;
          inherit (clr) white;
          inherit (clr) orange;
        };
      };

      # The status bar is panes in a tab template, so it lives here.
      layouts.default = tabTemplate.${cfg.statusBar};

      settings = lib.recursiveUpdate (
        {
          theme = "nixspace";
          default_mode = cfg.defaultMode;
          default_layout = "default";
          pane_frames = cfg.paneFrames;
          mouse_mode = cfg.mouse;
          scroll_buffer_size = cfg.scrollback;
          session_serialization = cfg.sessionSerialization;
        }
        // lib.optionalAttrs (cfg.copyCommand != null) {
          copy_command = cfg.copyCommand;
        }
      ) cfg.extraSettings;

      # RAW KDL, not the settings generator.
      #
      # A bind directive through the KDL generator is
      # `keybinds.normal._children = [ { bind = { _args = [...]; _children =
      # [...]; }; } ]` — technically expressible and unreadable. extraConfig
      # exists for this.
      extraConfig =
        lib.optionalString (cfg.keybindings == "tmux") ''
          keybinds clear-defaults=true {
              normal {
                  bind "Ctrl b" { SwitchToMode "Tmux"; }
              }
              locked {
                  bind "Ctrl g" { SwitchToMode "Normal"; }
              }
          }
        ''
        + cfg.extraConfig;
    };
  };
}
