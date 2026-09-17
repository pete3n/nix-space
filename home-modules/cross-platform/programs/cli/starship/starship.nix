# starship - cross-shell prompt module.
#
# Integrates with enabled shells.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.programs.starship;
  shells = config.nixSpace.programs.shells;
in
{
  options.nixSpace.programs.starship = {
    enable = lib.mkEnableOption "starship prompt";

    truncateDirectory = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      example = 3;
      description = ''
        Path components to show before truncating, or null for the full path.

        Null maps to truncation_length = 0, which starship reads as "do not
        truncate", but is mapped here as null for clarity.

        The full path is the right default in a multiplexer, where the window
        title already carries the directory and a truncated prompt duplicates
        it badly.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = lib.literalExpression ''
        {
          git_branch.symbol = "";
          nix_shell.format = "via [$symbol$state]($style) ";
        }
      '';
      description = ''
        Starship settings, merged over the ones above.

        Any additional custom settings belong here. 
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.starship = {
      enable = true;

      enableBashIntegration = shells.bash.enable;
      enableZshIntegration = shells.zsh.enable;

      settings = {
        directory.truncation_length = if cfg.truncateDirectory == null then 0 else cfg.truncateDirectory;
      }
      // cfg.settings;
    };
  };
}
