# Keyboard backlight auto-control module for the Framework 16 laptop.
#
# A timer runs this every pollIntervalSeconds. The ambient light sensor's raw value is
# sorted into five buckets (dark, low, dim, bright, sunlight), each mapped to a
# backlight level set through qmk_hid. Hysteresis keeps the level from flapping at a
# bucket boundary. The backlight is turned off while the lid is closed and, with
# batteryOnly, held at acDefault while on external power.
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

  cfg = config.nixSpace.services.fw16KbdAlsd;

  runtimeDir = "fw16-kbd-alsd";

  fw16KbdAlsd = pkgs.writeShellApplication {
    name = "fw16-kbd-alsd";
    runtimeInputs = with pkgs; [
      coreutils
      qmk_hid
    ];

    text = # sh
    ''
      AC_DEFAULT="${toString cfg.acDefault}"
      ALS_PATH="${cfg.alsPath}"
      ${
        lib.toShellVar "BACKLIGHT_LEVELS" [
          cfg.nolight
          cfg.lowlight
          cfg.dimlight
          cfg.brightlight
          cfg.sunlight
        ]
      } # Indexed by bucket
      BATTERY_ONLY="${lib.boolToString cfg.batteryOnly}"
      HYSTERESIS="${toString cfg.hysteresis}"
      MISSING_STAMP="/run/${runtimeDir}/qmk-missing.logged"
      STATE_FILE="/run/${runtimeDir}/last_bucket"
      VID="${cfg.vid}"
    ''
    + builtins.readFile ./kbd-alsd.sh;
  };
in
{
  options.nixSpace.services.fw16KbdAlsd = {
    enable = mkEnableOption "Framework 16 keyboard backlight auto-control via ALS and qmk_hid";

    vid = mkOption {
      type = types.str;
      default = "32ac";
      description = ''
        USB vendor ID passed to qmk_hid. List devices with `qmk_hid -l`, for example:
          3434:0e20
            Manufacturer: "Keychron"
            Product:      "Keychron K2 HE"
            FW Version:   1.0.0
            Serial No:    ""
          32ac:0012
            Manufacturer: "Framework"
            Product:      "Laptop 16 Keyboard Module - ANSI"
            FW Version:   0.3.1
            Serial No:    "FRAKDKEN0100000000"

        Default: 32ac
      '';
    };

    alsPath = mkOption {
      type = types.str;
      default = "/sys/bus/iio/devices/iio:device0/in_illuminance_raw";
      description = ''
        Path to the ambient light sensor's raw illuminance value.

        Default: /sys/bus/iio/devices/iio:device0/in_illuminance_raw
      '';
    };

    pollIntervalSeconds = mkOption {
      type = types.ints.positive;
      default = 5;
      description = ''
        How frequently to check for ALS changes.

        Default: 5
      '';
    };

    hysteresis = mkOption {
      type = types.ints.between 0 5;
      default = 1;
      description = ''
        Hysteresis margin in ALS raw units (0 disables). Prevents flapping between
        brightness buckets.

        Default: 1
      '';
    };

    nolight = mkOption {
      type = types.ints.between 0 100;
      default = 100;
      description = ''
        Backlight level when ALS is 0-4 (dark).

        Default: 100
      '';
    };

    lowlight = mkOption {
      type = types.ints.between 0 100;
      default = 75;
      description = ''
        Backlight level when ALS is 5-9 (low light).

        Default: 75
      '';
    };

    dimlight = mkOption {
      type = types.ints.between 0 100;
      default = 50;
      description = ''
        Backlight level when ALS is 10-14 (dim light).

        Default: 50
      '';
    };

    brightlight = mkOption {
      type = types.ints.between 0 100;
      default = 25;
      description = ''
        Backlight level when ALS is 15-19 (bright light).

        Default: 25
      '';
    };

    sunlight = mkOption {
      type = types.ints.between 0 100;
      default = 0;
      description = ''
        Backlight level when ALS is 20 or more (sunlight).

        Default: 0
      '';
    };

    batteryOnly = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Only apply settings when on battery power.

        Default: true
      '';
    };

    acDefault = mkOption {
      type = types.ints.between 0 100;
      default = 100;
      description = ''
        Backlight level while external power is connected. Only applies if
        batteryOnly is true.

        Default: 100
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.fw16-kbd-alsd = {
      description = "Framework 16 keyboard backlight auto-control (ALS -> qmk_hid)";
      unitConfig = {
        ConditionPathExists = cfg.alsPath;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${fw16KbdAlsd}/bin/fw16-kbd-alsd";
        RuntimeDirectory = runtimeDir;
        # A oneshot stops after every run, and stopping removes RuntimeDirectory
        # unless preserved. The hysteresis state and the missing-device stamp
        # must outlive a single run.
        RuntimeDirectoryPreserve = true;
        ProtectSystem = "strict";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
      };
    };

    systemd.timers.fw16-kbd-alsd = {
      description = "Timer for Framework 16 keyboard backlight auto-control";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5s";
        OnUnitActiveSec = "${toString cfg.pollIntervalSeconds}s";
        Unit = "fw16-kbd-alsd.service";
      };
    };
  };
}
