# hyprlock — screen lock appearance.
#
# A PRESET over programs.hyprlock, not a wrapper. Only the background image
# and the placeholder text get options; everything else is a default written
# straight into programs.hyprlock.settings, where anyone can override it
# directly. Exposing eight colour options for one input field would be a lot
# of surface for something more likely replaced wholesale.
#
# WHO CALLS THIS. Nothing here locks anything — hyprlock is invoked by
# hypridle's lock_cmd, by loginctl lock-session through the same, and by the
# which-key power entry. This module only decides what the lock screen looks
# like when one of those fires.
#
# swaylock is NOT installed. Every lock path in this bundle goes to hyprlock,
# so a second locker would be an installed program with no caller — and two
# lockers on one session is a way to end up with neither working.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.hyprdesktop.lock;
in
{
  options.nixSpace.hyprdesktop.lock = {
    enable = lib.mkEnableOption "hyprlock screen lock";
    background = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "\${config.xdg.userDirs.pictures}/wallpapers/hyprlock.jpg";
      description = ''
        Image shown behind the lock screen.

        Null gives hyprlock's own default, a solid colour. A path that does
        not EXIST also gives a black screen, but accidentally — so this is
        null rather than a plausible-looking default the module cannot
        provide.

        Note this is independent of the desktop wallpaper: changing one does
        not change the other.
      '';
    };

    placeholderText = lib.mkOption {
      type = lib.types.str;
      default = "Password...";
      example = "Speak friend...";
      description = "Text shown in the empty password field.";
    };
  };

  config = lib.mkIf (config.nixSpace.hyprdesktop.enable && cfg.enable) {
    # Screencopy permission for the locker.
    #
    # Without it the lock screen is black: ecosystem.enforce_permissions is on
    # in the compositor preset, and hyprlock needs screencopy to render a
    # blurred or image background.
    wayland.windowManager.hyprland.settings.permission = {
      _args = [
        {
          binary = lib.getExe config.programs.hyprlock.package;
          type = "screencopy";
          mode = "allow";
        }
      ];
    };

    programs.hyprlock = {
      enable = true;

      settings = {
        general = {
          # The cursor is a useful signal that the machine is awake and
          # responding, which a lock screen otherwise gives no indication of.
          hide_cursor = false;

          # Enter on an empty field does nothing rather than running a PAM
          # round trip that always fails — which on some configurations
          # counts against the retry limit.
          ignore_empty_input = true;
        };

        animations.enabled = true;

        # Same keyword syntax as hyprland.conf, but hyprlock has its OWN
        # parser — it is not affected by the compositor's configType, so
        # these stay in the hyprlang string form.
        bezier = [
          "linear, 1, 1, 0, 0"
          "easeOut, 0.05, 0.9, 0.1, 1.0"
        ];

        animation = [
          "fadeIn, 1, 3, easeOut"
          "fadeOut, 1, 3, easeOut"
        ];

        background = lib.optional (cfg.background != null) {
          path = cfg.background;
        };

        "input-field" = [
          {
            size = "400, 100";
            position = "0, -80";

            # Empty monitor means every monitor. A named one would leave the
            # others with a lock screen and no way to type into it.
            monitor = "";

            dots_center = true;

            # Keep the field visible when empty: fading it out on an idle
            # lock screen leaves nothing on screen to indicate the machine is
            # locked rather than off.
            fade_on_empty = false;

            font_color = "rgb(202, 211, 245)";
            inner_color = "rgb(0, 0, 0)";
            outer_color = "rgb(24, 25, 38)";
            outline_thickness = 5;
            shadow_passes = 2;

            placeholder_text = cfg.placeholderText;
          }
        ];
      };
    };
  };
}
