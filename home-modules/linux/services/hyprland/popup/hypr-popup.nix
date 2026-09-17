# hypr-popup module. 
#
# Enableds querying and closing class-tagged popup windows.
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

  cfg = config.nixSpace.hyprland;

  # `or pkgs.hyprland` does NOT help here: finalPackage EXISTS and is null
  # when the preset sets package = null (the system provides the compositor).
  # `or` tests attribute presence, not nullness.
  hyprPkg =
    if config.wayland.windowManager.hyprland.finalPackage != null then
      config.wayland.windowManager.hyprland.finalPackage
    else
      pkgs.hyprland;

  hyprPopup = pkgs.writeShellApplication {
    name = "hypr-popup";
    runtimeInputs = [
      hyprPkg
      pkgs.coreutils
    ];
    text = builtins.readFile ./hypr-popup.sh;
  };
in
{
  options.nixSpace.hyprland.popupHelper = {
    enable = mkEnableOption "popup helper" // {
      default = true;
      description = ''
        Install hypr-popup, used by the calendar, mpd visualiser, and any other
        class-tagged popup.
      '';
    };

    package = mkOption {
      type = types.package;
      readOnly = true;
      default = hyprPopup;
      defaultText = lib.literalMD "the hypr-popup helper";
      description = ''
        The built hypr-popup, for other modules to put on a script's
        runtimeInputs rather than relying on it being on the session PATH.
      '';
    };
  };

  config = mkIf (cfg.enable && cfg.popupHelper.enable) {
    home.packages = [ cfg.popupHelper.package ];
  };
}
