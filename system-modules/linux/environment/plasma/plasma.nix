# KDE Plasma system configuration module.
#
# The module configures the system level aspects of Plasma: the desktop
# session, Qt integration, and package selection.
#
# Panels, shortcuts, theming, and KWin rules are configured by home-manager
# through plasma-manager.
#
# CONTRAST WITH hyprland.nix: Hyprland is a compositor, so that module has to
# assemble a desktop around it — portals, polkit, PAM for the locker. Plasma
# is a desktop, and services.desktopManager.plasma6 brings its own portal
# (xdg-desktop-portal-kde), starts polkit-kde-agent as part of
# plasma-workspace, and registers PAM for kscreenlocker itself. So this module
# is mostly about what to REMOVE rather than what to add.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.plasma;
in
{
  options.nixSpace.plasma = {
    enable = lib.mkEnableOption "Plasma environment configuration.";

    qt5Integration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the Qt5 platform theme alongside Qt6.

        Plasma 6 is Qt6, and a Qt5 application without this renders with the
        default Fusion style rather than Breeze — visibly out of place rather
        than broken. Costs a second Qt stack in the closure.

        Off is reasonable on a machine running nothing older than Qt6, which
        is increasingly most of them.
      '';
    };

    excludePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression ''
        with pkgs.kdePackages; [
          elisa
          khelpcenter
          konsole
          oxygen
        ]
      '';
      description = ''
        Plasma packages to leave out of the system profile.

        plasma6 installs a full desktop: a music player, a help centre, a
        terminal, a text editor, and more. Most of those duplicate something
        already chosen elsewhere — konsole against the terminals module, kate
        against nixvim, elisa against the media module — and a duplicate that
        is also the MIME handler for its file types will win associations you
        set deliberately.

        This is the system-level list. It cannot remove something a
        home-manager module installs.
      '';
    };

    kdeConnect = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable KDE Connect for phone integration.

        Off by default because it is not only a package: it OPENS FIREWALL
        PORTS (UDP and TCP 1714-1764) for device discovery on the local
        network. That is a deliberate exposure rather than a convenience,
        and it should be an explicit choice per host.
      '';
    };
  };

  config = {
    services.desktopManager.plasma6 = {
      enable = true;
      enableQt5Integration = cfg.qt5Integration;
    };

    environment.plasma6.excludePackages = cfg.excludePackages;

    # GTK application settings are read through dconf. Plasma theming reaches
    # GTK applications through its own bridge, but that bridge writes dconf —
    # without this, GTK apps silently keep their defaults.
    programs.dconf.enable = true;

    programs.kdeconnect.enable = cfg.kdeConnect;

    # Wayland-native and XWayland clients both need these present system-wide;
    # a home-manager font install is not visible to the session itself.
    fonts.enableDefaultPackages = true;

    # NOTE: no display manager here, matching hyprland.nix. SDDM is the
    # conventional pairing and services.displayManager.sddm.wayland.enable is
    # what gets you a Wayland session from it — but whether this host uses
    # SDDM, greetd, or autologin is per-host policy, not a property of running
    # Plasma. Configure it in the host's configuration.nix.
    #
    # NOTE: no xdg.portal block. plasma6 provides xdg-desktop-portal-kde,
    # which handles the file chooser as well as screencast — unlike
    # portal-hyprland, which needs the GTK portal alongside it for file
    # dialogs.
    #
    # NOTE: no security.polkit.enable and no PAM entries. plasma-workspace
    # starts polkit-kde-agent itself, and the plasma6 module registers PAM for
    # kscreenlocker. Verify with `systemctl --user status plasma-polkit-agent`
    # if an authentication prompt fails to appear.
  };
}
