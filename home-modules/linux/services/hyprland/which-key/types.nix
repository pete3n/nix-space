# Submodule types for the which-key module.
#
# A function of the module arguments rather than a bare attrset because the
# style defaults read the palette and the hypr defaults read the Hyprland
# preset — both of which are `config`, and `config` is only in scope inside a
# module. Called once from which-key.nix's `let`.
#
# The bind submodule is defined once and used twice: extraBinds needs the
# TYPE, an entry's hyprBind needs a nullable OPTION wrapping it. One
# definition means both validate identically and the generator renders either
# without caring which it came from.
{
  config,
  lib,
  pkgs,
}:
let
  inherit (lib) mkOption types;

  palette = config.nixSpace.palette;
  hyprCfg = config.nixSpace.hyprland;

  submodule = opts: types.submodule { options = opts; };
in
rec {
  hyprActionOpts = {
    type = mkOption {
      type = types.enum [
        "nop"
        "exec"
        "dispatch"
        "layoutmsg" # layout-specific messages sent via `layoutmsg` dispatcher (e.g. togglesplit)
        "luaDispatch" # raw hl.dsp call; configType = "lua" only
      ];
      default = "nop";
      description = "Hyprland action type.";
    };

    cmd = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Command for type=exec.";
    };

    dispatch = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Dispatcher name for type=dispatch (e.g., movefocus).";
    };

    arg = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional argument for type=dispatch.";
    };

    lua = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Raw Lua dispatcher call for type=luaDispatch, e.g.
        "hl.dsp.window.resize({ x = 10, y = 0, relative = true })".

        The escape hatch for dispatchers with no dispatchMap entry — hl.dsp
        is a structured namespace, so it cannot be mapped mechanically.
        Has no hyprlang equivalent; using it under configType = "hyprlang"
        is an error rather than a silent skip.
      '';
      example = ''hl.dsp.window.float({ action = "toggle" })'';
    };

    message = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Layout message for type=layoutmsg.
        Generates: bind = MODS, KEY, layoutmsg, MESSAGE
        Use this for dispatchers removed in 0.54 that were folded into layoutmsg
        (e.g. togglesplit, swapsplit).
      '';
    };
  };
  hyprActionModule = submodule hyprActionOpts;

  hyprBindModule = types.submodule {
    options = {
      mods = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''List of Hyprland modifier variables (e.g. ["$mainMod" "$shiftMod"]).'';
      };

      key = mkOption {
        type = types.str;
        description = ''Hyprland key (e.g. "j", "PRINT").'';
      };

      action = mkOption {
        type = hyprActionModule;
        default = { };
        description = "Hyprland action executed by this bind.";
      };

      showHint = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          If set, overrides showBindHints for this entry.
          null means "use the module default".
        '';
      };
    };
  };

  hyprBindOption = mkOption {
    type = types.nullOr hyprBindModule;
    default = null;
    description = ''
      Hyprland keybind generated for this entry, or null for a
      menu-only entry.
    '';
  };

  menuEntryOpts = {
    desc = mkOption {
      type = types.str;
      description = "Menu description.";
    };

    menuKey = mkOption {
      type = types.str;
      description = "Key used inside wlr-which-key.";
    };

    cmd = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Command executed when selecting this entry in wlr-which-key.
        Use this for menu-only entries that don't generate a Hyprland bind.
      '';
    };

    hyprBind = hyprBindOption;
  };
  menuEntryModule = submodule menuEntryOpts;

  groupOpts = {
    key = mkOption {
      type = types.str;
      description = "Key binding to enter the group menu.";
    };

    desc = mkOption {
      type = types.str;
      description = "Menu group description.";
    };

    submenu = mkOption {
      type = types.nullOr (types.listOf types.attrs);
      default = null;
      description = ''
        Optional submenu entries. These can be created explicitly as
        individual submenu list entries, or from another group using the
        fromGroup option.
      '';
      example = lib.literalExpression ''
        [
          {
            key = "F1";
            desc = "Searchable help";
            cmd = "rofi-help-menu";
          }
          {
            fromGroup = "navigation";
            key = "n";
            desc = "Navigation";
          }
        ]
      '';
    };
  };
  groupModule = submodule groupOpts;

  styleOpts = {
    anchor = mkOption {
      type = types.str;
      default = "center";
      description = "Screen anchor for the overlay.";
    };

    background = mkOption {
      type = types.str;
      default = palette.background;
      defaultText = lib.literalExpression "config.nixSpace.palette.background";
      description = ''
        Overlay background, #RRGGBB. Translucency is `opacity` below — the
        palette stores no alpha, since three of its consumers cannot parse
        one.
      '';
    };

    opacity = mkOption {
      type = types.numbers.between 0.0 1.0;
      default = 0.82;
      description = ''
        Overlay opacity, composed with `background` into the #RRGGBBAA form
        wlr-which-key takes.
      '';
    };

    border = mkOption {
      type = types.str;
      default = palette.accent;
      defaultText = lib.literalExpression "config.nixSpace.palette.accent";
      description = "Border colour, #RRGGBB.";
    };

    color = mkOption {
      type = types.str;
      default = palette.foreground;
      defaultText = lib.literalExpression "config.nixSpace.palette.foreground";
      description = "Text colour, #RRGGBB.";
    };

    font = mkOption {
      type = types.str;
      default = "${config.nixSpace.fonts.monospace.name} 24";
      defaultText = lib.literalExpression ''"''${config.nixSpace.fonts.monospace.name} 24"'';
      description = "Pango font description.";
    };

    separator = mkOption {
      type = types.str;
      default = " ➜ ";
      description = "Rendered between a key and its description.";
    };

    borderWidth = mkOption {
      type = types.ints.unsigned;
      default = 2;
    };

    cornerRnd = mkOption {
      type = types.ints.unsigned;
      default = 10;
      description = "Corner radius in pixels.";
    };

    padding = mkOption {
      type = types.nullOr types.ints.unsigned;
      default = null;
      description = "Defaults to cornerRnd when null.";
    };

    rowsPerColumn = mkOption {
      type = types.nullOr types.ints.unsigned;
      default = null;
      description = "No limit when null.";
    };

    columnPadding = mkOption {
      type = types.nullOr types.ints.unsigned;
      default = null;
      description = "Defaults to padding when null (and padding defaults to cornerRnd).";
    };

    marginRight = mkOption {
      type = types.ints.unsigned;
      default = 0;
    };
    marginLeft = mkOption {
      type = types.ints.unsigned;
      default = 0;
    };
    marginBottom = mkOption {
      type = types.ints.unsigned;
      default = 0;
    };
    marginTop = mkOption {
      type = types.ints.unsigned;
      default = 0;
    };
  };

  menuOpts = {
    groups = mkOption {
      type = types.attrsOf groupModule;
      default = { };
      description = ''
        An unordered set of menu groups. Each has a description and a key
        that opens it. The entries set holds the leaf entries and can
        generate Hyprland keybinds; groups can optionally carry submenus,
        built from other groups via fromGroup or as plain key/command pairs.
        Submenus cannot currently generate Hyprland keybinds.
      '';
    };

    entries = mkOption {
      type = types.attrsOf (types.listOf menuEntryModule);
      default = { };
      description = "Ordered lists of menu entries, keyed by group name.";
    };

    root = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Ordered list of group names shown in the root menu.";
    };
  };

  settingsOpts = {
    leaderMods = mkOption {
      type = types.listOf types.str;
      default = [ "$mainMod" ];
      description = ''
        Modifiers for the menu leader bind.

        Split from leaderKey because the old combined form
        ("$mainMod, space") is hyprlang syntax with no Lua meaning — it
        would have been emitted verbatim into a Lua string.
      '';
      example = [
        "$mainMod"
        "$shiftMod"
      ];
    };

    leaderKey = mkOption {
      type = types.str;
      default = "space";
      description = "Key that opens the menu, without modifiers.";
    };

    showHyprKeyInDesc = mkOption {
      type = types.bool;
      default = true;
      description = "Append a formatted Hyprland keybind hint to entry descriptions.";
    };

    hyprKeyDescFormat = mkOption {
      type = types.str;
      default = " ({keys})";
      description = ''Format string for the bind hint. "{keys}" is the placeholder.'';
    };

    style = mkOption {
      type = submodule styleOpts;
      default = { };
      description = "Menu style and theming.";
    };

    inhibit_compositor_keyboard_shortcuts = mkOption {
      type = types.bool;
      default = false;
      description = "Permits key bindings that conflict with compositor key bindings.";
    };

    auto_kbd_layout = mkOption {
      type = types.bool;
      default = false;
      description = "Try to guess the correct keyboard layout to use.";
    };

    menu = mkOption {
      type = submodule menuOpts;
      default = { };
      description = "Menu generation settings.";
    };
  };

  hyprOpts = {
    configType = mkOption {
      type = types.enum [
        "hyprlang"
        "lua"
      ];
      default = config.wayland.windowManager.hyprland.configType or "hyprlang";
      defaultText = lib.literalMD "Inherited from `wayland.windowManager.hyprland.configType`.";
      description = ''
        Which config language to generate binds for.

        Defaults to whatever the Hyprland module is set to, so the two
        cannot drift. Generating hyprlang bind strings into a Lua file
        produces `hl.bind("$mainMod, q, exec, alacritty")` — syntactically
        valid Lua that means nothing, with no error until Hyprland loads it.
      '';
    };

    keyVars = mkOption {
      type = types.attrsOf types.str;
      default = {
        "$mainMod" = hyprCfg.mainMod;
        "$shiftMod" = hyprCfg.shiftMod;
        "$altMod" = hyprCfg.altMod;
      };
      defaultText = lib.literalMD "Sourced from `nixSpace.hyprland.{mainMod,shiftMod,altMod}`.";
      description = ''
        Modifier variables, merged into hyprland.settings.

        Defaults come from the Hyprland preset rather than being restated:
        the preset emits these as Lua locals, and two independent definitions
        of "what SUPER is called" would let the binds this module generates
        reference a variable the preset never declared.

        The $ prefix is a hyprlang sigil. Under configType = "lua" it is
        stripped — $ is not legal in a Lua identifier.
      '';
    };

    printMods = mkOption {
      type = types.attrsOf types.str;
      default = {
        "SUPER" = "Super";
        "SHIFT" = "Shift";
        "CTRL" = "Ctrl";
        "ALT" = "Alt";
      };
      description = "How to display modifier names in bind hints.";
    };

    showBindHints = mkOption {
      type = types.bool;
      default = true;
      description = "Append bind hints to descriptions by default; entries can override via showHint.";
    };

    extraBinds = mkOption {
      type = types.listOf hyprBindModule;
      default = [ ];
      description = ''
        Extra binds appended after the generated ones, in the same
        structured form as an entry's hyprBind so one code path renders
        either config language and the same validation applies.

        For a dispatcher with no dispatchMap entry, use
        action.type = "luaDispatch" with the raw hl.dsp call.
      '';
      example = lib.literalExpression ''
        [
          {
            mods = [ "$mainMod" ];
            key = "F1";
            action = {
              type = "exec";
              cmd = "rofi-help-menu";
            };
          }
        ]
      '';
    };
  };

  inherit submodule;
}
