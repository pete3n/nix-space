# Display settings widget for waybar: launches wdisplays for monitor
# arrangement.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.hyprdesktop.wdisplays;
in
{
  options.nixSpace.hyprdesktop.wdisplays = {
    enable = lib.mkEnableOption "the wdisplays waybar widget";
  };

  config = lib.mkIf cfg.enable {
    nixSpace.waybar.modules."custom/wdisplays" = {
      style = ''
        #custom-wdisplays {
          color: ${config.nixSpace.waybar.accentColor};
        }
      '';

      format = "󰹑";
      tooltip = true;
      tooltip-format = "Display Settings";

      # Absolute store path rather than a bare name: the widget must work
      # whether or not wdisplays is on the session PATH.
      on-click = lib.getExe' pkgs.wdisplays "wdisplays";
    };

    home.packages = [ pkgs.wdisplays ];
  };
}
