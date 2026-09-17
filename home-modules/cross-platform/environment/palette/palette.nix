# Named color module for cross-platform theming.
#
# Distinct from nixSpace.theme, which selects toolkit theme packages. 
# Anything that renders its own surface rather than inheriting one from a 
# toolkit reads this module: waybar, dunst, which-key, sketchybar, the terminals.
#
# Format: #RRGGBB, no alpha. 
# Transparency is a property of a surface, not of a color. A module wanting a
# translucent panel takes `background` and its own opacity option rather than
# storing #RRGGBBAA here.
#
# Usage: a consumer keeps its own option and changes only the default —
#
#   accentColor = mkOption {
#     default = config.nixSpace.palette.accent;
#     defaultText = lib.literalExpression "config.nixSpace.palette.accent";
#   };
#
# so a host overriding one module's color still works, and nothing changes
# appearance unless the palette's value differs from what the module had.
{
  lib,
  ...
}:
{
  options.nixSpace.palette = {
    background = lib.mkOption {
      type = lib.types.str;
      default = "#1f2335";
      description = ''
        Panel and surface background: the waybar bar, dunst notifications,
        the which-key overlay, the sketchybar bar.
      '';
    };

    foreground = lib.mkOption {
      type = lib.types.str;
      default = "#c0caf5";
      description = ''
        Default text and icon colour on `background`. The resting state for
        anything that is legible but not drawing attention.
      '';
    };

    accent = lib.mkOption {
      type = lib.types.str;
      default = "#7aa2f7";
      description = ''
        Colour for active or focused elements: the waybar module that is
        playing, the focused workspace indicator, the which-key border,
        transport controls.

        The one value most likely to be overridden per host, since it is what
        makes two machines visually distinguishable at a glance.
      '';
    };

    dim = lib.mkOption {
      type = lib.types.str;
      default = "#627180";
      description = ''
        Present but not active: a paused player, an unfocused workspace, a
        disabled toggle.

        Legible against `background` at a glance, which is what separates it
        from `inactive`.
      '';
    };

    inactive = lib.mkOption {
      type = lib.types.str;
      default = "#384047";
      description = ''
        Off or stopped: a stopped player, a shuffle toggle that is off.
      '';
    };

    urgent = lib.mkOption {
      type = lib.types.str;
      default = "#f7768e";
      description = ''
        Demands attention: a critical notification, a battery below its
        threshold, a failed unit.

        Separate from the four above because it is the one colour that must
        stay distinguishable no matter how the rest of the palette is
        retuned.
      '';
    };

    warning = lib.mkOption {
      type = lib.types.str;
      default = "#e0af68";
      description = ''
        Worth noticing but not urgent: a low-but-not-critical battery, a
        degraded but working service.

        Between `dim` and `urgent`. A module with only two states should use
        `dim` and `urgent` rather than reaching for this.
      '';
    };
  };
}
