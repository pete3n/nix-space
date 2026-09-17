# Alacritty terminal module.
#
# Appearance comes from nixSpace.programs.terminals
# See that module for more information.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  shared = config.nixSpace.programs.terminals;
  cfg = config.nixSpace.programs.terminals.alacritty;
  clr = shared.colors;
in
{
  options.nixSpace.programs.terminals.alacritty = {
    enable = lib.mkEnableOption "Alacritty terminal";

    darwinKeybindings = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isDarwin;
      defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isDarwin";
      description = ''
        Add Command-key bindings for copy, paste, quit, and font size.

        Alacritty ships no macOS defaults for these, so without them Cmd+C
        does nothing and the application feels broken to anyone expecting
        native behaviour. On Linux the same actions are already bound to
        Ctrl+Shift.

        Derived from the platform rather than from a lib helper, so pkgs knows
        what it is building for, and this module then needs no arguments
        beyond the standard ones.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.alacritty = {
      enable = true;

      settings = {
        window = {
          decorations = if shared.decorations then "Full" else "None";
          inherit (shared) opacity;
          padding = {
            x = shared.padding;
            y = shared.padding;
          };
        };

        font = {
          normal = {
            family = shared.font.family;
            style = shared.font.style;
          };
          size = shared.font.size;
        };

        colors = {
          primary = {
            inherit (clr) background;
            inherit (clr) foreground;
          };

          cursor = {
            # Alacritty's `text` is the glyph under the cursor, and `cursor`
            # is the block itself, so these are inverted relative to the
            # primary pair on purpose.
            text = clr.cursorText;
            inherit (clr) cursor;
          };

          inherit (clr) normal;
          inherit (clr) bright;
        };

        keyboard.bindings = lib.optionals cfg.darwinKeybindings [
          {
            key = "V";
            mods = "Command";
            action = "Paste";
          }
          {
            key = "C";
            mods = "Command";
            action = "Copy";
          }
          {
            key = "Q";
            mods = "Command";
            action = "Quit";
          }
          {
            key = "N";
            mods = "Command";
            action = "CreateNewWindow";
          }
          {
            key = "Return";
            mods = "Command";
            action = "ToggleFullscreen";
          }
          {
            key = "Key0";
            mods = "Command";
            action = "ResetFontSize";
          }
          {
            key = "Equals";
            mods = "Command";
            action = "IncreaseFontSize";
          }
          {
            key = "Minus";
            mods = "Command";
            action = "DecreaseFontSize";
          }
        ];
      };
    };
  };
}
