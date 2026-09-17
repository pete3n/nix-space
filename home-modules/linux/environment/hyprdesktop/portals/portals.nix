# Hyprland portal preference.
#
# WHAT THIS DOES NOT DO: enable xdg.portal. That option belongs to the SYSTEM
# (programs.hyprland sets it), and home-manager's own portal module conflicts
# with the Hyprland module — which derives xdg.portal.enable from whether it
# is installing a portal package.
#
# The previous configuration set enable = false while still listing
# extraPortals, xdgOpenUsePortal, and a common.default. home-manager ignores
# ALL of those when the module is off, so it read as configured and did
# nothing — and its FileChooser preference named a KDE backend that nothing
# installed, so file dialogs fell back silently.
#
# What remains is the one file that takes effect regardless: a preference list
# read by whichever xdg-desktop-portal the system runs.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.hyprdesktop.portals;
in
{
  options.nixSpace.hyprdesktop.portals = {
    enable = lib.mkEnableOption "Hyprland portal preferences";
    fileChooser = lib.mkOption {
      type = lib.types.enum [
        "gtk"
        "kde"
      ];
      default = "gtk";
      description = ''
        Backend for file open and save dialogs.

        MUST name a backend that is actually installed — the portal has no
        fallback for a named-but-missing implementation, and the symptom is a
        dialog that never appears. Setting "kde" requires
        xdg-desktop-portal-kde on the system, which nixSpace.kde does NOT
        install.

        Check what is available:
          ls /run/current-system/sw/share/xdg-desktop-portal/portals/
      '';
    };
  };

  config = lib.mkIf (config.nixSpace.hyprdesktop.enable && cfg.enable) {
    xdg.configFile."xdg-desktop-portal/hyprland-portals.conf".text = ''
      [preferred]
      default=hyprland;gtk
      org.freedesktop.impl.portal.FileChooser=${cfg.fileChooser}

      # Settings comes from GTK regardless: it carries the colour scheme and
      # font preferences that GTK applications read, and the Hyprland backend
      # does not implement it.
      org.freedesktop.impl.portal.Settings=gtk
    '';
  };
}
