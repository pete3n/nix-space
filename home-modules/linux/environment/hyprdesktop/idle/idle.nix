# hypridle module.
# Managed idle timeouts: dim, lock, blank, suspend, for Hyprland.
# Utilizes Lua configuration sytanx for Hyprland.

# Locking goes through loginctl, not hyprlock directly. general.lock_cmd
# carries the `pidof hyprlock ||` guard against a second instance, and
# `loginctl lock-session` routes through it.
#
# Timeout ordering is important: blanking before locking would show the desktop
# for the gap between them on the next keypress; suspending before locking would
# resume to an unlocked session.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.hyprdesktop.idle;

  # The compositor is installed by the system, so home-manager's finalPackage
  # is null here and a nixpkgs fallback would be a different build than the
  # one running. PATH is correct because the session cannot exist without
  # hyprctl on it.
  hyprctl = "hyprctl";

  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  loginctl = "${pkgs.systemd}/bin/loginctl";

  displayArgs = lib.optionalString (cfg.backlightDevice != "") " -d ${cfg.backlightDevice}";
in
{
  options.nixSpace.hyprdesktop.idle = {
    enable = lib.mkEnableOption "hypridle timeouts";
    dimTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 150;
      description = ''
        Seconds of inactivity before dimming the screen and turning off the
        keyboard backlight.

        The first and cheapest signal that the session is idle, and the only
        one that is trivially reversible: brightnessctl -r restores the
        previous value rather than a configured one.
      '';
    };

    dimBrightness = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 10;
      description = ''
        Backlight percentage when dimmed.

        NOT zero: on an OLED panel a zero backlight is indistinguishable from
        the screen being off.
      '';
    };

    lockTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = "Seconds of inactivity before locking the session.";
    };

    screenOffTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 330;
      description = ''
        Seconds of inactivity before turning the display off.

        Must exceed lockTimeout: blanking first would show the unlocked
        desktop for the interval between them when a key is pressed.
      '';
    };

    suspendTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 600;
      description = ''
        Seconds of inactivity before attempting suspend.

        Goes through hypr-suspend-blocker rather than systemctl directly, so
        the blocker conditions apply.
      '';
    };

    backlightDevice = lib.mkOption {
      type = lib.types.str;
      default = config.nixSpace.services.powerproud.backlightDevice or "";
      defaultText = lib.literalMD "Inherited from `nixSpace.services.powerproud.backlightDevice`.";
      description = ''
        Display backlight to dim, as listed by `ls /sys/class/backlight`.

        Defaults to whatever powerproud uses.
      '';
    };

    keyboardBacklightDevice = lib.mkOption {
      type = lib.types.str;
      default = "rgb:kbd_backlight";
      example = "framework_laptop::kbd_backlight";
      description = ''
        Keyboard backlight device, as listed by `brightnessctl -l`.

        The default is the common name on Intel-era laptops. Framework and
        other vendors expose different ones, and a wrong name makes
        brightnessctl fail silently.
      '';
    };

    dimKeyboard = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Turn off the keyboard backlight when idle.";
    };

    extraListeners = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [ ];
      example = lib.literalExpression ''
        [
          {
            timeout = 900;
            on-timeout = "systemctl hibernate";
          }
        ]
      '';
      description = ''
        Additional hypridle listeners, appended after the ones above.

        Listeners are independent: hypridle fires each at its own timeout
        rather than in sequence, so an entry here needs a timeout that does
        not duplicate one already in use.
      '';
    };
  };

  config = lib.mkIf (config.nixSpace.hyprdesktop.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.lockTimeout > cfg.dimTimeout;
        message = ''
          idle.lockTimeout must exceed idle.dimTimeout. Dimming is the
          warning that a lock is coming, and a lock that fires first removes
          the warning.
        '';
      }
      {
        assertion = cfg.screenOffTimeout > cfg.lockTimeout;
        message = ''
          idle.screenOffTimeout must exceed idle.lockTimeout. Blanking before
          locking shows the unlocked desktop for the interval between them
          the moment a key is pressed.
        '';
      }
      {
        assertion = cfg.suspendTimeout > cfg.lockTimeout;
        message = ''
          idle.suspendTimeout must exceed idle.lockTimeout, or the machine
          resumes to an unlocked session.
        '';
      }
    ];

    services.hypridle = {
      enable = true;

      settings = {
        general = {
          # Without this the first keypress after resume only wakes the
          # display and is swallowed, so everything needs pressing twice.
          after_sleep_cmd = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"enable\" })'";

          # The guard against a second hyprlock. Everything that locks goes
          # through loginctl so it lands here rather than around it.
          lock_cmd = "pidof hyprlock || hyprlock";

          # Lock BEFORE suspending, not after resume. A lock command that runs
          # on resume leaves a window where the session is visible.
          before_sleep_cmd = "${loginctl} lock-session";

          ignore_dbus_inhibit = false;
        };

        listener = [
          {
            timeout = cfg.dimTimeout;
            on-timeout = "${brightnessctl}${displayArgs} -s set ${toString cfg.dimBrightness}%";

            # -r restores the value saved by -s above, so the screen returns
            # to whatever it was rather than to a configured level.
            on-resume = "${brightnessctl}${displayArgs} -r";
          }
        ]
        ++ lib.optional cfg.dimKeyboard {
          timeout = cfg.dimTimeout;
          on-timeout = "${brightnessctl} -sd ${cfg.keyboardBacklightDevice} set 0";
          on-resume = "${brightnessctl} -rd ${cfg.keyboardBacklightDevice}";
        }
        ++ [
          {
            timeout = cfg.lockTimeout;

            # loginctl, not hyprlock: this routes through lock_cmd and gets
            # its pidof guard. Calling hyprlock here bypasses the very
            # protection lock_cmd exists to provide.
            on-timeout = "${loginctl} lock-session";
          }
          {
            timeout = cfg.screenOffTimeout;
            on-timeout = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"disable\" })'";

            # Restore brightness alongside the display: the dim listener's
            # on-resume may have already fired, so nothing else would.
            on-resume = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"enable\" })' && ${brightnessctl}${displayArgs} -r";
          }
          {
            timeout = cfg.suspendTimeout;

            # Through the blocker, so extPower and extDisplay conditions
            # apply. Bare `systemctl suspend` would ignore them.
            on-timeout = "hypr-suspend-blocker";
          }
        ]
        ++ cfg.extraListeners;
      };
    };
  };
}
