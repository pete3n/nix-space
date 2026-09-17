# KDE application integration.
#
# NOT a KDE desktop — this is the plumbing that makes individual KDE
# applications behave when run outside Plasma. Dolphin in particular needs
# several pieces that Plasma would otherwise provide, and without them it
# opens the wrong terminal, shows an empty application menu, and cannot
# preview or browse remote filesystems.
#
# OFF BY DEFAULT. It pulls a substantial slice of the KDE framework, and a
# machine with no KDE applications gains nothing from it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.kde;
in
{
  options.nixSpace.kde = {
    enable = lib.mkEnableOption "KDE application integration outside Plasma";

    terminal = lib.mkOption {
      type = lib.types.str;
      default = "ghostty";
      description = ''
        Terminal KDE applications launch, as a command name.

        Dolphin's "Open Terminal" reads this from kdeglobals, and with no
        value it tries konsole — which is not installed on a machine using
        KDE applications without Plasma.
      '';
    };

    terminalService = lib.mkOption {
      type = lib.types.str;
      default = "Alacritty.desktop";
      description = ''
        The .desktop file matching `terminal`.

        KDE wants both: the command for direct execution and the service file
        for anything going through its launcher. They must name the same
        program, and nothing checks that they do.
      '';
    };

    applicationMenu = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Write a menu definition for kbuildsycoca6.

        Without one, KDE's menu database build produces an empty application
        menu — kbuildsycoca6 needs a menu file to know which directories to
        scan, and Plasma normally supplies it.
      '';
    };

    fileManagerExtras = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install kio-extras, which gives Dolphin thumbnails and remote
        protocols (sftp, smb, mtp).

        Without it those simply do not appear, with no indication that a
        component is missing.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      # kbuildsycoca6, which builds the service and MIME database KDE
      # applications read at startup.
      pkgs.kdePackages.kservice
    ]
    ++ lib.optional cfg.fileManagerExtras pkgs.kdePackages.kio-extras
    ++ lib.optional cfg.applicationMenu pkgs.kdePackages.kmenuedit;

    xdg.configFile."kdeglobals".text = ''
      [General]
      TerminalApplication=${cfg.terminal}
      TerminalService=${cfg.terminalService}
    '';

    # The <n> element is deliberate and not a typo for <Name>: this is the
    # minimum kbuildsycoca6 accepts, and the DefaultAppDirs/DefaultDirectoryDirs
    # entries are what point it at the XDG directories to scan.
    xdg.configFile."menus/applications.menu" = lib.mkIf cfg.applicationMenu {
      text = ''
        <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
          "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">
        <Menu>
          <n>Applications</n>
          <DefaultAppDirs/>
          <DefaultDirectoryDirs/>
          <DefaultMergeDirs/>
        </Menu>
      '';
    };
  };
}
