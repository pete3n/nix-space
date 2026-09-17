# Pomodoro timer — the bar clock, its transition popup, and its config TUI.
#
# The CLOCK is defined here rather than in the waybar module because the
# ticker renders both the time and a running timer: `pomodoro ticker` emits
# {text, tooltip, class} every second, and the class drives the CSS that
# colours activity versus rest. A separate clock widget would mean two things
# competing for the same spot on the bar.
#
# The CALENDAR attaches its own on-click to this same widget. That works
# without either module importing the other because waybar.modules is
# attrsOf (attrsOf ...), so the module system merges per FIELD — pomodoro
# owns format/exec/on-click-right, calendar owns on-click, and two modules
# writing the same field would be reported as a conflict rather than one
# silently winning.
#
# WINDOW RULES ARE THE ONLY HYPRLAND COUPLING. The timer scripts do not call
# hyprctl at all — both windows are matched by CLASS and placed by their
# rules, and the image is closed by PID rather than by window, so hypr-popup
# is not involved either.
#
# The config TUI gets its class from a wrapper this module installs. The
# package launches a terminal by name from its own runtimeDeps, which meant
# the window opened alacritty regardless of which terminal is primary — and
# carried no class, so its rule had to match on title and would catch any
# window called "Pomodoro".
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.hyprdesktop.pomodoro;
  terminals = config.nixSpace.programs.terminals;

  # Wraps the package's TUI in a terminal THIS module chooses.
  #
  # The package puts alacritty on PATH through runtimeDeps and its script
  # calls it by name — so the config window opened alacritty regardless of
  # nixSpace.programs.terminals.primary, and on a machine where alacritty is
  # not the primary that is a second terminal appearing for one dialog.
  #
  # Wrapping also lets the window carry a CLASS. The rule previously matched
  # on TITLE, which catches any window titled "Pomodoro" — an editor with that
  # filename open, a browser tab in some compositors.
  configLauncher =
    pkgs.writeShellScriptBin "pomodoro-config-window" # sh
      ''
        exec ${
          terminals.mkTerminalCommand {
            class = cfg.configWindowClass;
            command = "${cfg.package}/bin/pomodoro-config";
          }
        }
      '';
