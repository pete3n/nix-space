# ghostty terminal module.
#
# Appearance comes from nixSpace.programs.terminals: see that module for
# more information.
#
# ghostty writes $XDG_CONFIG_HOME/ghostty/themes/<name> and settings then names
# it with `theme`
#
# Color palette entries carry a leading '#' ("0=#45475a") while background,
# foreground, and cursor-color do NOT ("1e1e2e"). Both forms appear in ghostty's
# own documentation. stripHash below is applied where appropriate.
#
# home-manager runs `ghostty +validate-config` on change, so a mistake here
# surfaces at activation rather than the first time the terminal is opened.
{
  config,
  lib,
  ...
}:
let
  shared = config.nixSpace.programs.terminals;
  cfg = config.nixSpace.programs.terminals.ghostty;
  clr = shared.colors;

  stripHash = lib.removePrefix "#";

  # Palette entries keep the hash; the standalone colour keys drop it.
  paletteEntry = i: color: "${toString i}=${color}";

  themeName = "nixspace";
in
{
  options.nixSpace.programs.terminals.ghostty = {
    enable = lib.mkEnableOption "ghostty terminal";

    systemd = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Use ghostty's systemd user service on Linux.

        Starts the process ahead of the first window, so opening a terminal is
        immediate rather than paying startup cost each time. Ignored on
        Darwin, where the upstream module refuses it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.ghostty = {
      enable = true;

      # NOT setting package. Upstream declares it with mkPackageOption and
      # nullable = true, so it already defaults to pkgs.ghostty and null means
      # DO NOT INSTALL - a wrapper option here would invert that meaning.
      # Anyone needing a specific build sets programs.ghostty.package.

      systemd.enable = cfg.systemd;

      themes.${themeName} = {
        palette = [
          (paletteEntry 0 clr.normal.black)
          (paletteEntry 1 clr.normal.red)
          (paletteEntry 2 clr.normal.green)
          (paletteEntry 3 clr.normal.yellow)
          (paletteEntry 4 clr.normal.blue)
          (paletteEntry 5 clr.normal.magenta)
          (paletteEntry 6 clr.normal.cyan)
          (paletteEntry 7 clr.normal.white)
          (paletteEntry 8 clr.bright.black)
          (paletteEntry 9 clr.bright.red)
          (paletteEntry 10 clr.bright.green)
          (paletteEntry 11 clr.bright.yellow)
          (paletteEntry 12 clr.bright.blue)
          (paletteEntry 13 clr.bright.magenta)
          (paletteEntry 14 clr.bright.cyan)
          (paletteEntry 15 clr.bright.white)
        ];

        background = stripHash clr.background;
        foreground = stripHash clr.foreground;
        cursor-color = stripHash clr.cursor;
        cursor-text = stripHash clr.cursorText;
      };

      settings = {
        theme = themeName;

        font-family = shared.font.family;
        font-size = shared.font.size;

        background-opacity = shared.opacity;
        window-padding-x = shared.padding;
        window-padding-y = shared.padding;
        window-decoration = shared.decorations;
      };
    };
  };
}
