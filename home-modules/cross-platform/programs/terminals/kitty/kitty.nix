# kitty terminal module.
#
# Appearance comes from nixSpace.programs.terminals: see that module for more
# information.
#
# kitty's config is flat: no nesting, and colours are named color0 through
# color15 by ANSI index rather than by name.
#
# Booleans are converted. home-manager runs settings values through
# lib.hm.booleans.yesNo, so a Nix bool becomes kitty's yes/no.
{
  config,
  lib,
  ...
}:
let
  shared = config.nixSpace.programs.terminals;
  cfg = config.nixSpace.programs.terminals.kitty;
  clr = shared.colors;
in
{
  options.nixSpace.programs.terminals.kitty = {
    enable = lib.mkEnableOption "kitty terminal";

    shellIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable kitty's shell integration.

        Gives prompt marking, so jumping between commands and opening the last
        command's output in a pager work.

        This sets mode to "no-rc", NOT "enabled" - kitty has no such value,
        and an unrecognised mode is rejected. no-rc means integration is
        active but kitty does not modify shell rc files itself; home-manager
        sources the integration script instead, which keeps the shell config
        declarative.
      '';
    };

    gitIntegration = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use `kitten diff` as git's difftool.

        Off by default because it changes git's behaviour globally: a diff
        opened from any terminal will try to launch kitty, including from a
        session where kitty is not running.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.kitty = {
      enable = true;

      font = {
        name = shared.font.family;
        size = shared.font.size;
      };

      shellIntegration.mode = if cfg.shellIntegration then "no-rc" else "disabled";

      enableGitIntegration = cfg.gitIntegration;

      settings = {
        # A float, not a string.
        background_opacity = shared.opacity;

        window_padding_width = shared.padding;

        # A bool, converted to yes/no by home-manager. kitty also accepts
        # "titlebar-only", which is why the option here is a bool rather than
        # a passthrough.
        hide_window_decorations = !shared.decorations;

        inherit (clr) background;
        inherit (clr) foreground;

        # kitty inverts alacritty's naming: `cursor` is the block, and
        # `cursor_text_color` is the glyph beneath it.
        inherit (clr) cursor;
        cursor_text_color = clr.cursorText;

        color0 = clr.normal.black;
        color1 = clr.normal.red;
        color2 = clr.normal.green;
        color3 = clr.normal.yellow;
        color4 = clr.normal.blue;
        color5 = clr.normal.magenta;
        color6 = clr.normal.cyan;
        color7 = clr.normal.white;

        color8 = clr.bright.black;
        color9 = clr.bright.red;
        color10 = clr.bright.green;
        color11 = clr.bright.yellow;
        color12 = clr.bright.blue;
        color13 = clr.bright.magenta;
        color14 = clr.bright.cyan;
        color15 = clr.bright.white;
      };
    };
  };
}
