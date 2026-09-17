# MPD music browser module utilizing rofi menus.
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

  cfg = config.nixSpace.waybar.mpdBrowser;

  browser = pkgs.writeShellApplication {
    name = "mpd-browser";

    # programs.rofi wraps it with the theme and plugins.
    runtimeInputs = with pkgs; [
      config.programs.rofi.finalPackage
      coreutils
      findutils
      gawk
      mpc
    ];

    # nounset only. An interactive menu must survive a failing mpc call and
    # return to its menu rather than exit, and `sort | head` would trip
    # pipefail whenever head closes the pipe early.
    bashOptions = [ "nounset" ];

    text = # sh
    ''
      NEWEST_LIMIT="${toString cfg.newestLimit}"
    ''
    + builtins.readFile ./mpd-browser.sh;
  };
in
{
  options.nixSpace.waybar.mpdBrowser = {
    enable = mkEnableOption "mpd rofi browser";
    newestLimit = mkOption {
      type = types.ints.positive;
      default = 500;
      description = ''
        How many files the "Newest (file mtime)" search offers, most recently
        modified first. The whole list is handed to rofi at once, so this
        bounds both the scan and the menu size.
      '';
    };
  };

  config = mkIf (config.nixSpace.waybar.mpdPlayer.enable && cfg.enable) {
    assertions = [
      {
        assertion = config.programs.rofi.enable;
        message = ''
          nixSpace.waybar.mpdBrowser needs programs.rofi. It uses the
          configured package so the menus match every other rofi menu.
        '';
      }
    ];

    home.packages = [
      browser
    ];

    nixSpace.waybar.modules."custom/playerctl".on-click-right = lib.getExe browser;
  };
}
