# pomodoro-timer — a bar ticker, a transition handler, and a config TUI.
#
# TWO BINARIES, NEITHER OPENING A WINDOW:
#
#   pomodoro         the ticker and transition logic, run by the bar widget
#   pomodoro-config  the TUI itself, python calling curses directly
#
# pomodoro-config USED TO LAUNCH ITS OWN TERMINAL — alacritty, with a title and
# dimensions baked in. That made it impossible to compose: a caller wanting
# the TUI in a different terminal, or with a window class its compositor could
# match, got a second terminal wrapped around the first. The window rule then
# matched the outer empty one and the TUI tiled beside it.
#
# So the package emits the bare TUI and whatever binds it decides how to
# display it. nixSpace.hyprdesktop.pomodoro wraps it with the primary terminal
# and a window class.
#
# RUNTIME DEPENDENCIES ARE WHAT THE SCRIPTS ACTUALLY CALL. The previous list
# carried imagemagick, hyprland, and alacritty — none of which appear in
# either script. hyprland in particular pulled the whole compositor into the
# closure of a timer.
{ pkgs }:
let
  runtimeDeps = with pkgs; [
    coreutils
    findutils
    gnused
    jq
    mpc
    swayimg
  ];

  pomodoroMain = pkgs.writeShellScriptBin "pomodoro" (builtins.readFile ./pomodoro.sh);

  # The TUI, not a launcher for it. "$@" is forwarded so a caller can pass an
  # alternative state file, which config-tui.py takes as argv[1].
  pomodoroConfig =
    pkgs.writeShellScriptBin "pomodoro-config" # sh
      ''
        exec ${pkgs.python3}/bin/python3 ${./config-tui.py} "$@"
      '';
in
pkgs.symlinkJoin {
  name = "pomodoro-timer";
  version = "1.1.0";

  paths = [
    pomodoroMain
    pomodoroConfig
  ];

  buildInputs = [ pkgs.makeWrapper ];

  postBuild = ''
    for bin in pomodoro pomodoro-config; do
      wrapProgram $out/bin/$bin \
        --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps}:$out/bin
    done
  '';

  meta = {
    description = "Pomodoro timer with a waybar ticker and a curses config UI";
    mainProgram = "pomodoro";
  };
}
