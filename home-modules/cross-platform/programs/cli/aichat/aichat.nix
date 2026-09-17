# aichat module.
# provides a terminal LLM client/REPL with session context scripts.
#
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

  cfg = config.nixSpace.programs.aichat;

  # Renders a session file as Markdown. fzf's preview pane calls it with a
  # line; aichat-search calls it with --full to open the whole file paged.
  aichatPreview = pkgs.writeShellApplication {
    name = "aichat-preview";
    runtimeInputs = with pkgs; [
      bat
      glow
      gnused
    ];
    text = builtins.readFile ./aichat-preview.sh;
  };

	# Search previous sessions in a tmux split pain view.
  aichatSearch = pkgs.writeShellApplication {
    name = "aichat-search";
    runtimeInputs = with pkgs; [
      fzf
      ripgrep
    ];

    text = # sh
    ''
      AICHAT_PREVIEW="${lib.getExe aichatPreview}"
      AICHAT_SESSIONS_DIR="''${AICHAT_SESSIONS_DIR:-$HOME/.config/aichat/sessions}"
    ''
    + builtins.readFile ./aichat-search.sh;
  };

	# Build a system context to pass to models.
  aichatCtx = pkgs.writeShellApplication {
    name = "aichat-ctx";
    runtimeInputs = with pkgs; [
      aichat
      coreutils
    ];

    text = # sh
    ''
      AICHAT_SESSIONS_DIR="''${AICHAT_SESSIONS_DIR:-$HOME/.config/aichat/sessions}"
      API_KEY_FILE="${toString cfg.apiKeyFile}" # Empty when null
      API_KEY_VAR="${cfg.apiKeyVariable}"
    ''
    + builtins.readFile ./aichat-ctx.sh;
  };
in
{
  imports = [ ./local.nix ];

  options.nixSpace.programs.aichat = {
    enable = mkEnableOption "aichat terminal LLM client";

    apiKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/agenix/anthropic-api-key";
      description = ''
        Runtime path to a file containing the API key for the remote provider.

        This is a runtime path, NOT a path literal. A literal is copied to the Nix
        store and is world-readable. This must be readable by this user: an agenix
        secret needs owner set to the user, not root.

        Null disables remote providers; local models via ollama still work.
      '';
    };

    apiKeyVariable = mkOption {
      type = types.str;
      default = "ANTHROPIC_API_KEY";
      description = ''
        Environment variable the key is exported as.
      '';
    };

    defaultRole = mkOption {
      type = types.str;
      default = "nix-env";
      description = "Role used by the ?? alias.";
    };

    defaultContext = mkOption {
      type = types.str;
      default = "nix-space";
      description = "Context used by the ??? alias.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.aichat
      aichatCtx
      aichatSearch
      aichatPreview
    ];

    # Roles and context files
    home.file = {
      ".config/aichat/roles/nix-env.md".source = ./roles/nix-env.md;
      ".config/aichat/contexts/nix-space.md".source = ./contexts/nix-space.md;
    };

    # Aliases only. No initExtra wrapper function: the key is read by
    # aichat-ctx itself, so it works from scripts and keybinds too.
    programs.bash.shellAliases = {
      "??" = "aichat-ctx nix_env --role ${cfg.defaultRole}";
      "???" = "aichat-ctx make_nix --role ${cfg.defaultRole} --session-ctx ${cfg.defaultContext}";
    };
  };
}
