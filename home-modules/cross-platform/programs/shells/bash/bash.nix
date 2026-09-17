# bash specific configuration module
#
# Shared functions come from nixSpace.programs.shells, which writes them
# to $XDG_CONFIG_HOME/shell and exports the lines that source them.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.shells.bash;
  shared = config.nixSpace.programs.shells;
in
{
  options.nixSpace.programs.shells.bash = {
    enable = lib.mkEnableOption "bash configuration";

    viMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
          Use vi keybindings at the prompt, with the current mode shown.
        	A mode indicator is required to show either insert or navigation mode.
      '';
    };

    editor = lib.mkOption {
      type = lib.types.str;
      default = "nvim";
      description = ''
        The default editor for the login shell.

        Set in profileExtra rather than home.sessionVariables so it applies to
        shells started outside a graphical session.
      '';
    };

    loginGreeting = {
      fastfetch = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run fastfetch on the first login shell.

          Guarded so it runs once per session rather than in every new shell,
          and skipped inside tmux because a new pane is not a new login.
        '';
      };

      network = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Print `ip link` and `ip -br a` on the first login shell.

          Linux only `ip` is iproute2 and does not exist on Darwin.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    programs.bash = {
      enable = true;
      enableCompletion = true;

      shellAliases = shared.aliases;

      initExtra = lib.mkMerge [
        (lib.mkIf cfg.viMode # sh
          ''
            set -o vi

            # \1 and \2 mark the non-printing parts of the mode string.
            # Without them readline counts the escape sequence toward the prompt
            # width and wraps lines in the wrong place.
            bind 'set show-mode-in-prompt on'
            bind 'set vi-ins-mode-string \1\e[32m\2[I]\1\e[0m\2 '
            bind 'set vi-cmd-mode-string \1\e[34m\2[N]\1\e[0m\2 '
          ''
        )

        # The shared functions, sourced from files rather than defined inline.
        shared.sourceScript

        shared.initExtra
      ];

      profileExtra = lib.mkMerge [
        ''
          export EDITOR=${cfg.editor}
        ''

        (lib.mkIf (cfg.loginGreeting.fastfetch || cfg.loginGreeting.network) # sh
          ''
            # Once per session, and not inside tmux, because every new pane starts 
            # a login shell.
            if [ -z "''${NS_LOGIN_GREETED:-}" ] && [ -z "''${TMUX:-}" ]; then
            export NS_LOGIN_GREETED=1
            ${lib.optionalString cfg.loginGreeting.fastfetch ''
              command -v fastfetch >/dev/null 2>&1 && ${lib.getExe pkgs.fastfetch}
              printf '\n'
            ''}
            fi
          ''
        )
      ];
    };

    home.packages = lib.optional cfg.loginGreeting.fastfetch pkgs.fastfetch;
  };
}
