# tmux multiplexer module.
#
# Shell hooks are files written to $XDG_CONFIG_HOME/shell/ alongside the
# shared shell functions and sourced through nixSpace.programs.shells.initExtra,
# so a shell picks them up without this module knowing which shell it is.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.multiplexers.tmux;
  terminals = config.nixSpace.programs.terminals;
  clr = cfg.colors;
in
{
  options.nixSpace.programs.multiplexers.tmux = {
    enable = lib.mkEnableOption "tmux";

    shell = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "\${pkgs.bash}/bin/bash";
      description = ''
        Shell tmux starts in new panes, or null for the login shell.

        Null rather than a platform guess: tmux uses $SHELL by default, which
        is what the user actually chose.
      '';
    };

    terminal = lib.mkOption {
      type = lib.types.str;
      default = "tmux-256color";
      description = ''
        TERM value inside tmux.

        tmux-256color is current tmux default and requires the terminfo entry 
        present, which ncurses provides.
      '';
    };

    clipboard = lib.mkOption {
      type = lib.types.enum [
        "wayland"
        "x11"
        "darwin"
      ];
      default = if pkgs.stdenv.hostPlatform.isDarwin then "darwin" else "wayland";
      defaultText = lib.literalMD "`darwin` on macOS, `wayland` otherwise.";
      description = ''
        Which clipboard tool the extrakto plugin copies with.

        Previously derived from a `wayland` TAG, which meant this module took
        the tag registry as an argument for one string. An explicit option is
        the same decision without the dependency.
      '';
    };

    colors = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        black = "#282c34";
        darkGrey = "#3e4452";
        comment = "#5c6370";
        fg = "#abb2bf";
        green = "#98c379";
        yellow = "#e5c07b";
        red = "#e06c75";
      };
      description = ''
        Status bar palette, One Dark by default.

        Replace the whole attrset to change scheme; every key is indexed by
        name below.
      '';
    };

    windowTitle = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
                Rename the window to the current directory on every prompt.

                tmux's own automatic-rename only triggers when the foreground process changes,
        				and `cd` doesn't launch a process.
      '';
    };

    sshRename = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
                Rename the window to the ssh destination for the duration of a
                connection, and restore it afterwards.

                Defines an `ssh` shell function, so anything calling ssh
                interactively goes through it. Scripts should be uneffected because 
        				functions are not exported.
      '';
    };

    viCopyMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Bind `v` to begin selection in copy mode.

        keyMode = "vi" gives vi navigation but leaves selection on Space,
        which is the one binding that differs from vim itself.
      '';
    };

    splitsInheritPath = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open new splits in the current pane's directory.

        tmux's default is the directory the session started in.
        Rebinds all four split keys.
      '';
    };

    zenMode = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "Z";
      description = ''
        Prefix key that zooms a pane AND hides the status bar, or null.

        Driven by window_zoomed_flag, so unzooming with plain `z` restores
        the pane but not the bar. They will be out of sync until this key is 
        pressed again.
      '';
    };

    statusPosition = lib.mkOption {
      type = lib.types.enum [
        "top"
        "bottom"
      ];
      default = "top";
      description = "Which edge the status bar sits on.";
    };

    renumberWindows = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Renumber windows when one is closed.

        Keeps prefix-number bindings contiguous, at the cost of a window's
        number changing under it.
      '';
    };

    listKeysBinding = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "b";
      description = "Prefix key listing all bindings, or null.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra tmux configuration, appended last.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      lib.optional (cfg.clipboard == "wayland") pkgs.wl-clipboard
      ++ lib.optional (cfg.clipboard == "x11") pkgs.xclip;

    # Written alongside the shared functions rather than into initExtra, so
    # they are real files shellcheck can read.
    xdg.configFile = lib.mkMerge [
      (lib.mkIf cfg.sshRename {
        "shell/tmux-ssh-rename.sh".source = ./ssh-rename.sh;
      })
      (lib.mkIf cfg.windowTitle {
        "shell/tmux-window-title.sh".source = ./window-title.sh;
      })
    ];

    nixSpace.programs.shells.initExtra = lib.mkMerge [
      (lib.mkIf cfg.sshRename ''
        [ -r "${config.xdg.configHome}/shell/tmux-ssh-rename.sh" ] \
          && . "${config.xdg.configHome}/shell/tmux-ssh-rename.sh"
      '')

      (lib.mkIf cfg.windowTitle ''
        [ -r "${config.xdg.configHome}/shell/tmux-window-title.sh" ] \
          && . "${config.xdg.configHome}/shell/tmux-window-title.sh"

        # The hook registration differs per shell; the function itself does
        # not. bash re-runs PROMPT_COMMAND before each prompt, zsh runs
        # everything in precmd_functions.
        if [ -n "''${BASH_VERSION:-}" ]; then
          PROMPT_COMMAND="''${PROMPT_COMMAND:+''${PROMPT_COMMAND}; }_ns_tmux_window_title"
        elif [ -n "''${ZSH_VERSION:-}" ]; then
          precmd_functions+=(_ns_tmux_window_title)
        fi
      '')
    ];

    programs.tmux = {
      enable = true;

      # sensible is not layered on top: it sets escape-time, history-limit,
      # and terminal itself, and would override the values below.
      sensibleOnTop = false;

      escapeTime = 10;
      mouse = true;
      keyMode = "vi";
      baseIndex = 1;
      historyLimit = 50000;
      clock24 = true;
      focusEvents = true;
      terminal = cfg.terminal;
    }
    // lib.optionalAttrs (cfg.shell != null) {
      shell = cfg.shell;
    }
    // {
      plugins = with pkgs.tmuxPlugins; [
        pain-control
        vim-tmux-navigator
        logging
        yank
        tmux-fzf

        {
          plugin = tmux-floax;
          extraConfig = "set -g @floax-border-color 'blue'";
        }

        {
          plugin = extrakto;
          extraConfig =
            let
              tool =
                {
                  wayland = "wl-copy";
                  x11 = "xclip";
                  darwin = "pbcopy";
                }
                .${cfg.clipboard};
            in
            ''set -g @extrakto_clip_tool "${tool}"'';
        }

        resurrect

        {
          plugin = continuum;
          extraConfig = ''
            set -g @continuum-restore 'on'
            set -g @continuum-save-interval '10'
          '';
        }
      ];

      extraConfig =
        lib.optionalString cfg.renumberWindows "set -g renumber-windows on\n"
        + lib.optionalString (cfg.listKeysBinding != null) "bind ${cfg.listKeysBinding} list-keys\n"
        + lib.optionalString (cfg.zenMode != null) ''
          # Toggles on the status bar
          bind ${cfg.zenMode} if -F '#{s/off//:status}' \
            'set -g status off; resize-pane -Z' \
            'set -g status on; resize-pane -Z'
        ''
        + lib.optionalString cfg.viCopyMode "bind-key -T copy-mode-vi v send-keys -X begin-selection\n"
        + lib.optionalString cfg.splitsInheritPath ''
          	bind '"' split-window -v -c "#{pane_current_path}"
          	bind % split-window -h -c "#{pane_current_path}"
          	bind | split-window -h -c "#{pane_current_path}"
          	bind _ split-window -v -c "#{pane_current_path}"
        ''
        + ''
          	set -g set-titles on
          	set -g set-titles-string "tmux: #S"

          	# Truecolor for the terminal in use, read from the terminals module
          	# rather than hardcoding alacritty — a value naming a terminal that is
          	# not running does nothing, silently.
          	set -sa terminal-features ',${terminals.primary}:RGB'

          	# Shell hooks do the renaming; allow-rename off stops an application
          	# printing an escape sequence from overriding them.
          	set -g automatic-rename on
          	set -g allow-rename off

          	set -g status-position ${cfg.statusPosition}

          	# bg=default keeps the gaps transparent, so the terminal's own
          	# background shows through rather than a flat bar.
          	set -g status-style "fg=${clr.fg},bg=default"
          	set -g status-left-length 40
          	set -g status-right-length 60

          	# Session name, then a zoom marker.
          	#
          	set -g status-left "#[fg=${clr.black},bg=${clr.green},bold] #S #[fg=${clr.green},bg=default,nobold,nounderscore,noitalics] #{?window_zoomed_flag,[Z] ,}"

          	# The time segment loses its dark block for the same reason; the
          	# hostname keeps its green pill, which has real contrast either way.
          	set -g status-right "#[fg=${clr.fg},bg=default] %H:%M  %d %b #[fg=${clr.black},bg=${clr.green},bold] #h "

          	# bg=default on the inactive states, not a dark grey.
          	#
          	# A Linux console has eight colours and maps hex values to the
          	# nearest — so comment (#5c6370) on black (#282c34), two greys that
          	# differ on a truecolor terminal, collapse to the same colour and the
          	# inactive window names become invisible.
          	#
          	# Letting the terminal's own background through fixes that everywhere
          	# rather than only in a TTY, and matches the base status style, which
          	# already uses bg=default.
          	set -g window-status-style 					"fg=${clr.fg},bg=default"
          	set -g window-status-current-style  "fg=${clr.black},bg=${clr.green},bold"
          	set -g window-status-activity-style "fg=${clr.yellow},bg=default"
          	set -g window-status-bell-style     "fg=${clr.red},bg=default,bold"
          	set -g window-status-separator      ""
          	set -g window-status-format         " #I:#W "
          	set -g window-status-current-format " #I:#W "

          	set -g message-style         "fg=${clr.fg},bg=${clr.darkGrey}"
          	set -g message-command-style "fg=${clr.fg},bg=${clr.darkGrey}"

          	# Same reasoning: darkGrey on black is two greys that merge on a
          	# low-colour display, leaving no visible border at all.
          	set -g pane-border-style        "fg=${clr.darkGrey},bg=default"
          	set -g pane-active-border-style "fg=${clr.green},bg=default"

          	# Dim inactive panes so the focused one is obvious without borders
          	# carrying all the weight.
          	set -g window-style        "fg=${clr.comment}"
          	set -g window-active-style "fg=${clr.fg}"
        ''
        + lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''

          	# smcup@/rmcup@ disables the alternate screen so scrollback reaches
          	# the terminal's own buffer. Only on Darwin, where Terminal.app and
          	# iTerm handle it differently from Linux terminals.
          	set -ga terminal-overrides ',${terminals.primary}:Tc:smcup@:rmcup@'
        ''
        + cfg.extraConfig;
    };
  };
}
