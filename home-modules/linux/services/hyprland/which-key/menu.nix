# hyprWhichKey menu preset.
#
# Splits the menu into two kinds of content:
#
#   COMPOSITOR OPERATIONS (window, workspaces, display, power) — defaults,
#   because they are Hyprland vocabulary. Anyone running Hyprland wants a way
#   to close a window and switch workspaces, and the keys are conventional.
#
#   APPLICATIONS (apps) — a TEMPLATE naming only tools the Hyprland preset
#   itself installs. The previous version defaulted to Dolphin, Element, and a
#   calculator, which are not installed by anything here — every entry was a
#   menu item that ran a missing binary on a machine that had not separately
#   installed them.
#
# Everything is lib.mkDefault, so a user replaces any group wholesale by
# assigning to it. Workspace entries are GENERATED rather than written out
# ten times.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.hyprland;

  # Workspace 0 is workspace 10 — the key label and the target differ, which is
  # why this is a mapping rather than a range.
  workspaceKeys = [
    {
      key = "1";
      ws = "1";
    }
    {
      key = "2";
      ws = "2";
    }
    {
      key = "3";
      ws = "3";
    }
    {
      key = "4";
      ws = "4";
    }
    {
      key = "5";
      ws = "5";
    }
    {
      key = "6";
      ws = "6";
    }
    {
      key = "7";
      ws = "7";
    }
    {
      key = "8";
      ws = "8";
    }
    {
      key = "9";
      ws = "9";
    }
    {
      key = "0";
      ws = "10";
    }
  ];

  # Directions are given in Hyprland's single-letter form. Under Lua, focus
  # takes spelled-out names while window.move takes the letters — the module's
  # dispatchMap handles that asymmetry, so it must not be pre-translated here.
  directions = [
    {
      key = "h";
      dir = "l";
      name = "left";
    }
    {
      key = "j";
      dir = "d";
      name = "down";
    }
    {
      key = "k";
      dir = "u";
      name = "up";
    }
    {
      key = "l";
      dir = "r";
      name = "right";
    }
  ];

  switchWorkspace = w: {
    desc = "Switch to workspace ${w.ws}";
    menuKey = w.key;
    hyprBind = {
      mods = [ "$mainMod" ];
      inherit (w) key;
      action = {
        type = "dispatch";
        dispatch = "workspace";
        arg = w.ws;
      };
    };
  };

  moveToWorkspace = w: {
    desc = "Move window to workspace ${w.ws}";
    # Uppercase so it does not collide with the switch entry above in the same
    # menu — wlr-which-key needs unique keys per menu, and menuKey is
    # case-sensitive.
    menuKey = lib.toUpper w.key;
    hyprBind = {
      mods = [
        "$mainMod"
        "$shiftMod"
      ];
      inherit (w) key;
      action = {
        type = "dispatch";
        dispatch = "movetoworkspace";
        arg = w.ws;
      };
    };
  };

  focusDirection = d: {
    desc = "Focus ${d.name}";
    menuKey = d.key;
    hyprBind = {
      mods = [ "$mainMod" ];
      inherit (d) key;
      action = {
        type = "dispatch";
        dispatch = "movefocus";
        arg = d.dir;
      };
    };
  };

  moveDirection = d: {
    desc = "Move window ${d.name}";
    menuKey = lib.toUpper d.key;
    hyprBind = {
      mods = [
        "$mainMod"
        "$shiftMod"
      ];
      inherit (d) key;
      action = {
        type = "dispatch";
        dispatch = "movewindow";
        arg = d.dir;
      };
    };
  };
