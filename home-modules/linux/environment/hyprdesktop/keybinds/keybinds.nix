# Application launcher entries for the Hyprland desktop bundle.
#
# The which-key base preset (which-key-menu.nix) ships the compositor
# vocabulary — window, workspaces, power, screenshots — as mkDefault, and a
# minimal apps group naming only what the Hyprland preset installs. This file
# REPLACES that apps group with the bundle's, which is why the base's own
# entries (terminal, launcher, clipboard) appear here too: replacing means
# they are not inherited.
#
# Wholesale replacement is deliberate. Merging would mean a host wanting to
# drop the base's clipboard entry has to mkForce the whole list anyway, so
# the mechanism might as well be replacement from the start.
#
# APPLICATION ENTRIES ARE GATED on the module that installs the application.
# An entry for a program that is not installed is worse than none: the
# overlay shows it, and pressing it does nothing. Each read goes through
# `or`, so a gate is safe when its module is not imported at all.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.hyprdesktop.keybinds;

  terminal = config.nixSpace.programs.terminals.primaryCommand;
  launcher = config.nixSpace.programs.launchers.primaryCommand;
  dmenu = config.nixSpace.programs.launchers.dmenuCommand;

  firefoxOn = config.nixSpace.programs.firefox.enable or false;
  onlyofficeOn = config.nixSpace.programs.office.onlyoffice.enable or false;
  yaziOn = config.nixSpace.programs.yazi.enable or false;
  tmuxOn = config.nixSpace.programs.multiplexers.tmux.enable or false;
  oathGuiOn = config.nixSpace.security.yubikey.tools.oathGui or false;
  elementOn = (config.nixSpace.programs.messaging.element or null) != null;
  signalOn = (config.nixSpace.programs.messaging.signal or null) != null;

  bind =
    mods: key: cmd: {
      inherit mods key;
      action = {
        type = "exec";
        inherit cmd;
      };
    };
in
{
  options.nixSpace.hyprdesktop.keybinds = {
    enable = lib.mkEnableOption "the desktop bundle's application launcher menu";
  };

  config = lib.mkIf cfg.enable {
    nixSpace.hyprland.hyprWhichKey = {
      hypr.extraBinds = [
        (bind [ "$mainMod" ] "F1" "rofi-help-menu")
      ];

      settings.menu.entries.apps =
        [
          # Base entries, restated — see the header.
          {
            desc = "Terminal";
            menuKey = "q";
            hyprBind = bind [ "$mainMod" ] "q" terminal;
          }
          {
            desc = "Run";
            menuKey = "r";
            hyprBind = bind [ "$mainMod" ] "r" launcher;
          }
          {
            desc = "Clipboard History";
            menuKey = "h";
            cmd = "${lib.getExe pkgs.cliphist} list | ${dmenu} | ${lib.getExe pkgs.cliphist} decode | wl-copy";
          }

          # Bundle additions with no module to gate on. rofi is enabled by
          # the bundle itself, so these are safe here.
          {
            desc = "Calculator";
            menuKey = "c";
            cmd = "rofi -show-icons -combi-modi drun,run -show calc";
          }
          {
            desc = "eMoji Picker";
            menuKey = "m";
            cmd = "rofi -show-icons -combi-modi drun,run -show emoji";
          }
        ]
        ++ lib.optional elementOn {
          desc = "ElementDesktop";
          menuKey = "e";
          cmd = "element-desktop";
        }
        ++ lib.optional firefoxOn {
          desc = "Firefox";
          menuKey = "f";
          cmd = "firefox";
        }
        ++ lib.optional onlyofficeOn {
          desc = "OnlyOffice";
          menuKey = "o";
          cmd = "onlyoffice-desktopeditors";
        }
        ++ lib.optional signalOn {
          desc = "SignalDesktop";
          menuKey = "s";
          # No --use-tray-icon: the overlay bakes it into the wrapper, so the
          # bare command is what the desktop file runs too.
          cmd = "signal-desktop";
        }
        ++ lib.optional tmuxOn {
          desc = "Tmux";
          menuKey = "t";
          hyprBind = bind [ "$mainMod" ] "t" "${terminal} -e tmux new-session -A -s main";
        }
        ++ lib.optional oathGuiOn {
          desc = "yUbikey Oath";
          menuKey = "u";
          hyprBind = bind [ "$mainMod" ] "u" "yubioath-flutter";
        }
        ++ lib.optional yaziOn {
          desc = "Yazi";
          menuKey = "y";
          hyprBind = bind [ "$mainMod" ] "y" "${terminal} -e yazi";
        };
    };
  };
}