in
{
  options.nixSpace.hyprdesktop.pomodoro = {
    enable = lib.mkEnableOption "pomodoro timer widget";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nsPkgs.pomodoro-timer;
      defaultText = lib.literalExpression "pkgs.nsPkgs.pomodoro-timer";
      description = ''
        Timer package, providing `pomodoro` and `pomodoro-config`.

        An option rather than a literal `pkgs.local.pomodoro-timer`: a module
        in a shared tree cannot assume a consumer has an overlay creating that
        namespace.
      '';
    };

    activityIntervals = lib.mkOption {
      type = lib.types.listOf lib.types.ints.positive;
      default = [
        25
        50
        75
      ];
      description = ''
        Selectable activity lengths in minutes, cycled in the config TUI.
      '';
    };

    restIntervals = lib.mkOption {
      type = lib.types.listOf lib.types.ints.positive;
      default = [
        5
        10
        15
      ];
      description = "Selectable rest lengths in minutes.";
    };

    defaultActivityName = lib.mkOption {
      type = lib.types.str;
      default = "Activity";
      description = "Label shown on the bar during an activity interval.";
    };

    music = {
      activityPlaylist = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "focus";
        description = ''
          MPD playlist loaded during activity intervals, or empty for none.

          The timer SAVES the current track and position before starting and
          restores them on stop, so it can be used mid-listening without
          losing your place.
        '';
      };

      restPlaylist = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "chill";
        description = "MPD playlist loaded during rest intervals.";
      };
    };

    transitionImage = {
      activity = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "\${config.xdg.userDirs.pictures}/pomodoro/focus";
        description = ''
          Image shown when an activity interval begins — a file, or a
          directory from which one is chosen at random.

          Empty shows nothing, which is the default because a module cannot
          ship images and a missing path would silently do nothing anyway.
        '';
      };

      rest = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Image shown when a rest interval begins.";
      };

      durationSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 5;
        description = ''
          How long the transition image stays up.

          The transition process BLOCKS for this long — it holds the image
          and its PID file alive, then kills it. A long duration keeps that
          process around correspondingly.
        '';
      };
    };

    clockFormat = lib.mkOption {
      type = lib.types.str;
      default = "%H:%M";
      description = ''
        strftime format for the idle clock.

        Only used when no timer is running; a running timer replaces the
        clock text with its countdown.
      '';
    };

    configWindowClass = lib.mkOption {
      type = lib.types.str;
      default = "com.nixspace.pomodoroConfig";
      description = ''
        Window class of the config TUI, matched by its rule.

        A CLASS rather than a title. The TUI is python inside a terminal, so
        the class belongs to the terminal — which is why this module launches
        it through a wrapper that sets one, rather than matching
        `title = "^(Pomodoro)$"` and catching every other window that happens
        to be called that.

        Reverse-DNS form because ghostty validates the class as a GTK
        application ID and silently keeps its own when given anything else,
        leaving the window unmatched and tiled.
      '';
    };

    imageWindowClass = lib.mkOption {
      type = lib.types.str;
      default = "com.nixspace.pomodoroImage";
      description = ''
        Window class of the transition image, matched by its rule.

        swayimg passes any string through — unlike ghostty, which validates it
        — but the same reverse-DNS form is used across the bundle so there is
        one convention rather than two.

        NOTE this must match what the timer script passes to swayimg. The
        package reads it from config.json, so changing it here without the
        package picking up the new value leaves an unmatched window.
      '';
    };
  };

  config = lib.mkIf (config.nixSpace.hyprdesktop.enable && cfg.enable) {
    home.packages = [
      cfg.package
      configLauncher
    ];

    # Read by both the shell timer and the python TUI. JSON rather than
    # options passed at build time because the TUI writes state alongside it
    # and both need the same view of the intervals.
    xdg.configFile."pomodoro/config.json".text = builtins.toJSON {
      activity_intervals = cfg.activityIntervals;
      rest_intervals = cfg.restIntervals;
      activity_playlist = cfg.music.activityPlaylist;
      rest_playlist = cfg.music.restPlaylist;
      activity_image = cfg.transitionImage.activity;
      rest_image = cfg.transitionImage.rest;
      image_display_duration = cfg.transitionImage.durationSeconds;
      default_activity_name = cfg.defaultActivityName;

      # The timer script reads this to pass --class to swayimg. Without it the
      # package would use its own literal, and changing imageWindowClass here
      # would leave the rule matching a class nothing sets.
      image_window_class = cfg.imageWindowClass;
    };

    nixSpace.waybar.modules."custom/clock" = {
      # The ticker emits a CSS class per mode, so the clock looks different
      # while a timer runs without the text having to say so.
      style = ''
        #custom-clock {
        	padding: 0 12px;
        	color: ${config.nixSpace.waybar.accentColor};
        }

        #custom-clock.activity {
        	color: #b5bd68;
        }

        #custom-clock.rest {
        	color: #81a2be;
        }
      '';

      format = "{}";
      return-type = "json";

      # One second, because the ticker decrements the countdown itself rather
      # than reading a deadline — a slower interval would make the timer run
      # slow rather than merely update coarsely.
      interval = 1;
      restart-interval = 1;

      exec = "${cfg.package}/bin/pomodoro ticker";

      # on-click is left to the calendar module. Waybar's module set merges
      # per field, so that attaches without either module importing the other.
      # The wrapper, not the package binary directly — it is what opens the
      # TUI in a terminal with a window class the rule can match.
			tooltip-format = lib.mkDefault "Click for calendar\nRight-click for timer";
			tooltip = true;
      on-click-right = lib.getExe configLauncher;
    };

    nixSpace.hyprland.windowRules = [
      {
        name = "pomodoro-tui";
        match.class = "^(${cfg.configWindowClass})$";
        float = true;
        center = true;
        size = "1200 800";

        # Deliberately focused, unlike the popups: this one is opened to be
        # typed into.
        stay_focused = true;
      }
      {
        name = "pomodoro-img";
        match.class = "^(${cfg.imageWindowClass})$";
        float = true;
        center = true;
        border_size = 0;
        no_shadow = true;

        # An animation on a window that exists for a few seconds is most of
        # its visible lifetime.
        no_anim = true;

        opacity = "0.92 0.92";

        # It appears unprompted at an interval boundary — taking focus would
        # interrupt whatever is being typed.
        no_initial_focus = true;
      }
    ];
  };
}
