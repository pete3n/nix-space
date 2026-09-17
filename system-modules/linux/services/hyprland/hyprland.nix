# Hyprland system configuration module.
#
# The module configures the system level aspects of Hyprland: the compositor
# package, portals, polkit, seat management, and PAM entries.
#
# Keybinds, monitor layout, Waybar, and appearance are configured by home-manager
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.hyprland;
in
{
  options.nixSpace.hyprland = {
    enable = lib.mkEnableOption "the Hyprland compositor";

    withUWSM = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Launch Hyprland under the Universal Wayland Session Manager.

        UWSM puts the session in a proper systemd user slice, which makes
        `systemctl --user` units bind to session lifetime and fixes ordering
        for things that expect graphical-session.target. Without it, user
        services that depend on the session start unreliably.

        Disable only if a launch path breaks under it - starting Hyprland from
        a bare tty behaves differently.
      '';
    };

    lockscreen = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Register a PAM stack for hyprlock.

        Without this, hyprlock cannot authenticate and the screen cannot be
        unlocked. It inherits the system default stack, so YubiKey and 
        fingerprint configuration apply.
      '';
    };
  };

  config = {
    programs.hyprland = {
      enable = true;
      withUWSM = cfg.withUWSM;
      xwayland.enable = true;
    };

    # programs.hyprland pulls in xdg.wm.portal-hyprland, which handles
    # screencast and screenshot. It does not provide a file chooser - GTK's
    # portal is what makes "Open File" dialogs work in Electron and Firefox.
    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };

    # An authentication agent must be running for anything that prompts for
    # privilege. Hyprland does not start one; the polkit agent is launched
    # from the home-manager side as a user service.
    security.polkit.enable = true;

    # GTK application settings are read through dconf. Without this, theme and
    # font settings silently fail to apply to GTK apps.
    programs.dconf.enable = true;

    security.pam.services.hyprlock = lib.mkIf cfg.lockscreen { };

    # Wayland-native and XWayland clients both need these present system-wide;
    # a home-manager font install is not visible to the compositor itself.
    fonts.enableDefaultPackages = true;

    # NOTE: no display manager here. Whether this host uses greetd, autologin
    # on a tty, or something else is per-host policy, not a property of
    # running Hyprland. Configure it in the host's configuration.nix.
  };
}
