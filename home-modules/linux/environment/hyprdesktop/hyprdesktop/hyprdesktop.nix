# Hyprland desktop - opinionated bundle.
#
# Composition only. This file enables modules and places waybar widgets; it
# does not define widgets, keybinds, or application configuration. Each of
# those lives in a sibling file that contributes to the relevant option when
# the bundle is on:
#
#   calendar.nix   pomodoro.nix   snowflake.nix   wdisplays.nix   keybinds.nix
#
# WHAT DOES NOT BELONG HERE: host opinions. A wallpaper path, a lock-screen
# phrase, a font someone happens to like, or a keymap into a directory only
# one machine has — those go in the host's home.nix. A library consumer
# enabling this bundle should get a working Hyprland desktop, not someone
# else's preferences.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.hyprdesktop;
in
{
  options.nixSpace.hyprdesktop = {
    enable = lib.mkEnableOption "Hyprland desktop environment bundle";

    launcher = lib.mkOption {
      type = lib.types.str;
      default = config.nixSpace.programs.launchers.primaryCommand;
      description = ''
        Application launcher command.

        Separate from the compositor preset's own launcher option so the
        bundle can standardise on one while a bare compositor user keeps
        theirs.
      '';
    };

    audioControl = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install pavucontrol.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixSpace = {
      workstationCommon.enable = true;

      waybar = {
        enable = lib.mkDefault true;
        hyprlandWorkspaces = true;

				# mpd player requires the mpd service
				mpdPlayer.enable = lib.mkDefault true;

        # mpdBrowser asserts that rofi is enabled. 
				# and requires mpdPlayer
        mpdBrowser.enable = lib.mkDefault true;

        # A widget definition alone does not appear on the bar: the feature
        # module defines it, this places it. Placement lists do not merge,
        # so each list here names everything in its position, in order.
        modulesLeft =
          lib.optional cfg.snowflake.enable "custom/snowflake"
          ++ [
            "hyprland/workspaces"
            "tray"
          ];

        # pomodoro defines the clock widget; calendar attaches its popup to
        # the same key. One placement covers both.
        modulesCenter = lib.optional cfg.pomodoro.enable "custom/clock";

        modulesRight =
          lib.optionals config.nixSpace.waybar.mpdPlayer.enable [
            "custom/mpd_prev"
            "custom/playerctl"
            "custom/mpd_next"
            "custom/mpd_shuffle"
            "custom/mpd_repeat"
          ]
          ++ [ "pulseaudio" ]
          ++ lib.optional config.nixSpace.waybar.backlight.enable "backlight"
          ++ lib.optional cfg.wdisplays.enable "custom/wdisplays"
          ++ [ "battery" ];
      };

      # Sibling modules. Each owns its own defaults; the bundle only decides
      # whether it is on.
      hyprdesktop = {
        calendar.enable = lib.mkDefault true;
        pomodoro.enable = lib.mkDefault true;
        snowflake.enable = lib.mkDefault true;
        wdisplays.enable = lib.mkDefault true;
        keybinds.enable = lib.mkDefault true;

        idle.enable = lib.mkDefault true;
        lock.enable = lib.mkDefault true;
        mpdVisualizer.enable = lib.mkDefault true;
        portals.enable = lib.mkDefault true;
        wallpaper = {
          enable = lib.mkDefault true;
          picker = lib.mkDefault true;
        };
      };

      programs.launchers = {
        rofi.enable = lib.mkDefault true;
        primary = lib.mkDefault "rofi";
      };

      services.dunst.enable = lib.mkDefault true;
    };

    home.packages = lib.optional cfg.audioControl pkgs.pavucontrol;
  };
}
