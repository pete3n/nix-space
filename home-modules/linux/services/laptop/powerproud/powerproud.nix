# Power profile user daemon module.
# Manages power-profile and backlight switching on AC/battery.
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

  cfg = config.nixSpace.services.powerproud;

  powerproud = pkgs.writeShellApplication {
    name = "powerproud";
    runtimeInputs = with pkgs; [
      brightnessctl
      coreutils
      power-profiles-daemon
      systemd
      util-linux
    ];

    text = # sh
    ''
      BACKLIGHT_DEVICE=${lib.escapeShellArg cfg.backlightDevice}
      BATTERY_DEVICE=${lib.escapeShellArg cfg.batteryDevice}
      BAT_POLL_INTERVAL="${toString cfg.batPollInterval}"
      LOG_EVENTS="${lib.boolToString cfg.logEvents}"
      MANAGE_BRIGHTNESS="${lib.boolToString cfg.manageBrightness}"
      ON_AC_BRIGHTNESS="${toString cfg.onAcBrightness}"
      ON_AC_PROFILE="${cfg.onAcProfile}"
      ON_BATTERY_BRIGHTNESS="${toString cfg.onBatteryBrightness}"
      ON_BATTERY_PROFILE="${cfg.onBatteryProfile}"
    ''
    + builtins.readFile ./powerproud.sh;
  };
in
{
  options.nixSpace.services.powerproud = {
    enable = mkEnableOption "power profile and backlight switching on AC/battery";

    logEvents = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Log actions with `logger -t powerproud`.

        Only transitions and failures are logged.
      '';
    };

    batPollInterval = mkOption {
      type = types.ints.positive;
      default = 5;
      description = ''
        Seconds between battery status checks.

        Each poll reads one file, so this can be short. It bounds how long the
        machine stays on the wrong profile after plugging in.
      '';
    };

    batteryDevice = mkOption {
      type = types.str;
      default = "";
      example = "BAT1";
      description = ''
        Battery to watch, as named under /sys/class/power_supply.

        Empty takes the first device whose type is Battery.
      '';
    };

    manageBrightness = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Also adjust the backlight on power state changes.

        Needs write access to /sys/class/backlight, which udev grants through
        the video group or hardware.brightnessctl.enable on the system side.
        Without it the profile still switches and a failure is logged.
      '';
    };

    backlightDevice = mkOption {
      type = types.str;
      default = "";
      example = "nvidia_wmi_ec_backlight";
      description = ''
        Backlight to control, as listed by `ls /sys/class/backlight`.

        Empty lets brightnessctl pick the first it finds. Should be explicitly
        configured on laptops with a discrete GPU and integrated graphics.
      '';
    };

    onBatteryProfile = mkOption {
      type = types.enum [
        "power-saver"
        "balanced"
        "performance"
      ];
      default = "power-saver";
      description = "Power profile to switch to on battery.";
    };

    onAcProfile = mkOption {
      type = types.enum [
        "power-saver"
        "balanced"
        "performance"
      ];
      default = "performance";
      description = "Power profile to switch to on AC.";
    };

    onBatteryBrightness = mkOption {
      type = types.ints.between 1 100;
      default = 50;
      description = ''
        Backlight percentage on battery.

        Only ever dims toward this value; a screen already below it is left
        alone.
      '';
    };

    onAcBrightness = mkOption {
      type = types.ints.between 1 100;
      default = 100;
      description = ''
        Backlight percentage on AC.

        Only ever raises toward this value. Will not lower to.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      powerproud
      pkgs.power-profiles-daemon
    ]
    ++ lib.optional cfg.manageBrightness pkgs.brightnessctl;

    systemd.user.services."powerproud" = {
      Unit = {
        Description = "Power profile and backlight switching on AC/battery";
      };

      Service = {
        Type = "simple";
        ExecStart = "${powerproud}/bin/powerproud";
        Restart = "on-failure";
        RestartSec = 2;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
