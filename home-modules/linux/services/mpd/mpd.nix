# MPD daemon and terminal client user service module.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.services.mpd;
in
{
  options.nixSpace.services.mpd = {
    enable = lib.mkEnableOption "MPD daemon and clients";

    musicDirectory = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.userDirs.music}";
      defaultText = lib.literalExpression "config.xdg.userDirs.music";
      description = ''
        Directory mpd scans for music.

        Defaults to the XDG music directory so it follows nixSpace.xdg rather
        than being stated twice, ncmpcpp reads this same value to know where
        the library lives, and the two disagreeing means the client browses a
        different tree than the daemon indexes.
      '';
    };

    audioOutput = lib.mkOption {
      type = lib.types.enum [
        "pipewire"
        "pulse"
        "alsa"
      ];
      default = "pipewire";
      description = "MPD audio output backend.";
    };

    visualizerFifo = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Add a FIFO audio output for visualisers.

          A visualiser cannot read the audio device directly, so mpd writes a
          second copy of the stream to a named pipe that ncmpcpp and cava read
          instead.
        '';
      };

      path = lib.mkOption {
        type = lib.types.str;
        default = "${config.xdg.dataHome}/mpd/mpd.fifo";
        description = ''
          FIFO path, shared by the mpd output and every visualiser reading it.
        '';
      };

      outputName = lib.mkOption {
        type = lib.types.str;
        default = "mpd_fifo";
        description = ''
          Name of the FIFO audio output.

          This must match ncmpcpp's visualizer_output_name, which is how ncmpcpp
          finds the output to toggle. 
        '';
      };

      stereo = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Write two channels to the FIFO instead of one.

          This must agree with ncmpcpp's visualizer_in_stereo.
        '';
      };
    };

    clients = {
      ncmpcpp = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install and configure ncmpcpp, the terminal client.";
      };

      cava = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install cava, the standalone spectrum visualiser.

          NOTE: Also used by the mpd visualizer widget: that module reads this
          package rather than installing its own, so the two cannot end up on
          different versions.
        '';
      };

      metadataEditor = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install Picard for fixing track metadata.

          Off by default: it is a Qt application with a substantial closure,
          and it is a tool used occasionally rather than part of playback.
        '';
      };
    };

    mpris = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run mpDris2, exposing MPD over MPRIS.

        This is what makes media keys and playerctl work. MPD speaks its own
        protocol and nothing else, so without a bridge the standard desktop
        playback controls do not see it at all.
      '';
    };

    cavaGradient = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "#1c2f5f"
        "#253a73"
        "#2e4587"
        "#38509b"
        "#415cad"
        "#4a67be"
        "#5071c6"
        "#5277c3"
        "#5c83cf"
        "#668fd9"
        "#709be3"
        "#7aa7ec"
        "#84b3f5"
        "#8ebffd"
        "#98caff"
        "#a3d4ff"
        "#afdfff"
        "#bbe9ff"
        "#c7f2ff"
        "#d3fbff"
      ];
      description = ''
        Colour stops for cava's bar gradient, low frequency to high.

        cava takes at most 20; extras are ignored rather than rejected.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.mpc
      pkgs.playerctl
    ]
    ++ lib.optional cfg.clients.metadataEditor pkgs.picard;

    services.mpd = {
      enable = true;

      musicDirectory = cfg.musicDirectory;

      extraConfig = ''
        audio_output {
        	type "${cfg.audioOutput}"
        	name "${cfg.audioOutput} output"
        }
      ''
      + lib.optionalString cfg.visualizerFifo.enable ''

        audio_output {
        	type   "fifo"
        	name   "${cfg.visualizerFifo.outputName}"
        	path   "${cfg.visualizerFifo.path}"
        	format "44100:16:${if cfg.visualizerFifo.stereo then "2" else "1"}"
        }
      '';
    };

    services.mpdris2.enable = cfg.mpris;

    programs.cava = lib.mkIf cfg.clients.cava {
      enable = true;
      settings = {
        general.framerate = 60;
        output.channels = if cfg.visualizerFifo.stereo then "stereo" else "mono";

        color = {
          gradient = 1;
        }
        # cava wants each colour single-quoted inside its config value, and
        # home-manager writes the string verbatim, so the quotes are part of
        # the value rather than Nix syntax.
        // lib.listToAttrs (
          lib.imap1 (i: c: lib.nameValuePair "gradient_color_${toString i}" "'${c}'") (
            lib.take 20 cfg.cavaGradient
          )
        );
      };
    };

    programs.ncmpcpp = lib.mkIf cfg.clients.ncmpcpp {
      enable = true;

      settings = {
        song_list_format = "{%g - }{%a - }{%t}|{$8%f$9}$R$3(%l)$9";
        song_library_format = "{%g - }{%a - }{%t}|{$8%f$9}$R$3(%l)$9";

        # Absolute store path: ncmpcpp runs this through a shell whose PATH is
        # whatever the terminal had.
        execute_on_song_change = ''notify-send "Now Playing" "$(${pkgs.mpc}/bin/mpc --format '%title% \n%artist%' current)"'';
      }
      // lib.optionalAttrs cfg.visualizerFifo.enable {
        visualizer_data_source = cfg.visualizerFifo.path;
        visualizer_output_name = cfg.visualizerFifo.outputName;
        visualizer_in_stereo = if cfg.visualizerFifo.stereo then "yes" else "no";
        visualizer_type = "ellipse";
        visualizer_look = "+|";
        visualizer_color = "41, 83, 119, 155, 185, 215, 209, 203, 197, 161";
      };

      # vim motions, plus the sort and search bindings that have no default.
      bindings = [
        {
          key = "j";
          command = "scroll_down";
        }
        {
          key = "k";
          command = "scroll_up";
        }
        {
          key = "h";
          command = "previous_column";
        }
        {
          key = "l";
          command = "next_column";
        }
        {
          key = "ctrl-d";
          command = "page_down";
        }
        {
          key = "ctrl-u";
          command = "page_up";
        }
        {
          key = "d";
          # One binding covering three contexts — ncmpcpp tries each in turn
          # and uses whichever applies to the focused panel.
          command = [
            "delete_playlist_items"
            "delete_browser_items"
            "delete_stored_playlist"
          ];
        }
        {
          key = "/";
          command = [
            "find"
            "find_item_forward"
          ];
        }
        {
          key = "n";
          command = "next_found_item";
        }
        {
          key = "N";
          command = "previous_found_item";
        }
        {
          key = "J";
          command = "move_sort_order_down";
        }
        {
          key = "K";
          command = "move_sort_order_up";
        }
        {
          key = "g";
          command = "move_home";
        }
        {
          key = "G";
          command = "move_end";
        }
      ];
    };
  };
}
