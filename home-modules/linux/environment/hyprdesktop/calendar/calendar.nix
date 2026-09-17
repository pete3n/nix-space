# Khal calendar waybar widget module.
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

  cfg = config.nixSpace.hyprdesktop.calendar;
  barHeight = config.nixSpace.waybar.height;
  terminals = config.nixSpace.programs.terminals;

  # Reads khal's sqlite cache directly rather than shelling out to `khal list`.
  #
  # `SELECT item FROM events` depends on khal's internal schema, which is a
  # cache khal is free to change. `khal list` with a format string would survive
  # an upgrade; this will not. It is used because per-event VALARM triggers are
  # not exposed by khal's own output, and honouring an event's own reminder is
  # the point of the service. If a khal upgrade breaks this, the fix is to
  # drop per-event triggers and use `khal list` with reminderOffsets only.
  khalNotify = pkgs.writeShellApplication {
    name = "khal-notify";
    runtimeInputs = with pkgs; [
      coreutils
      findutils
      libnotify
      sqlite
    ];

    text = # sh
    ''
      DISPLAY_MS="${toString cfg.notifications.displayMs}"
      KHAL_DB="''${XDG_DATA_HOME:-$HOME/.local/share}/khal/khal.db"
      LOOKAHEAD_HOURS="${toString cfg.notifications.lookaheadHours}"
      ${lib.toShellVar "REMINDER_OFFSETS" cfg.notifications.reminderOffsets}
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/khal-notify"
      TIMEZONE="${toString cfg.timezone}" # Empty means the system zone
    ''
    + builtins.readFile ./khal-notify.sh;
  };

  # Built by the terminals module rather than assembled here: the class and
  # opacity flags are spelled differently by each terminal, so a literal
  # command line would only work for whichever one it was written against.
  terminalCommand = terminals.mkTerminalCommand {
    class = cfg.windowClass;
    inherit (cfg) opacity;
    command = "${lib.getExe' pkgs.khal "khal"} interactive";
  };

  calendarToggle = pkgs.writeShellApplication {
    name = "calendar-toggle";
    runtimeInputs = [ config.nixSpace.hyprland.popupHelper.package ];
    text = # sh
    ''
      TERMINAL_CMD=${lib.escapeShellArg terminalCommand}
      WINDOW_CLASS="${cfg.windowClass}"
    ''
    + builtins.readFile ./calendar-toggle.sh;
  };
