# MPD player widgets for waybar: now-playing ticker, transport, shuffle, and
# repeat.
#
# Split from services/mpd, which is the daemon and terminal clients.
# Everything here emits waybar JSON or exists to be bound to a widget.
#
# Requires waybar and a running MPD. Two sibling modules attach to the
# custom/playerctl widget this defines: mpdVisualizer on middle-click, and
# mpdBrowser on right-click. Neither is imported here; waybar.modules merges
# per field, so each contributes only its own binding.
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

  cfg = config.nixSpace.waybar.mpdPlayer;
  accent = config.nixSpace.waybar.accentColor;

  stateDir = "\${XDG_STATE_HOME:-$HOME/.local/state}/mpd";

  ticker = pkgs.writeShellApplication {
    name = "mpd-ticker";
    runtimeInputs = with pkgs; [
      coreutils
      gnused
      jq
      mpc
    ];

    text = # sh
      ''
        MAX_CHARS=${toString cfg.maxLength}
        GAP=${lib.escapeShellArg cfg.ticker.gap}
        STEP=${toString cfg.ticker.step}
        STATE_DIR="${stateDir}"
      ''
      + builtins.readFile ./mpd-ticker.sh;
  };

  shuffleStatus = pkgs.writeShellApplication {
    name = "mpd-shuffle-status";
    runtimeInputs = with pkgs; [
      gawk
      gnugrep
      jq
      mpc
    ];

    text = # sh
      ''
        SHUFFLE_ICON=${lib.escapeShellArg cfg.icons.shuffle}
      ''
      + builtins.readFile ./mpd-shuffle-status.sh;
  };

  repeatStatus = pkgs.writeShellApplication {
    name = "mpd-repeat-status";
    runtimeInputs = with pkgs; [
      gawk
      gnugrep
      jq
      mpc
    ];

    text = # sh
      ''
        REPEAT_OFF_ICON=${lib.escapeShellArg cfg.icons.repeatOff}
        REPEAT_PLAYLIST_ICON=${lib.escapeShellArg cfg.icons.repeatPlaylist}
        REPEAT_TRACK_ICON=${lib.escapeShellArg cfg.icons.repeatTrack}
      ''
      + builtins.readFile ./mpd-repeat-status.sh;
  };

  repeatCycle = pkgs.writeShellApplication {
    name = "mpd-repeat-cycle";
    runtimeInputs = with pkgs; [
      gawk
      gnugrep
      mpc
    ];

    text = builtins.readFile ./mpd-repeat-cycle.sh;
  };

  # Transport goes through playerctl rather than mpc, so the widgets also
  # control whatever MPRIS bridge the daemon module runs.
  playerctl = "${lib.getExe pkgs.playerctl} -p mpd";
in
{
  options.nixSpace.waybar.mpdPlayer = {
    enable = mkEnableOption "MPD waybar widgets";

    maxLength = mkOption {
      type = types.ints.positive;
      default = 35;
      description = ''
        Characters of now-playing text shown before scrolling starts.

        Also the ticker's window width: a title shorter than this is shown
        whole and does not scroll at all.
      '';
    };

    ticker = {
      gap = mkOption {
        type = types.str;
        default = " • ";
        description = ''
          Separator between repeats of the scrolling text.

          Pure spaces make the wrap point invisible, so a looping title reads
          as one that stutters. A visible separator reads as a loop.
        '';
      };

      step = mkOption {
        type = types.ints.positive;
        default = 5;
        description = ''
          Characters advanced per tick.

          With the widget's one-second interval this is the scroll speed.
          Five is brisk; one is smoother but slow through a long title.
        '';
      };
    };

    icons = {
      previous = mkOption {
        type = types.str;
        default = "⏮";
        description = "Previous-track glyph.";
      };
      next = mkOption {
        type = types.str;
        default = "⏭";
        description = "Next-track glyph.";
      };
      shuffle = mkOption {
        type = types.str;
        default = "󰒟";
        description = "Shuffle glyph, styled by CSS class rather than swapped. Needs a Nerd Font.";
      };
      repeatOff = mkOption {
        type = types.str;
        default = "󰑗";
        description = "Repeat-off glyph.";
      };
      repeatPlaylist = mkOption {
        type = types.str;
        default = "󰑖";
        description = "Repeat-playlist glyph.";
      };
      repeatTrack = mkOption {
        type = types.str;
        default = "󰑘";
        description = "Repeat-track glyph.";
      };
    };
  };

  config = mkIf (config.nixSpace.waybar.enable && cfg.enable) {
    assertions = [
      {
        assertion = config.nixSpace.services.mpd.enable;
        message = ''
          nixSpace.waybar.mpdPlayer needs nixSpace.services.mpd: the widgets
          read `mpc status` and drive playerctl, both of which want a running
          daemon and the MPRIS bridge that module provides.
        '';
      }
    ];

    home.packages = [
      ticker
      shuffleStatus
      repeatStatus
      repeatCycle
      pkgs.playerctl
    ];

    nixSpace.waybar.modules = {
      "custom/mpd_prev" = {
        format = cfg.icons.previous;
        tooltip = true;
        tooltip-format = "Previous track";
        on-click = "${playerctl} previous";
        style = # css
          ''
            #custom-mpd_prev {
              color: ${accent};
            }
          '';
      };

      "custom/playerctl" = {
        format = "<span>{}</span>";
        return-type = "json";
        tooltip = true;
        max-length = cfg.maxLength;

        # One second, because the ticker advances its own offset per call.
        # This interval is the scroll rate, not a refresh rate.
        interval = 1;

        exec = lib.getExe ticker;

        on-click = "${playerctl} play-pause";
        on-scroll-up = "${playerctl} next";
        on-scroll-down = "${playerctl} previous";

        # on-click-middle and on-click-right are contributed by mpdVisualizer
        # and mpdBrowser respectively, neither of which need be present.

        style = # css
          ''
            #custom-playerctl.playing {
              color: ${accent};
            }

            #custom-playerctl.paused {
              color: #627180;
            }

            #custom-playerctl.stopped {
              color: #384047;
            }
          '';
      };

      "custom/mpd_next" = {
        format = cfg.icons.next;
        tooltip = true;
        tooltip-format = "Next track";
        on-click = "${playerctl} next";
        style = # css
          ''
            #custom-mpd_next {
              color: ${accent};
            }
          '';
      };

      "custom/mpd_shuffle" = {
        return-type = "json";
        tooltip = true;
        tooltip-format = "Shuffle track";
        exec = lib.getExe shuffleStatus;
        interval = 1;
        on-click = "${lib.getExe pkgs.mpc} random";
        style = # css
          ''
            #custom-mpd_shuffle.on {
              color: ${accent};
            }

            #custom-mpd_shuffle.off {
              color: #6b6b6b;
            }
          '';
      };

      "custom/mpd_repeat" = {
        return-type = "json";
        tooltip = true;
        tooltip-format = "Repeat track/playlist";
        exec = lib.getExe repeatStatus;
        interval = 1;
        on-click = lib.getExe repeatCycle;
        style = # css
          ''
            #custom-mpd_repeat.off {
              color: #6b6b6b;
            }

            #custom-mpd_repeat.playlist,
            #custom-mpd_repeat.track {
              color: ${accent};
            }
          '';
      };
    };
  };
}
