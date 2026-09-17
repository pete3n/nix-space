# MPD visualizer widget module: provides cava and album art in popout windows.
#
# Requires hyprland. It attaches on-click-middle to the custom/playerctl widget
# that module defines. Neither imports the other, and waybar.modules merges
# per field.
#
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

  cfg = config.nixSpace.hyprdesktop.mpdVisualizer;
  terminals = config.nixSpace.programs.terminals;

  # Album art viewer: a terminal running chafa, redrawn on track change.
  artViewer = pkgs.writeShellApplication {
    name = "mpd-art-viewer";
    runtimeInputs = with pkgs; [
      chafa
      coreutils
      mpc
    ];

    text = # sh
    ''
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/mpd"
    ''
    + builtins.readFile ./mpd-art-viewer.sh;
  };

  # Both windows are the primary terminal, so they follow
  # nixSpace.programs.terminals.primary rather than pinning one.
  vizCommand = terminals.mkTerminalCommand {
    class = cfg.visualizerClass;
    inherit (cfg) opacity;
    command = lib.getExe pkgs.cava;
  };
  artCommand = terminals.mkTerminalCommand {
    class = cfg.artClass;
    opacity = cfg.artOpacity;
    command = lib.getExe artViewer;
  };

  vizToggle = pkgs.writeShellApplication {
    name = "mpd-viz-toggle";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      config.nixSpace.hyprland.popupHelper.package
    ];

    text = # sh
    ''
      ART_CLASS="${cfg.artClass}"
      ART_TERMINAL_CMD=${lib.escapeShellArg artCommand}
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/mpd"
      VIZ_CLASS="${cfg.visualizerClass}"
      VIZ_TERMINAL_CMD=${lib.escapeShellArg vizCommand}
    ''
    + builtins.readFile ./mpd-viz-toggle.sh;
  };
in
{
  options.nixSpace.hyprdesktop.mpdVisualizer = {
    enable = mkEnableOption "mpd visualizer widget";
    artTerminal = mkOption {
      type = types.enum [
        "kitty"
        "ghostty"
      ];
      default = "ghostty";
      description = ''
        Terminal for the album art window. Alacritty doesn't support graphics output.
      '';
    };

    visualizerClass = mkOption {
      type = types.str;
      default = "com.nixspace.mpdVisualizer";
      description = ''
        Window class of the spectrum window, matched by its rule.
        Reverse-DNS because ghostty validates the class as a GTK application
        ID and rejects anything else.
      '';
    };

    artClass = mkOption {
      type = types.str;
      default = "com.nixspace.mpdArt";
      description = ''
        Window class of the album art window, matched by its rule.

        Reverse-DNS for the same reason as visualizerClass.
      '';
    };

    visualizerSize = mkOption {
      type = types.str;
      default = "900 240";
      description = "Spectrum window size, as Hyprland's \"W H\".";
    };

    artSize = mkOption {
      type = types.str;
      default = "260 240";
      description = ''
        Art window size. Height should match visualizerSize so the two sit
        level, but nothing enforces it.
      '';
    };

    gap = mkOption {
      type = types.ints.unsigned;
      default = 15;
      description = "Pixels between the two windows and from the screen edge.";
    };

    opacity = mkOption {
      type = types.float;
      default = 0.92;
      description = "Spectrum window opacity. The art window uses artOpacity.";
    };

    artOpacity = mkOption {
      type = types.float;
      default = 0.82;
      description = "Art window opacity, usually lower so the art recedes.";
    };
  };

  config = mkIf (config.nixSpace.hyprdesktop.enable && cfg.enable) {
    assertions = [
      {
        # The widget this attaches to is defined by the WAYBAR mpd module, not
        # the daemon one.
        assertion = config.nixSpace.waybar.mpdPlayer.enable;
        message = ''
          mpdVisualizer attaches to the custom/playerctl widget, which
          nixSpace.waybar.mpdPlayer defines, but that module is disabled.
        '';
      }
    ];

    home.packages = [
      artViewer
      vizToggle
      pkgs.cava
      pkgs.chafa
    ];

    # Attaches to the widget linux/mpd/default.nix defines. Only this field is
    # written here; waybar.modules merges per field.
    nixSpace.waybar.modules."custom/playerctl".on-click-middle = lib.getExe vizToggle;

    nixSpace.hyprland.windowRules =
      let
        # Right-aligned, art outermost. Both x offsets derive from the sizes
        # rather than being written as literals — the previous version had
        # `(monitor_w-1175)` with a comment explaining the arithmetic, which
        # went stale the moment a size changed.
        artWidth = lib.toInt (lib.head (lib.splitString " " cfg.artSize));
        visWidth = lib.toInt (lib.head (lib.splitString " " cfg.visualizerSize));

        artX = artWidth + cfg.gap;
        visX = visWidth + artWidth + (cfg.gap * 2);

        barOffset = config.nixSpace.waybar.height + cfg.gap;
      in
      [
        {
          name = "mpd-vis";
          match.class = "^(${cfg.visualizerClass})$";
          float = true;
          pin = true;
          no_initial_focus = true;
          no_anim = true;
          border_size = 0;
          opacity = "${toString cfg.opacity} ${toString cfg.opacity}";
          size = cfg.visualizerSize;
          move = "(monitor_w-${toString visX}) ${toString barOffset}";
        }
        {
          name = "mpd-art";
          match.class = "^(${cfg.artClass})$";
          float = true;
          pin = true;
          no_initial_focus = true;
          no_anim = true;
          border_size = 0;
          opacity = "${toString cfg.artOpacity} ${toString cfg.artOpacity}";
          size = cfg.artSize;
          move = "(monitor_w-${toString artX}) ${toString barOffset}";
        }
      ];
  };
}
