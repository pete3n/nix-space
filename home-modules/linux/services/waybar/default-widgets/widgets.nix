# Waybar default widgets and styling module.
#
# Do not use lib.mkDefault inside widget definitions:
# mkDefault produces a plain attrset — { _type = "override"; priority = 1000;
# content = ...; } which mangles the attrsOf (attrsOf anything) typed by the
# widgets. Overriding still works
#
# Nothing here is compositor-specific; the Hyprland workspace widget lives in
# default.nix behind its own flag. A clock is included, and the hyprdesktop
# bundle replaces modulesCenter with its pomodoro-backed custom/clock, this is
# a list assignment, so the two cannot both appear.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.waybar;
in
{
  options.nixSpace.waybar = {
    defaultWidgets = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Contribute a working default widget set.

        False leaves the bar empty except for what feature modules add, which
        is what you want when composing a bar entirely by hand.
      '';
    };

    defaultStyle = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Apply the bundled stylesheet.

        An explicit flag rather than a mkDefault on `style`: that option is
        types.lines, and lines cat across definitions, so a default could only 
        ever be appended to, never replaced. Set this false to write a 
        stylesheet from scratch.
      '';
    };

    backlight = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Include a backlight widget.

          Off by default because it needs a device name that varies by
          hardware, and a wrong one shows nothing rather than erroring.
        '';
      };

      device = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "amdgpu_bl1";
        description = ''
          sysfs backlight device, as listed by
          `ls /sys/class/backlight`.

          Empty lets waybar pick the first it finds, which is usually right on
          a laptop with one panel.
        '';
      };
    };

    accentColor = lib.mkOption {
      type = lib.types.str;
      default = "#7ebae4";
      description = "Accent used by the default stylesheet for icons and hover.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (lib.mkIf cfg.defaultWidgets {
        nixSpace.waybar.modulesRight = lib.mkDefault (
          [
            "pulseaudio"
          ]
          ++ lib.optional cfg.nixSpace.waybar.backlight.enable "backlight"
          ++ lib.optional cfg.displaySettings "custom/wdisplays"
          ++ [
            "battery"
          ]
        );

        # No modulesLeft here: hyprland/workspaces is the only default
        # left-hand widget and it places itself with autoPlace.
        nixSpace.waybar.modulesCenter = lib.mkDefault [ "clock" ];

        nixSpace.waybar.modules = {
          # KNOWN BROKEN UPSTREAM: clicking a workspace number does not switch
          # to it under a Lua Hyprland config. Waybar's internal click handler
          # issues a legacy dispatcher call, and an explicit on-click does NOT
          # override it. Keyboard binds are unaffected.
          "hyprland/workspaces" = lib.mkIf cfg.hyprlandWorkspaces {
            autoPlace = "left";

            format = "{name} {icon}";
            tooltip = false;
            all-outputs = true;
            format-icons = {
              "active" = " ";
              "default" = " ";
            };

            # exec_raw takes a legacy hyprlang string, which is the supported
            # escape hatch, because a bare `dispatch workspace e+1` is a Lua
            # syntax error under a Lua config.
            on-scroll-up = "hyprctl dispatch 'hl.dsp.focus({ workspace = \"e+1\" })'";
            on-scroll-down = "hyprctl dispatch 'hl.dsp.focus({ workspace = \"e-1\" })'";

            style = ''
              #workspaces button {
              	padding: 0 6px;
              	color: ${cfg.accentColor};
              }

              #workspaces button.active {
              	background-color: rgba(126, 186, 228, 0.2);
              }

              #workspaces button.urgent {
              	color: #cc6666;
              }
            '';
          };

          tray = {
            autoPlace = "left";
            spacing = 10;

            style = ''
              /* An item asking for attention should look different from one
                 that is merely present. */
              #tray > .needs-attention {
              	background-color: #cc6666;
              }
            '';
          };

          pulseaudio = {
            style = ''
              #pulseaudio {
              	color: ${cfg.accentColor};
              }

              #pulseaudio.muted {
              	color: #6b6b6b;
              }
            '';

            format = "{icon} {volume}%";
            format-muted = "󰝟 ";
            tooltip = true;
            format-icons = {
              headphone = "󰋋 ";
              default = [
                "󰕿 "
                "󰖀 "
                "󰕾 "
              ];
            };
            scroll-step = 1;
            on-click = (lib.getExe' pkgs.pavucontrol "pavucontrol");
          };

          battery = {
            # `good` exists so a nearly-full battery can be styled distinctly
            # from a discharged one. Without it there is no CSS hook for
            # "charged".
            states = {
              good = 80;
              warning = 30;
              critical = 15;
            };
            format = "{icon} {capacity}%";
            format-charging = " ⚡{capacity}%";

            # Click to swap capacity for estimated time remaining.
            format-alt = "{time} {icon}";
            format-icons = [
              " "
              " "
              " "
              " "
              " "
            ];
            style = # css
              ''
                #battery {
                	background: transparent;
                	color: ${cfg.accentColor};
                	padding-left: 10px;
                	padding-right: 10px;
                	border-radius: 6px;
                }

                #battery.good {
                color: ${cfg.accentColor};
                }

                #battery.warning {
                	color: #f0c674;
                }

                #battery.critical {
                	color: #cc6666;
                }

                /* Blink only when critical AND discharging — a critical battery
                	 already on the charger is being dealt with. */
                #battery.critical:not(.charging) {
                	animation: blink 1s steps(2, start) infinite;
                }

                @keyframes blink {
                	to {
                		color: #ffffff;
                	}
                }
              '';
          };

          clock = {
            style = ''
              #clock {
              	color: ${cfg.accentColor};
              }
            '';

            format = "{:%Y-%m-%d %H:%M}";
            tooltip-format = "<tt><small>{calendar}</small></tt>";
          };

        }
        // lib.optionalAttrs cfg.backlight.enable {
          backlight = {
            autoPlace = "right";
            format = "{icon} {percent}%";
            tooltip-format = "Brightness: {percent}%";
            scroll-step = 1;
            format-icons = [
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
              ""
            ];

            style = ''
              #backlight {
              	color: ${cfg.accentColor};
              }
            '';
          }
          // lib.optionalAttrs (cfg.backlight.device != "") {
            device = cfg.backlight.device;
          };
        };
      })

      (lib.mkIf cfg.defaultStyle {
        nixSpace.waybar.baseStyle = ''
          /* Bundled nixSpace base. Disable with
             nixSpace.waybar.defaultStyle = false; */

          * {
          	border: none;
          	border-radius: 0;

          	/* Nerd Font glyphs need a font that has them; without this the
          	   icon widgets render tofu boxes at the wrong metrics, which is
          	   what makes a bar look "cut off". */
          	font-family: "JetBrainsMono Nerd Font", monospace;
          	font-size: 14px;

          	/* Waybar sizes the bar to its tallest child. Without a floor,
          	   widgets whose glyphs are shorter than others sit at different
          	   heights and text clips at the top or bottom. */
          	min-height: 25px;
          }

          window#waybar {
          	background: transparent;
          }

          /* Waybar renders modules as different GTK widget types depending on
             the module, so all three selectors are needed to cover them. */
          #waybar button,
          #waybar label,
          #waybar box {
          	transition: background-color 0.2s ease;
          }

          #waybar button:hover,
          #waybar label:hover {
          	background-color: rgba(255, 255, 255, 0.1);
          }

          /* Horizontal breathing room for EVERY module, including ones this
             bundle does not define. Setting padding per widget instead left
             anything contributed elsewhere flush against its neighbour. */
          #waybar > box > box > widget > * {
          	padding: 0 8px;
          }
        '';

      })
    ]
  );
}
