# zsh shell module.
#
# Shared functions come from nixSpace.programs.shells.
# This module handles zsh specific configuration.
#
# Ordering in this module matters in a way it does not for bash.
# initContent is split by mkOrder around oh-my-zsh's own initialisation, which
# runs compinit. Things that must precede it go at 550, everything else at 1000.
# Getting this wrong produces completion that silently does not load rather
# than an error.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.shells.zsh;
  shared = config.nixSpace.programs.shells;
in
{
  options.nixSpace.programs.shells.zsh = {
    enable = lib.mkEnableOption "zsh configuration";

    dotDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.configHome}/zsh";
      defaultText = lib.literalExpression ''"''${config.xdg.configHome}/zsh"'';
      description = ''
        Where .zshrc and friends live.

        The XDG location rather than the home directory: home-manager's
        default is changing to this at stateVersion 26.05, and setting it
        explicitly means the move happens when you choose rather than when
        the version bumps.

        Existing ~/.zshrc content is no longer read after this changes.
      '';
    };

    viMode = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Use vi keybindings at the prompt.

        Sets defaultKeymap rather than adding the oh-my-zsh vi-mode plugin because
        that plugin also adds a mode indicator and rebinds several keys, which
        is more than the keymap alone.
      '';
    };

    syntaxHighlighting = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Colour commands as you type, showing invalid ones in red.";
    };

    autosuggestion = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Suggest completions from history inline as you type.

        Off by default: it redraws on every keystroke, which is noticeable
        over a slow ssh connection, and the suggestion competing with the
        syntax highlighter is visually busy.
      '';
    };

    disableCompfix = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isDarwin;
      defaultText = lib.literalMD "`true` on Darwin.";
      description = ''
        Suppress zsh's "insecure directories" warning at startup.

        macOS ships /usr/local directories that are group-writable, which
        compinit refuses to load from and complains about on every shell
        start.
      '';
    };

    ohMyZsh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Use oh-my-zsh for plugins and prompt.

          It runs compinit itself, which is why this module's ordering is
          expressed with mkOrder rather than plain concatenation.
        '';
      };

      theme = lib.mkOption {
        type = lib.types.str;
        default = "robbyrussell";
        description = "oh-my-zsh theme name.";
      };

      plugins = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "colored-man-pages"
          "git"
        ];
        example = [
          "docker"
          "docker-compose"
          "ssh-agent"
        ];
        description = ''
          oh-my-zsh plugins.

          A short default. Each plugin is loaded at every shell start, and the
          docker ones in particular add completion for a tool that may not be
          installed, which costs startup time for nothing.

          Note "vi-mode" is not here: use the viMode option, which sets the
          keymap without the plugin's extra bindings.
        '';
      };

      sshAgentIdentities = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "id_ed25519" ];
        description = ''
          Keys the ssh-agent plugin loads at startup.

          Only meaningful with "ssh-agent" in plugins. Each is a filename
          under ~/.ssh, and the agent prompts for a passphrase at SHELL START
          rather than at first use, which is why this is empty by default.
        '';
      };

      extraConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Extra configuration evaluated before oh-my-zsh loads.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    warnings =
      lib.optional (cfg.ohMyZsh.sshAgentIdentities != [ ] && !(lib.elem "ssh-agent" cfg.ohMyZsh.plugins))
        ''
          nixSpace.programs.shells.zsh.ohMyZsh.sshAgentIdentities is set but
          "ssh-agent" is not in ohMyZsh.plugins, so nothing reads it.
        '';

    programs.zsh = {
      enable = true;
      enableCompletion = true;
      inherit (cfg) dotDir;

      autosuggestion.enable = cfg.autosuggestion;
      syntaxHighlighting.enable = cfg.syntaxHighlighting;

      defaultKeymap = if cfg.viMode then "viins" else "emacs";

      shellAliases = shared.aliases;

      oh-my-zsh = lib.mkIf cfg.ohMyZsh.enable {
        enable = true;
        theme = cfg.ohMyZsh.theme;
        plugins = cfg.ohMyZsh.plugins;

        extraConfig =
          lib.optionalString (cfg.ohMyZsh.sshAgentIdentities != [ ]) ''
            zstyle :omz:plugins:ssh-agent identities ${lib.concatStringsSep " " cfg.ohMyZsh.sshAgentIdentities}
          ''
          + cfg.ohMyZsh.extraConfig;
      };

      initContent = lib.mkMerge [
        # Ordered before oh-my-zsh runs compinit.
        #
        # ZSH_DISABLE_COMPFIX is read by compinit itself, so setting it after
        # would be too late: the warning would already have printed.
        (lib.mkOrder 550 (
          lib.optionalString cfg.disableCompfix ''
            ZSH_DISABLE_COMPFIX="true"
          ''
        ))

        # Ordered after the shared functions define shell functions and touch
        # PATH, neither of which compinit cares about, so they go last where
        # they can override anything a plugin set up.
        (lib.mkOrder 1000 shared.sourceScript)

        (lib.mkOrder 1000 shared.initExtra)
      ];
    };
  };
}
