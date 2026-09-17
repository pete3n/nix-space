# sketchybar status bar for macOS.
#   https://felixkratz.github.io/SketchyBar/
#
# The darwin counterpart to nixSpace.waybar. Workspace indicators are
# AeroSpace-specific and appear only when that module is enabled; the clock
# and battery items have no such dependency.
#
# COORDINATION WITH AEROSPACE: the workspace indicators subscribe to a custom
# event, aerospace_workspace_change, which nothing fires unless AeroSpace's
# exec-on-workspace-change triggers it. That setting is contributed HERE, to
# programs.aerospace, when both modules are on — the consumer of the event
# wires the producer, the same way firefox contributes its Hyprland window
# rule. The previous version subscribed to the event and left it unfired.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;

  cfg = config.nixSpace.sketchybar;
  aerospace = config.nixSpace.aerospace;
  aerospaceOn = aerospace.enable or false;

  # Workspace list derived from the AeroSpace module rather than restated, so
  # the two cannot drift.
  workspaces = lib.optionalString aerospaceOn (
    lib.concatStringsSep " " (
      map toString (lib.range 1 aerospace.workspaces) ++ [ aerospace.scratchpadWorkspace ]
    )
  );

  highlight = pkgs.writeShellApplication {
    name = "sketchybar-workspace-highlight";
    runtimeInputs = [ pkgs.sketchybar ];
    text = # sh
      ''
        ACTIVE_COLOR=${cfg.colors.active}
        ITEM_COLOR=${cfg.colors.item}
      ''
      + builtins.readFile ./workspace-highlight.sh;
  };

  # sketchybar's ARGB hex takes the form 0xAARRGGBB. Options are given as
  # #RRGGBB for consistency with every other colour in nixSpace, and the
  # alpha is fixed at opaque.
  argb = hex: "0xff${lib.removePrefix "#" hex}";
in
{
  options.nixSpace.sketchybar = {
    enable = mkEnableOption "the sketchybar status bar";

    height = mkOption {
      type = types.ints.positive;
      default = 25;
      description = "Bar height in points.";
    };

    position = mkOption {
      type = types.enum [
        "top"
        "bottom"
      ];
      default = "top";
      description = "Screen edge the bar is attached to.";
    };

    padding = mkOption {
      type = types.ints.unsigned;
      default = 15;
      description = "Horizontal padding at both ends of the bar, in points.";
    };

    font = {
      name = mkOption {
        type = types.str;
        default = config.nixSpace.fonts.monospace.name;
        defaultText = lib.literalExpression "config.nixSpace.fonts.monospace.name";
        description = ''
          Font family for all items. Defaults to the fonts module's monospace
          face — the workspace indicators and any glyphs need a Nerd Font,
          and that option is where one is declared.
        '';
      };

      size = mkOption {
        type = types.float;
        default = 14.0;
        description = "Font size in points, for both icons and labels.";
      };
    };

    colors = {
      bar = mkOption {
        type = types.str;
        default = "#1f2335";
        description = "Bar background, as #RRGGBB. Alpha is fixed opaque.";
      };

      item = mkOption {
        type = types.str;
        default = "#7ebae4";
        description = "Default icon and label colour, and the inactive workspace colour.";
      };

      active = mkOption {
        type = types.str;
        default = "#5277c3";
        description = "Focused workspace indicator colour.";
      };
    };

    clock = mkOption {
      type = types.bool;
      default = true;
      description = "Centre clock item, updating every second.";
    };

    battery = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Right-side battery percentage, read from pmset once a minute.
        Reasonable to turn off on a desktop, where it shows nothing useful.
      '';
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = ''
        Additional sketchybar commands, appended after the generated config
        and before the final --update. For items this module does not know
        about.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "nixSpace.sketchybar is a macOS status bar and cannot be enabled on ${pkgs.stdenv.hostPlatform.system}.";
      }
    ];

    programs.sketchybar = {
      enable = true;
      service.enable = true;

      # aerospace on the bar's PATH, because the workspace items' click_script
      # invokes it by name. Only when the indicators exist to need it.
      extraPackages = lib.optional aerospaceOn pkgs.aerospace;

      config = # sh
        ''
          BAR_COLOR=${argb cfg.colors.bar}
          ITEM_COLOR=${argb cfg.colors.item}
          FONT=${lib.escapeShellArg cfg.font.name}
          FONT_SIZE=${toString cfg.font.size}
          HEIGHT=${toString cfg.height}
          POSITION=${cfg.position}
          PADDING=${toString cfg.padding}
          WORKSPACES=${lib.escapeShellArg workspaces}
          HIGHLIGHT_SCRIPT=${lib.getExe highlight}
          CLOCK=${if cfg.clock then "1" else "0"}
          BATTERY=${if cfg.battery then "1" else "0"}
        ''
        + builtins.readFile ./sketchybarrc.sh
        + lib.optionalString (cfg.extraConfig != "") ''

          ${cfg.extraConfig}
          sketchybar --update
        '';
    };

    # The producer side of the workspace event. AeroSpace runs this on every
    # workspace change, and the environment variable is what the highlight
    # script reads.
    programs.aerospace.settings.exec-on-workspace-change = mkIf aerospaceOn [
      "/bin/bash"
      "-c"
      "${lib.getExe pkgs.sketchybar} --trigger aerospace_workspace_change AEROSPACE_FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE"
    ];
  };
}
