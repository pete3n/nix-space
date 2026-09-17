# btop better top module with GPU support.
#
# cudaSupport or rocmSupport overrides the package, so changing either
# rebuilds btop from source rather than substituting.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.btop;
in
{
  options.nixSpace.programs.btop = {
    enable = lib.mkEnableOption "btop resource monitor";

    cuda = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Build with NVIDIA GPU monitoring.

        This will rebuild btop from source if a cached binary isn't available.
      '';
    };

    rocm = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Build with AMD GPU monitoring.

        This will rebuild btop from source if a cached binary isn't available.
      '';
    };

    theme = lib.mkOption {
      type = lib.types.str;
      default = "nord";
      description = ''
        Colour theme name.

        Themes ship with the package; an unrecognised name falls back to the
        default rather than erroring.
      '';
    };

    transparentBackground = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Let the terminal's background show through.

        Sets theme_background = false, which is inverted from how it reads.
        The option name refers to whether btop draws a background.
      '';
    };

    vimKeys = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Navigate with hjkl in addition to the arrow keys.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra btop settings, merged over the ones above.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.btop = {
      enable = true;

      package =
        if cfg.cuda || cfg.rocm then
          pkgs.btop.override {
            cudaSupport = cfg.cuda;
            rocmSupport = cfg.rocm;
          }
        else
          # Unoverridden when neither is set, so the cached binary is used
          # rather than a rebuild with both flags false.
          pkgs.btop;

      settings = {
        vim_keys = cfg.vimKeys;
        color_theme = cfg.theme;
        theme_background = !cfg.transparentBackground;
      }
      // cfg.settings;
    };
  };
}
