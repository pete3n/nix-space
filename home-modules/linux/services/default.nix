# Directory hook for linux services modules.
{ ... }:
{
  imports = [
    ./hyprland
    ./laptop
    ./mpd
		./notify
    ./waybar
  ];
}
