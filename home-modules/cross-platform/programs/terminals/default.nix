# Shared terminal appearance.
#
# This allows three terminals to share the the same palette, font, and
# opacity configuration.
#
# Each terminal module reads these options and translates:
# alacritty takes a nested attrset of "#rrggbb",
# kitty takes flat keys with different names,
# ghostty takes a list of "N=rrggbb" strings without the hash.
#
# This module is cross-platform, which is why the font family is an option here
# rather than read from nixSpace.fonts, because that module is Linux-only, and
# a terminal module reaching into it would not evaluate on Darwin.
# The two should name the same family because nothing enforces it.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.terminals;
in
{
  imports = [
    ./alacritty
    ./ghostty
    ./kitty
  ];

  options.nixSpace.programs.terminals = {
    primary = lib.mkOption {
      type = lib.types.enum [
        "alacritty"
        "ghostty"
        "kitty"
      ];
      default = "ghostty";
      description = ''
        Selects the default terminal that other modules launch.

        This is separate from enabling a terminal. Multiple terminals can be 
        enabled at the same time, but configurations like a keybind that opens 
        a terminal has to open exactly one.
      '';
    };

    primaryPackage = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = pkgs.${cfg.primary};
      defaultText = lib.literalMD "The package for `primary`.";
      description = ''
        The package named by `primary`, for modules that need to launch it by
        store path.

        readOnly: it is derived from primary.
      '';
    };

    primaryCommand = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = lib.getExe cfg.primaryPackage;
      defaultText = lib.literalMD "`lib.getExe` of `primaryPackage`.";
      description = ''
        Absolute path to the primary terminal's binary.

        A store path rather than a bare name: the callers are keybinds and
        widget click handlers, which run from a compositor or a bar whose PATH
        is whatever it inherited at session start.

        NOTE this is the binary only. Flags for window class and opacity are
        NOT portable between these three: 
        alacritty takes `--class X --option window.opacity=N`, 
        kitty takes `--class X -o background_opacity=N`, 
        ghostty takes `--class=X`. 
        A caller that needs those has to know which terminal it is talking to.
      '';
    };

    font = {
      family = lib.mkOption {
        type = lib.types.str;
        default = "JetBrainsMono Nerd Font";
        description = ''
          Terminal font family.

          Note the spelling — "JetBrainsMono" with no space is the installed
          family, while "JetBrains Mono" does not resolve and falls back
          silently to a proportional font.

          Should match nixSpace.fonts.monospace.name where that module is in
          use. It is not read from there because this module is
          cross-platform and that one is Linux-only.
        '';
      };

      size = lib.mkOption {
        type = lib.types.number;
        default = 18;
        description = ''
          Terminal font size in points.

          A float rather than an integer: kitty and ghostty accept fractional
          sizes.
        '';
      };

      style = lib.mkOption {
        type = lib.types.str;
        default = "Regular";
        description = ''
          Font style for the normal face.

          Only alacritty takes this separately; kitty and ghostty derive bold
          and italic from the family.
        '';
      };
    };

    opacity = lib.mkOption {
      type = lib.types.numbers.between 0.0 1.0;
      default = 0.7;
      description = ''
        Background opacity.

        Requires a compositor doing blur or showing something behind the
        window. On a bare X session this reveals the root window, which is
        usually not what was wanted.
      '';
    };

    padding = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 5;
      description = ''
        Inner padding in pixels, applied on all sides.

        One value rather than x and y: the terminals disagree about how to
        express asymmetric padding, and the asymmetry is rarely wanted.
      '';
    };

    decorations = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Draw window decorations.

        Off by default because a tiling compositor draws its own borders, and
        a title bar on a tiled window is a wasted row.
      '';
    };

    colors = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {
        background = "#090300";
        foreground = "#a5a2a2";

        cursorText = "#090300";
        cursor = "#a5a2a2";

        normal = {
          black = "#090300";
          red = "#db2d20";
          green = "#01a252";
          yellow = "#fded02";
          blue = "#01a0e4";
          magenta = "#a16a94";
          cyan = "#b5e4f4";
          white = "#a5a2a2";
        };

        bright = {
          # Only black and white differ from normal in this scheme: the six
          # hues are shared. The palette gets its contrast from the greys,
          # and duplicating the hues avoids the washed-out "bright" variants
          # many schemes produce.
          black = "#5c5855";
          red = "#db2d20";
          green = "#01a252";
          yellow = "#fded02";
          blue = "#01a0e4";
          magenta = "#a16a94";
          cyan = "#b5e4f4";
          white = "#f7f7f7";
        };
      };

      description = ''
        Colour scheme, in a terminal-neutral shape.

        Each terminal module translates this into its own format because they
        disagree about key names, nesting, and whether a colour carries a
        leading hash.

        Replace the whole attrset to change scheme; the structure is fixed
        because every consumer indexes into it by name.
      '';
    };

    mkTerminalCommand = lib.mkOption {
      type = lib.types.functionTo lib.types.str;
      readOnly = true;
      default =
        {
          class ? null,
          opacity ? null,
          command ? null,
        }:
        let
          classFlag =
            if class == null then
              ""
            else if cfg.primary == "ghostty" then
              " --class=${class}"
            else
              " --class ${class}";

          opacityFlag =
            if opacity == null then
              ""
            else if cfg.primary == "kitty" then
              " -o background_opacity=${toString opacity}"
            else if cfg.primary == "ghostty" then
              " --background-opacity=${toString opacity}"
            else
              " --option window.opacity=${toString opacity}";
        in
        cfg.primaryCommand
        + classFlag
        + opacityFlag
        + lib.optionalString (command != null) " -e ${command}";
      description = ''
        Build a terminal command line with a window class and opacity.

        These flags are spelled differently by each terminal, so a caller that
        needs them cannot use primaryCommand alone. -e is portable and is
        included here only for convenience.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.${cfg.primary}.enable;
        message = ''
          nixSpace.programs.terminals.primary is "${cfg.primary}", but
          nixSpace.programs.terminals.${cfg.primary}.enable is false.

          Other modules launch the primary terminal by store path, so this
          would give keybinds and widget handlers that point at a program the
          profile does not install.
        '';
      }
    ];
  };
}
