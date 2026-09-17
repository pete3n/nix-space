# Plasma desktop - opinionated bundle.
#
# The counterpart to hyprdesktop, and deliberately much smaller. hyprdesktop
# has to assemble a desktop around a compositor: a bar, notifications, idle
# handling, a locker, wallpaper. Plasma brings all of that itself, so this
# module's job is mostly to enable the application and workflow layers and to
# stay out of Plasma's way.
#
# WHAT THIS DOES NOT DO: manage Plasma's own configuration. Panels, widgets,
# shortcuts, and KWin rules live in ~/.config/*rc files that Plasma rewrites
# during a session — the same ownership problem as Firefox's containers.json.
# Managing them declaratively means plasma-manager, which is not mirrored on
# flakehub and would break the consistency of this library's inputs. So
# Plasma's layout is configured through Plasma, and everything above it is
# configured here.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.plasmadesktop;
in
{
  options.nixSpace.plasmadesktop = {
    enable = lib.mkEnableOption "the opinionated Plasma desktop bundle";

    applications = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable the application and workflow modules alongside Plasma.

        These are desktop-agnostic — a terminal, an editor, a browser, and
        the document tooling do not care which session is running — so the
        same set is enabled here as under hyprdesktop.

        Off leaves a bare Plasma session with only what plasma6 installs,
        which is a reasonable starting point for a host that wants the
        desktop and picks its own applications.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(config.nixSpace.hyprdesktop.enable or false);
        message = ''
          nixSpace.plasmadesktop and nixSpace.hyprdesktop are both enabled.

          They are not additive. Both set defaults for the same things and
          the result is decided by option priority rather than by intent —
          two notification daemons racing for the org.freedesktop.Notifications
          D-Bus name, a waybar with no compositor to attach to, and Qt themed
          twice by two mechanisms.

          Enable one per host. Both bundles are Linux-only and neither is
          importable without the other's options existing, so this is checked
          here rather than being structurally impossible.
        '';
      }
    ];

    nixSpace = {
      theme = {
        qt = lib.mkDefault false;
        gtk = lib.mkDefault false;
      };

      programs.workstationCommon.enable = true;
      security.filevaults.enable = lib.mkIf cfg.applications (lib.mkDefault true);
    };
  };
}