in
{
  options.nixSpace.hyprdesktop.calendar = {
    enable = mkEnableOption "khal calendar widget";
    windowClass = mkOption {
      type = types.str;
      default = "com.nixspace.calendarPopup";
      description = ''
        Window class used to match the rule and find the window again.

        Reverse-DNS form because ghostty validates the class as a GTK
        application ID and rejects anything else: the log says
        "invalid 'class' in config, ignoring" and the window keeps
        com.mitchellh.ghostty, so no rule matches and the popup tiles.
        alacritty and kitty pass any string through, so one form works for
        all three.
      '';
    };

    width = mkOption {
      type = types.int;
      default = 1280;
      description = "Popup width in pixels.";
    };

    height = mkOption {
      type = types.int;
      default = 800;
      description = "Popup height in pixels.";
    };

    opacity = mkOption {
      type = types.float;
      default = 0.92;
      description = "Terminal background opacity.";
    };

    timezone = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "America/New_York";
      description = ''
        Timezone for khal, or null to inherit the system default.

        Null rather than a literal: a module that hardcodes a timezone is
        wrong for everyone outside it, and khal falls back to the system
        setting on its own. Set it only where khal should differ from the
        host.
      '';
    };

    basePath = mkOption {
      type = types.str;
      default = "${config.xdg.dataHome}/khal/calendars";
      description = ''
        Parent directory holding calendar vdirs, one subdirectory each.

        Written to accounts.calendar.basePath, from which each account's
        local.path defaults to <basePath>/<name>.

        Use an absolute path. A literal "~/..." is NOT expanded by Nix, and
        whether it resolves then depends on each consumer's own path handling;
        vdirsyncer and khal do not agree about it.
      '';
    };

    accounts = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            primary = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Calendar new events go to. Exactly one account should set this.

                Replaces a default_calendar setting: the accounts framework
                already models this, and writing both would be two sources for
                one fact.
              '';
            };

            color = mkOption {
              type = types.nullOr types.str;
              default = null;
              example = "light blue";
              description = "khal colour name or #rrggbb, or null for its default.";
            };

            readOnly = mkOption {
              type = types.bool;
              default = false;
              description = ''
                Keep khal from writing to this calendar.

                Set it for anything vdirsyncer pulls from a server: a local
                write into a synced vdir produces a conflict that surfaces at
                the next sync rather than at the edit.
              '';
            };
          };
        }
      );

      default = {
        default = {
          primary = true;
          color = "light blue";
        };
      };

      description = ''
        Calendars, keyed by vdir directory name.

        Declared through home-manager's accounts.calendar framework rather
        than programs.khal.settings. That option is a flat INI attrset and
        cannot express khal's [[subsection]] calendars at all. Going through
        accounts also means vdirsyncer reads the same definitions, so syncing
        later needs no second declaration.

        A default account exists so the tag alone yields a working calendar:
        khal pointed at nothing shows an empty view AND refuses to add events,
        which reads as broken rather than unconfigured. Replace the attrset to
        declare your own.
      '';
    };

    notifications = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Fire desktop notifications before events start.

          Off by default: it adds a systemd timer running every few seconds,
          and a calendar with no events produces nothing but wakeups.

          Requires a notification daemon.
        '';
      };

      reminderOffsets = mkOption {
        type = types.listOf types.ints.unsigned;
        default = [
          15
          5
          1
        ];
        description = ''
          Minutes before an event to notify, when the event carries no
          reminder of its own.

          An event's own VALARM triggers take precedence: someone who set a
          reminder on an event meant that one, not this list.
        '';
      };

      displayMs = mkOption {
        type = types.ints.between 1000 60000;
        default = 15000;
        description = "How long a notification stays on screen, in milliseconds.";
      };

      lookaheadHours = mkOption {
        type = types.ints.unsigned;
        default = 25;
        description = ''
          How far ahead to consider events.

          Must exceed the largest reminderOffset, and 25 rather than 24 so a
          daily event is still in range when the previous day's marker is
          swept. State markers older than this are swept, so one cannot be
          removed while its event is still pending.
        '';
      };

      intervalSec = mkOption {
        type = types.ints.positive;
        default = 15;
        description = ''
          Seconds between checks.

          Must be 60 or less: an offset matches within a 60-second window, so
          a longer interval can step over one entirely and miss the
          notification.
        '';
      };
    };

  };

  config = mkIf (config.nixSpace.hyprdesktop.enable && cfg.enable) {
    assertions = [
      {
        assertion = config.nixSpace.hyprdesktop.pomodoro.enable;
        message = ''
          The calendar attaches its popup to the custom/clock widget, which the
          pomodoro module defines, but pomodoro is disabled, so the widget
          would have an on-click and no format: an invisible clickable region
          on the bar.

          Enable pomodoro, or disable the calendar.
        '';
      }
      {
        assertion = !cfg.notifications.enable || cfg.notifications.intervalSec <= 60;
        message = ''
          calendar.notifications.intervalSec is ${toString cfg.notifications.intervalSec}s,
          but an offset only matches within a 60-second window. A longer
          interval steps over the window and the notification never fires.
        '';
      }
      {
        assertion =
          !cfg.notifications.enable
          || cfg.notifications.reminderOffsets == [ ]
          || (cfg.notifications.lookaheadHours * 60) > lib.foldl' lib.max 0 cfg.notifications.reminderOffsets;
        message = ''
          calendar.notifications.lookaheadHours is too small for the largest
          reminderOffset — an event would fall outside the lookahead window
          before its earliest reminder is due, so that reminder never fires.
        '';
      }
    ];

    # ISO 8601 throughout, and a Monday-first week. Opinionated but
    # unambiguous: khal's own defaults are locale-derived, so two machines
    # with different LC_TIME render the same calendar differently.
    programs.khal = {
      enable = true;

      locale = {
        timeformat = "%H:%M";
        dateformat = "%Y-%m-%d";
        datetimeformat = "%Y-%m-%d %H:%M";
        longdateformat = "%Y-%m-%d";
        longdatetimeformat = "%Y-%m-%d %H:%M:%S";

        # 0 is Monday. khal's default follows the locale, which puts Sunday
        # first in en_US and shifts every week row by a day.
        firstweekday = 0;
      }
      // lib.optionalAttrs (cfg.timezone != null) {
        local_timezone = cfg.timezone;
        default_timezone = cfg.timezone;
      };

    };

    # Calendars go through the accounts framework, NOT
    # programs.khal.settings.calendars: that option is typed as a flat INI
    # attrset (section -> key -> atom) and rejects the nested table khal's
    # [[calendars]] subsections need.
    accounts.calendar = {
      inherit (cfg) basePath;

      accounts = lib.mapAttrs (_name: cal: {
        inherit (cal) primary;

        # local.path defaults to <basePath>/<name>, so it is not set here.
        local.type = "filesystem";

        khal = {
          enable = true;

          # A vdir — a directory of .ics files, which is what vdirsyncer
          # produces and khal writes into. "discover" would instead treat the
          # path as a parent of several calendars.
          type = "calendar";

          inherit (cal) readOnly;
        }
        // lib.optionalAttrs (cal.color != null) { inherit (cal) color; };
      }) cfg.accounts;
    };

    home.packages = [ calendarToggle ] ++ lib.optional cfg.notifications.enable khalNotify;

    # mkdir only: the directories are created, but not managed.
    #
    # home.file would be the declarative route, but it would make
    # home-manager the owner of a directory whose contents are written at
    # runtime by khal and vdirsyncer. Activation creates what is missing and
    # touches nothing else, so events survive a rebuild and dropping a
    # calendar from the list leaves its data alone rather than deleting it.
    # The accounts framework DESCRIBES paths and does not create them.
    # modules/accounts/calendar.nix contains no mkdir. If khal points at a
    # missing directory, it shows an empty view and refuses to add events,
    # which on a fresh machine looks like a broken calendar.
    #
    home.activation.createCalendarDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] (
      lib.concatMapStringsSep "\n" (
        acct: ''$DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "${acct.local.path}"''
      ) (lib.filter (a: a.khal.enable or false) (lib.attrValues config.accounts.calendar.accounts))
    );

    systemd.user.services.khal-notify = mkIf cfg.notifications.enable {
      Unit.Description = "khal calendar notifications";
      Service = {
        Type = "oneshot";
        ExecStart = "${khalNotify}/bin/khal-notify";
      };
    };

    systemd.user.timers.khal-notify = mkIf cfg.notifications.enable {
      Unit.Description = "khal calendar notification timer";
      Timer = {
        # OnBootSec delays the first run so the notification daemon is up.
        OnBootSec = "1min";
        OnUnitActiveSec = "${toString cfg.notifications.intervalSec}s";
        Unit = "khal-notify.service";
      };
      Install.WantedBy = [ "timers.target" ];
    };

    nixSpace.hyprland.windowRules = [
      {
        name = "calendar-popup";
        match.class = "^(${cfg.windowClass})$";
        float = true;

        # Centred horizontally, sitting just under the bar. The arithmetic is
        # evaluated by Hyprland, so it follows the monitor the window opens on
        # rather than being computed once for the focused one.
        size = "${toString cfg.width} ${toString cfg.height}";
        move = "(monitor_w-${toString cfg.width})/2 ${toString barHeight}";

        # Without this, opening the popup steals focus from whatever was
        # being worked on.
        no_initial_focus = true;

        border_size = 0;
        opacity = "${toString cfg.opacity} ${toString cfg.opacity}";
      }
    ];

    # Attaches to the clock rather than taking its own bar slot: a calendar
    # and a clock are the same concern, and the pomodoro module already owns
    # a widget there.
    #
    # Only on-click is written here. waybar.modules is attrsOf (attrsOf ...),
    # so the module system merges per field: pomodoro contributes
    # format/exec/on-click-right to the same key, and neither module imports
    # the other. Two modules writing the SAME field would be reported as a
    # conflict rather than one silently winning.
    #
    # If nothing defines custom/clock (pomodoro disabled), this contributes a
    # widget with only an on-click and no format, which waybar renders as an
    # empty clickable region. The assertion below catches that.
    nixSpace.waybar.modules."custom/clock" = {
      tooltip-format = lib.mkDefault "Click for calendar\nRight-click for timer";
      tooltip = true;
      on-click = lib.getExe calendarToggle;
    };
  };
}
