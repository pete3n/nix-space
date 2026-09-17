# XDG base directories, user directories, and MIME associations.
#
# COMPOSITOR-INDEPENDENT — nothing here knows about a window manager. The
# Hyprland portal preference lives in wm/hyprland/desktop/, and KDE application
# integration in linux/kde.nix; both were mixed into this file previously,
# which is why it carried a hyprland tag check.
#
# PARTIALLY PLATFORM-INDEPENDENT, which is why it sits at the root rather than
# under linux/. The base directories and the exported user-dir variables are
# portable and are what nb, yazi, bat, and git resolve their config through.
# MIME associations are not: macOS routes file handling through LaunchServices
# and UTIs and never reads mimeapps.list, so that part defaults off there.
#
# NO PORTAL CONFIGURATION. home-manager's xdg.portal module conflicts with the
# Hyprland module, which sets xdg.portal.enable from whether it is installing
# a portal package — and the system already provides portals through
# programs.hyprland. The previous version set enable = false while still
# listing extraPortals and a common.default, all of which home-manager ignores
# when the module is off: configuration that looked active and was not. A
# FileChooser preference pointed at a KDE backend nothing installed.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.xdg;
  home = config.home.homeDirectory;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  options.nixSpace.xdg = {
    enable = lib.mkEnableOption "XDG user directories and MIME associations";

    userDirs = {
      enable = lib.mkEnableOption "XDG user directories" // {
        default = true;
        description = ''
          Write ~/.config/user-dirs.dirs and export the paths as session
          variables.

          Applications read these to decide where a download or a screenshot
          goes. Without them each one picks its own default, so files scatter.

          On darwin no native application reads the file, but the exported
          variables are still worth having: portable CLI tools consult
          XDG_DOCUMENTS_DIR and friends, and the fallback when they are unset
          is each tool's own guess.
        '';
      };

      videos = lib.mkOption {
        type = lib.types.str;
        default = if isLinux then "${home}/Videos" else "${home}/Movies";
        defaultText = lib.literalMD "`~/Videos` on Linux, `~/Movies` on darwin";
        description = ''
          Video directory.

          Platform-derived because the conventional name differs: macOS ships
          ~/Movies and has no ~/Videos. Exporting a path that does not exist
          is the quiet failure — a caller testing `[ -d "$dir" ]` takes its
          fallback branch rather than reporting anything.
        '';
      };

      projects = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "${home}/Projects";
        defaultText = lib.literalExpression "\"\${config.home.homeDirectory}/Projects\"";
        description = ''
          Directory exported as a project location, or null to omit it.

          Written as `PROJECT` in extraConfig; home-manager derives the
          variable name and currently emits BOTH XDG_PROJECTS_DIR and
          XDG_PROJECT_DIR — the second is a compatibility shim from the older
          interface, which took the full variable name directly.

          Not part of the freedesktop spec, so only things specifically
          looking for it will find it.
        '';
      };
    };

    mimeApps = {
      enable = lib.mkEnableOption "MIME type associations" // {
        default = isLinux;
        defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isLinux";
        description = ''
          Write ~/.config/mimeapps.list.

          Defaults to the platform rather than to true: macOS resolves file
          handlers through LaunchServices and UTIs, so the file is written and
          nothing ever consults it.

          NOTHING HERE INSTALLS THE APPLICATIONS. An association names a
          .desktop file, and pointing at one that does not exist makes the
          handler silently fall back — so the defaults below are empty and
          each association is opt-in.
        '';
      };

      defaults = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        example = lib.literalExpression ''
          {
            "application/pdf" = [ "org.pwmt.zathura.desktop" ];
            "video/mp4" = [ "vlc.desktop" ];
          }
        '';
        description = ''
          MIME type to .desktop file, for both defaultApplications and
          associations.added.

          Written to both because they answer different questions —
          `added` says an application CAN open this type, `default` says it
          SHOULD. Setting only the second leaves the type absent from
          "Open With" menus.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.mimeApps.enable && !isLinux);
        message = ''
          nixSpace.xdg.mimeApps is enabled on a non-Linux host. mimeapps.list
          is a freedesktop mechanism; macOS uses LaunchServices, so the file
          would be written and never read.
        '';
      }
    ];

    xdg.enable = true;

    xdg.userDirs = lib.mkIf cfg.userDirs.enable {
      enable = true;
      setSessionVariables = true;

      # config.home.homeDirectory rather than "/home/${user}" — the latter
      # assumes the path shape, which is wrong on Darwin and on any host with
      # a non-standard home.
      documents = "${home}/Documents";
      download = "${home}/Downloads";
      music = "${home}/Music";
      pictures = "${home}/Pictures";
      publicShare = "${home}/Public";
      templates = "${home}/Templates";
      inherit (cfg.userDirs) videos;

      # Bare name, not XDG_PROJECT_DIR. home-manager prefixes and suffixes it
      # itself, and passing the full variable name is deprecated — it produced
      # XDG_XDG_PROJECT_DIR_DIR in older versions, which is why the interface
      # changed.
      extraConfig = lib.optionalAttrs (cfg.userDirs.projects != null) {
        PROJECT = cfg.userDirs.projects;
      };
    };

    xdg.mimeApps = lib.mkIf cfg.mimeApps.enable {
      enable = true;
      defaultApplications = cfg.mimeApps.defaults;
      associations.added = cfg.mimeApps.defaults;
    };

    # Both are freedesktop tooling with nothing to act on outside Linux:
    # update-desktop-database rebuilds a .desktop cache macOS does not have,
    # and xdg-user-dirs-update maintains a file no native application reads.
    home.packages = lib.optionals isLinux [
      # update-desktop-database, which rebuilds the MIME cache. Without it a
      # newly installed application's associations are not seen until
      # something else triggers a rebuild.
      pkgs.desktop-file-utils
      pkgs.xdg-user-dirs
    ];
  };
}