in
{
  config = lib.mkIf cfg.enable {
    nixSpace.hyprland.hyprWhichKey.settings.menu = {
      root = lib.mkDefault [
        "apps"
        "power"
        "screen"
        "window"
        "workspaces"
      ];

      groups = {
        apps = {
          desc = "Apps/Launchers";
          key = "a";
        };
        power = {
          desc = "Power/Exit/Lock";
          key = "p";
        };
        screen = {
          key = "s";
          desc = "Screen";
          submenu = [
            {
              desc = "Screenshots";
              key = "s";
              fromGroup = "screenshots";
            }
            {
              desc = "Wallpaper select";
              key = "w";
              cmd = "waypaper";
            }
          ];
        };
        screenshots = {
          key = "s";
          desc = "Screenshots";
        };
        window = {
          desc = "Window";
          key = "w";
        };
        workspaces = {
          desc = "Workspaces";
          key = "k";
        };
      };

      entries = {
        # Example app template
        apps = lib.mkDefault [
          {
            desc = "Terminal";
            menuKey = "t";
            hyprBind = {
              mods = [ "$mainMod" ];
              key = "q";
              action = {
                type = "exec";
                cmd = config.nixSpace.programs.terminals.primaryCommand;
              };
            };
          }
          {
            desc = "Launcher";
            menuKey = "r";
            hyprBind = {
              mods = [ "$mainMod" ];
              key = "r";
              action = {
                type = "exec";
                cmd = config.nixSpace.programs.launchers.primaryCommand;
              };
            };
          }
          {
            desc = "Clipboard history";
            menuKey = "c";
            cmd = "${lib.getExe pkgs.cliphist} list | ${config.nixSpace.programs.launchers.dmenuCommand} | ${lib.getExe pkgs.cliphist} decode | wl-copy";
          }
        ];

        window = [
          {
            desc = "Close active window";
            menuKey = "c";
            hyprBind = {
              mods = [ "$mainMod" ];
              key = "c";
              action = {
                type = "dispatch";
                dispatch = "killactive";
              };
            };
          }
          {
            desc = "Fullscreen";
            menuKey = "f";
            hyprBind = {
              mods = [ "$mainMod" ];
              key = "f";
              action = {
                type = "dispatch";
                dispatch = "fullscreen";
                arg = "1";
              };
            };
          }
          {
            desc = "Toggle floating";
            menuKey = "F";
            hyprBind = {
              mods = [
                "$mainMod"
                "$shiftMod"
              ];
              key = "F";
              action = {
                type = "dispatch";
                dispatch = "togglefloating";
              };
            };
          }
          {
            desc = "Toggle pseudotile";
            menuKey = "p";
            hyprBind = {
              mods = [ "$mainMod" ];
              key = "p";
              action = {
                type = "dispatch";
                dispatch = "pseudo";
              };
            };
          }
          {
            desc = "Toggle split";
            menuKey = "s";
            hyprBind = {
              mods = [
                "$mainMod"
                "$shiftMod"
              ];
              key = "T";
              # layoutmsg, not dispatch: togglesplit was folded into the
              # layout message set in 0.54, and under Lua this renders as
              # hl.dsp.layout("togglesplit").
              action = {
                type = "layoutmsg";
                message = "togglesplit";
              };
            };
          }
        ]
        ++ map focusDirection directions
        ++ map moveDirection directions;

        workspaces =
          map switchWorkspace workspaceKeys
          ++ map moveToWorkspace workspaceKeys
          ++ [
            {
              desc = "Toggle scratch workspace";
              menuKey = "s";
              hyprBind = {
                mods = [ "$mainMod" ];
                key = "s";
                action = {
                  type = "dispatch";
                  dispatch = "togglespecialworkspace";
                  arg = "magic";
                };
              };
            }
            {
              desc = "Move window to scratch workspace";
              menuKey = "S";
              hyprBind = {
                mods = [
                  "$mainMod"
                  "$shiftMod"
                ];
                key = "S";
                action = {
                  type = "dispatch";
                  dispatch = "movetoworkspace";
                  arg = "special:magic";
                };
              };
            }
          ];

        power = [
          {
            desc = "Exit Hyprland";
            menuKey = "e";
            # hl.dsp.exit(), not the legacy "exit" string: under Lua,
            # `hyprctl dispatch exit` is parsed as Lua and fails.
            cmd = "hyprctl dispatch 'hl.dsp.exit()'";
          }
          {
            desc = "Lock";
            menuKey = "l";
            cmd = "loginctl lock-session";
          }
          {
            desc = "Poweroff";
            menuKey = "o";
            cmd = "systemctl poweroff";
          }
          {
            desc = "Reboot";
            menuKey = "r";
            cmd = "systemctl reboot";
          }
          {
            desc = "Suspend";
            menuKey = "s";
            cmd = "systemctl suspend";
          }
        ];

        screenshots = lib.mkDefault [
          {
            desc = "Output";
            menuKey = "o";
            hyprBind = {
              key = "PRINT";
              action = {
                type = "exec";
                cmd = "${lib.getExe pkgs.hyprshot} -m output";
              };
            };
          }
          {
            desc = "Region";
            menuKey = "r";
            hyprBind = {
              mods = [ "$shiftMod" ];
              key = "PRINT";
              action = {
                type = "exec";
                cmd = "${lib.getExe pkgs.hyprshot} -m region";
              };
            };
          }
          {
            desc = "Window";
            menuKey = "w";
            hyprBind = {
              mods = [ "$mainMod" ];
              key = "PRINT";
              action = {
                type = "exec";
                cmd = "${lib.getExe pkgs.hyprshot} -m window";
              };
            };
          }
        ];
      };
    };
  };
}
