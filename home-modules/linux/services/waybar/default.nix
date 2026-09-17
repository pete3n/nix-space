# Directory hook for the waybar module.
{ ... }:
{
  imports = [
		./default-widgets
    ./mpd-browser
		./mpd-player
		./waybar
  ];
}
