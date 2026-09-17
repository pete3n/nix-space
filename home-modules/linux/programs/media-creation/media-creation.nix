# Multimedia creation and editing.
#
# CUDA-accelerated Blender comes from overlays/cuda.nix, applied where
# pkgs is constructed and enabled with the cuda tag.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.mediaCreation;
in
{
  options.nixSpace.programs.mediaCreation = {
    enable = lib.mkEnableOption "multimedia creation and editing tools";

    audio = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Audacity (editor) and Bitwig Studio (DAW).";
    };

    graphics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        GIMP with plugins, and Inkscape with extensions.

        The -with-plugins and -with-extensions variants are separate
        derivations, so switching to the plain packages is a rebuild, not a
        smaller closure of the same build.
      '';
    };

    video = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Kdenlive (editor) and HandBrake (transcoding).";
    };

    threeD = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Blender.

        Picks up CUDA support automatically when the cuda tag is set, via the
        overlay. Nothing to configure here.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.krita pkgs.darktable ]";
      description = ''
        Additional tools, for anything not worth its own option.

        A package list, not names: the caller has pkgs in scope and can
        override or pin, which a string list would not allow.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      lib.optionals cfg.audio [
        pkgs.audacity
        pkgs.bitwig-studio # unfree
      ]
      ++ lib.optionals cfg.graphics [
        pkgs.gimp-with-plugins
        pkgs.inkscape-with-extensions
      ]
      ++ lib.optionals cfg.video [
        pkgs.kdePackages.kdenlive
        pkgs.handbrake
      ]
      ++ lib.optional cfg.threeD pkgs.blender
      ++ cfg.extraPackages;
  };
}
