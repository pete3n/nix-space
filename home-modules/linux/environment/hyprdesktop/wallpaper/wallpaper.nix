# Wallpaper daemon and picker.
#
# TWO PROGRAMS, ONE-WAY DEPENDENCY.
#
#   awww-daemon holds the wlr-layer-shell surface and does the transitions;
#   `awww img <path>` sets an image at runtime. It works alone — a script or a
#   login hook can drive it.
#
#   waypaper is a GUI chooser. It presents a grid and shells out to a backend
#   to apply the selection. Without a backend it has nothing to call.
#
# So the daemon is the dependency and the picker is optional, which is why
# they are separate flags rather than one.
#
# COMPOSITOR CONSTRAINT: awww needs wlr-layer-shell and will not run on
# Gnome. That is fine here — this is the Hyprland bundle — but it is why the
# module lives under wm/hyprland/desktop/ rather than somewhere general.
#
# NOTE ON THE NAME: awww is the renamed swww. Some tooling still refers to the
# old name, and waypaper dispatches to a backend BY NAME — so if its backend
# list predates the rename, it will try to call a binary that no longer
# exists.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.hyprdesktop.wallpaper;
in
{
  options.nixSpace.hyprdesktop.wallpaper = {
    enable = lib.mkEnableOption "wallpaper daemon";
    picker = lib.mkEnableOption "wallpaper picker";
    directory = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "\${config.xdg.userDirs.pictures}/wallpapers";
      description = ''
        Directory waypaper opens in.

        Null leaves waypaper's own default, which is its last-used path stored
        in its config — mutable state this module does not manage. Set it to
        make the starting point declarative.
      '';
    };

    menuKey = lib.mkOption {
      type = lib.types.str;
      default = "w";
      description = ''
        Key for the picker entry in the which-key display group.

        Must not collide with another entry in that group — wlr-which-key
        needs unique keys per menu, and a duplicate makes one of the two
        unreachable with no error.
      '';
    };
  };

  config = lib.mkIf (config.nixSpace.hyprdesktop.enable && cfg.enable) (
    lib.mkMerge [
      {
        services.awww.enable = true;
      }

      (lib.mkIf cfg.picker {
        home.packages = [ pkgs.waypaper ];

        # Appended to the display group rather than replacing it: listOf
        # concatenates across definitions at the same priority, and the
        # module's own entries are not mkDefault.
        nixSpace.hyprland.hyprWhichKey.settings.menu.entries.display = [
          {
            desc = "Wallpaper select";
            menuKey = cfg.menuKey;

            # cmd, not hyprBind: this is a menu-only entry. Binding a key to a
            # GUI picker that is used occasionally would spend a combination
            # for little gain.
            cmd =
              "${lib.getExe pkgs.waypaper}"
              + lib.optionalString (cfg.directory != null) " --folder ${cfg.directory}";
          }
        ];
      })
    ]
  );
}
