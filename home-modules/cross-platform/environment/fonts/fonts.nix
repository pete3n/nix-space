# Font families, packages, and fontconfig defaults.
#
# SEPARATE FROM theme.nix because they are separate concerns that happen to
# meet: this module decides which fonts EXIST and what the system-wide
# defaults are, while theme.nix decides which of them each toolkit uses. A
# machine with no GTK or Qt applications still wants fonts.
#
# theme.nix READS these options for its dconf, GTK, and Qt settings, so the
# family named here is the one those toolkits get — one value rather than the
# four spellings the previous single module carried.
#
# FONT NAMES ARE NOT FUZZY. fontconfig falls back silently on a name it cannot
# resolve, so a typo produces DejaVu Sans rather than an error. The previous
# monospace default was "JetBrains Mono" — with a space — which does not
# exist; the installed family is "JetBrainsMono Nerd Font", so every
# application asking for a default monospace font had been getting a
# proportional sans. Check any change with `fc-match "<name>"`, which prints
# what a name actually resolves to.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.fonts;
in
{
  options.nixSpace.fonts = {
    enable = lib.mkEnableOption "font packages and fontconfig defaults";

    installPackages = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isLinux;
      defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isLinux";
      description = ''
        Install the font packages into the home profile.

        Linux only. macOS resolves fonts through Core Text, which scans 
        ~/Library/Fonts and the system font directories and never looks at the
        Nix profile. Fonts installed here on darwin are invisible to every 
        native application. The terminal renders a fallback rather than 
        reporting a missing family.

        On darwin, feed `allPackages` below to nix-darwin's fonts.packages,
        which installs into /Library/Fonts/Nix Fonts where Core Text finds
        them. This module still owns WHICH fonts; only the delivery differs.
      '';
    };

    allPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      readOnly = true;
      description = ''
        Every font package this module selects, computed from the options
        above. Read-only.

        Exists so the nix-darwin side can install the same set without
        restating it:

          fonts.packages =
            config.home-manager.users.username.nixSpace.fonts.allPackages;
      '';
    };

    ui = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Noto Sans";
        description = ''
          Interface font family.

          A REAL family name, not a fontconfig generic. "Sans Serif" and
          "Sans Regular" both resolve to DejaVu Sans by FALLBACK rather than
          by match, which is how the previous configuration ended up using a
          font it never named.
        '';
      };

      size = lib.mkOption {
        type = lib.types.ints.positive;
        default = 11;
        description = "Interface font size in points.";
      };

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = pkgs.noto-fonts;
        defaultText = lib.literalExpression "pkgs.noto-fonts";
        description = ''
          Package providing the UI font, or null if it comes from elsewhere.

          Null does not disable the setting — the family is still named, it
          just has to be installed by something else or it falls back.
        '';
      };
    };

    monospace = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "JetBrainsMono Nerd Font";
        description = ''
          Monospace font family.

          Note the spelling: "JetBrainsMono" with no space is the installed
          family, while "JetBrains Mono" does not resolve.

          Also the family waybar's stylesheet expects — the bar's icons are
          Nerd Font glyphs, and a family without them renders tofu at the
          wrong metrics, which reads as a broken bar rather than a missing
          font.
        '';
      };

      size = lib.mkOption {
        type = lib.types.ints.positive;
        default = 11;
        description = "Monospace font size in points.";
      };

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = pkgs.nerd-fonts.jetbrains-mono;
        defaultText = lib.literalExpression "pkgs.nerd-fonts.jetbrains-mono";
        description = "Package providing the monospace font.";
      };
    };

    emoji = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "Noto Color Emoji";
        description = "Emoji font family, used as the fontconfig emoji default.";
      };

      packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [
          pkgs.noto-fonts-color-emoji
          pkgs.noto-fonts-monochrome-emoji
        ];
        defaultText = lib.literalExpression ''
          [ pkgs.noto-fonts-color-emoji pkgs.noto-fonts-monochrome-emoji ]
        '';
        description = ''
          Emoji font packages.

          Both colour and monochrome by default: some applications refuse
          colour glyphs and render nothing rather than falling back, so having
          only one variant means emoji work in some places and not others.
        '';
      };
    };

    msCoreFonts = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install Microsoft core fonts (Arial, Times New Roman, and so on).

        This is an unfree font.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.fira-code pkgs.liberation_ttf ]";
      description = "Additional font packages to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixSpace.fonts.allPackages =
      lib.optional (cfg.ui.package != null) cfg.ui.package
      ++ lib.optional (cfg.monospace.package != null) cfg.monospace.package
      ++ cfg.emoji.packages
      ++ lib.optional cfg.msCoreFonts pkgs.corefonts
      ++ cfg.extraPackages;

    home.packages = lib.optionals cfg.installPackages cfg.allPackages;

    # fontconfig is the Linux font resolution path. macOS applications use
    # Core Text.
    fonts.fontconfig = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      enable = true;

      defaultFonts = {
        monospace = [ cfg.monospace.name ];
        emoji = [ cfg.emoji.name ];
      };
    };
  };
}
