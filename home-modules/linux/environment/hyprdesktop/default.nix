# Directory hook for the hyprdesktop module.
# This is an opionated configuration focused on a keyboard workflow with vim
# key bindings and modern CLI utilities.
{ ... }:
{
  imports = [
    ./calendar
    ./hyprdesktop
    ./idle
    ./keybinds
    ./lock
    ./mpd-visualizer
    ./pomodoro
    ./portals
    ./snowflake
    ./wallpaper
		./wdisplays
  ];
  # NOTE: pomodoro.nix must be imported for the clock to exist. calendar.nix
  # contributes only an on-click to that widget and asserts pomodoro is
  # enabled, since a widget with a click handler and no format renders as an
  # invisible region on the bar.
}
