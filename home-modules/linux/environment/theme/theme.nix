# GTK, Qt, cursor, and font theming.
#
# ONE SOURCE PER VALUE. The previous configuration named the icon theme four
# times and the cursor three. Every option here feeds several places at once,
# so a change lands everywhere or nowhere.
#
# FONTS LIVE IN fonts.nix. This module READS nixSpace.fonts for its dconf,
# GTK, and Qt settings rather than declaring families of its own — which
# family a toolkit uses is theming, but which fonts exist on the machine is
# not, and mixing them made "theme" the surprising place to look for font
# configuration.
#
# WHY BOTH GTK AND QT. They share no theming mechanism: GTK reads settings.ini
# and dconf, Qt reads a platform theme plugin pointed at qt5ct/qt6ct configs.
# A machine running both toolkits needs both configured or half its
# applications look unthemed.

{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.theme;
  fonts = config.nixSpace.fonts;

  # Qt font descriptors are a comma-separated struct, not a name — the
  # trailing fields are weight, style, and stretch flags that qt5ct writes
  # itself. Built here so the family and size come from the same options GTK
  # uses rather than being restated.
  qtFont = family: size: ''"${family},${toString size},-1,5,50,0,0,0,0,0"'';

  qtAppearance = {
    style = "kvantum";
    icon_theme = cfg.iconTheme.name;

    # File dialogs go through the portal rather than Qt's own, so a Qt
    # application gets the same picker as a GTK one. Which backend that is
    # comes from nixSpace.hyprdesktop.portals.fileChooser.
    standard_dialogs = "xdgdesktopportal";

    color_scheme_path = "";
    custom_palette = false;
  };

  qtFonts = {
    fixed = qtFont fonts.monospace.name fonts.monospace.size;
    general = qtFont fonts.ui.name fonts.ui.size;
  };
in
{
  options.nixSpace.theme = {
    enable = lib.mkEnableOption "GTK, Qt, cursor, and font theming";

    gtk = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Theme GTK applications through gtk3/gtk4 settings and dconf.

        MUST BE FALSE UNDER PLASMA. plasma-workspace includes kde-gtk-config,
        which writes ~/.gtkrc-2.0 and ~/.config/gtk-3.0/settings.ini itself to
        propagate the Plasma appearance settings to GTK applications. It does
        this at session start and on every appearance change, so the two
        compete: home-manager's activation reports that the file would be
        clobbered, and whichever wrote last is what GTK reads.

        Turning this off leaves Plasma's bridge as the single writer, which is
        what System Settings' appearance page expects.

        Cursors are NOT covered by this toggle — see pointerCursor below.
      '';
    };

    gtkTheme = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Tokyonight-Dark";
        description = "GTK theme name, as installed by `package`.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.tokyonight-gtk-theme;
        defaultText = lib.literalExpression "pkgs.tokyonight-gtk-theme";
        description = ''
          Package providing the GTK theme.

          Must actually contain a theme directory matching `name` — a
          mismatch leaves applications unthemed with no error, since GTK
          treats a missing theme as "use the default".
        '';
      };
    };

    qt = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Theme Qt applications through qt6ct/qt5ct and Kvantum.

        MUST BE FALSE UNDER PLASMA. Plasma manages Qt theming itself through
        plasma-workspace, and setting QT_QPA_PLATFORMTHEME=qtct overrides
        that — applications come up with the Kvantum theme instead of Breeze,
        including Plasma's own, and System Settings appears to have no effect
        because its writes are being ignored at runtime.

        GTK, cursor, and icon theming are unaffected by this and stay on.
        Those are the parts a Plasma session still wants from this module,
        since Plasma's GTK bridge only covers some of it.

        Turning this off also skips Kvantum and its style plugin, which have
        nothing to read them without qtct.
      '';
    };

    iconTheme = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Yaru-magenta";
        description = ''
          Icon theme name.

          Used by GTK, dconf, and both Qt config files — one value feeding
          four places.
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.yaru-theme;
        defaultText = lib.literalExpression "pkgs.yaru-theme";
        description = "Package providing the icon theme.";
      };
    };

    cursorTheme = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Bibata-Modern-Classic";
        description = "Cursor theme name.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.bibata-cursors;
        defaultText = lib.literalExpression "pkgs.bibata-cursors";
        description = "Package providing the cursor theme.";
      };

      size = lib.mkOption {
        type = lib.types.ints.positive;
        default = 16;
        description = ''
          Cursor size in pixels.

          The compositor reads this from XCURSOR_SIZE, which the Hyprland
          preset sets separately — the two should agree, and nothing checks
          that they do.
        '';
      };
    };

    themeTools = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install gnome-tweaks and themechanger.

        OFF BY DEFAULT because they fight this module. Both write dconf, and
        home-manager rewrites dconf on every switch — so a change made in one
        of these survives until the next rebuild and then silently reverts.

        Useful for PREVIEWING a theme before writing it into configuration,
        which is a different thing from configuring with them.
      '';
    };

    # Close equivalent to Tokyo Night
    kvantumTheme = lib.mkOption {
      type = lib.types.str;
      default = "KvArcDark";
      description = ''
        Kvantum theme for Qt applications.

        Deliberately not derived from gtkTheme.name: Kvantum themes are a
        separate, smaller set, and there is no Tokyo Night among the bundled
        ones, so Qt applications are the closest available match rather than
        an exact one. A name Kvantum does not have leaves Qt applications
        unstyled with no error.

        `ls ${pkgs.kdePackages.qtstyleplugin-kvantum}/share/Kvantum` lists
        what is available.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.nixSpace.fonts.enable;
        message = ''
          nixSpace.theme needs nixSpace.fonts — the GTK, Qt, and dconf
          settings below name the families that module installs.

          Without it the names are still written but nothing provides them,
          and fontconfig falls back SILENTLY: the interface renders in
          DejaVu Sans and nothing indicates a font is missing.
        '';
      }
    ];

    home.packages = [
      pkgs.dconf
      pkgs.gnome-tweaks
      pkgs.themechanger
    ]
    ++ lib.optional cfg.qt pkgs.kdePackages.qtstyleplugin-kvantum;

    # pointerCursor writes the cursor for GTK, X11, and the session
    # environment from one definition. gtk.cursorTheme is NOT set separately
    # below — this already covers it, and two definitions of the same thing is
    # one to forget when changing it.
    home.pointerCursor = {
      gtk.enable = cfg.gtk;
      package = cfg.cursorTheme.package;
      name = cfg.cursorTheme.name;
      size = cfg.cursorTheme.size;
    };

    dconf = lib.mkIf cfg.gtk {
      enable = true;
      settings."org/gnome/desktop/interface" = {
        # GTK4 applications built on libadwaita ignore gtk-theme entirely and
        # follow this instead, so it is the only way to make them dark.
        color-scheme = "prefer-dark";

        gtk-theme = cfg.gtkTheme.name;
        icon-theme = cfg.iconTheme.name;
        cursor-theme = cfg.cursorTheme.name;
        font-name = "${fonts.ui.name} ${toString fonts.ui.size}";
      };
    };

    gtk = lib.mkIf cfg.gtk {
      enable = true;

      gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;

      gtk4 = {
        # NULL, deliberately. GTK4 applications use libadwaita, which does not
        # read GTK3-style themes — pointing it at one produces a mix of themed
        # and unthemed widgets rather than a themed application.
        theme = null;
        extraConfig.gtk-application-prefer-dark-theme = 1;
      };

      font = {
        name = fonts.ui.name;
        size = fonts.ui.size;
      };

      iconTheme = {
        name = cfg.iconTheme.name;
        package = cfg.iconTheme.package;
      };

      theme = {
        name = cfg.gtkTheme.name;
        package = cfg.gtkTheme.package;
      };
    };

    qt = lib.mkIf cfg.qt {
      enable = true;

      # qtct rather than gtk3: the gtk3 platform theme makes Qt applications
      # read GTK settings directly, which works for colours and not for icons
      # or fonts. qtct reads the qt5ct/qt6ct files written below.
      platformTheme.name = "qtct";

      style = {
        name = cfg.kvantumTheme;
        package = pkgs.kdePackages.qtstyleplugin-kvantum;
      };

      # Qt5 and Qt6 read separate files and share nothing, so both get the
      # same content from the same options.
      qt5ctSettings = {
        Appearance = qtAppearance;
        Fonts = qtFonts;
      };

      qt6ctSettings = {
        Appearance = qtAppearance;
        Fonts = qtFonts;
      };

    };

    xdg.configFile."Kvantum/kvantum.kvconfig" = lib.mkIf cfg.qt {
      text = ''
        [General]
        theme=${cfg.kvantumTheme}
      '';
    };
  };
}
