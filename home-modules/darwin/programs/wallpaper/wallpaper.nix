# Wallpaper scripts for macOS.
#
# DARWIN ONLY, and deliberately not the cross-platform module it replaces.
# That one branched on an `os` option in every function, and the two halves
# shared nothing but the cycling logic — osascript against System Events on
# one side, awww against wlr-layer-shell on the other.
#
# The Linux half is dropped rather than ported: awww sets a wallpaper and
# waypaper picks one, so the only thing missing there was cycling, which is
# not worth a module that has to branch throughout to provide.
#
# SCRIPTS AS FILES, not writeShellScriptBin strings — shellcheck cannot read
# into a Nix '' string, and the escaping in the previous version had six
# consecutive quotes trying to express `read -d ''`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.wallpaper;

  # osascript is in the OS, not in nixpkgs, so it is called by name — the one
  # place in these modules where a bare command is not a portability lapse.
  wallpaperSet = pkgs.writeShellApplication {
    name = "wallpaper-set";
    runtimeInputs = [ ];
    text = builtins.readFile ./wallpaper-set.sh;
  };

  wallpaperCycle = pkgs.writeShellApplication {
    name = "wallpaper-cycle";
    runtimeInputs = [
      pkgs.findutils
      pkgs.gawk
      pkgs.coreutils
    ];
    text = builtins.readFile ./wallpaper-cycle.sh;
  };
in
{
  options.nixSpace.programs.wallpaper = {
    enable = lib.mkEnableOption "macOS wallpaper scripts";

    directory = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "\${config.home.homeDirectory}/Pictures/wallpapers";
      description = ''
        Directory `wallpaper-cycle` reads with no argument, or null to use
        whichever directory the CURRENT wallpaper is in.

        Null is the better default: it means changing the wallpaper by any
        other route — System Settings, a different script — moves the cycle
        with it, rather than the cycle snapping back to a configured folder.

        Set it where the current wallpaper may be somewhere you do not want
        to cycle through, such as a system default.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = ''
          nixSpace.programs.wallpaper is macOS only — it drives System
          Events through osascript, which does not exist elsewhere.

          On Linux use nixSpace.hyprdesktop.wallpaper, which runs awww and
          waypaper.
        '';
      }
    ];

    home.packages = [
      wallpaperSet
      wallpaperCycle
    ];

    # A default argument rather than baking the path into the script, so
    # `wallpaper-cycle /some/other/dir` still works.
    nixSpace.programs.shells.aliases = lib.mkIf (cfg.directory != null) {
      wallpaper-cycle = "wallpaper-cycle ${cfg.directory}";
    };
  };
}
