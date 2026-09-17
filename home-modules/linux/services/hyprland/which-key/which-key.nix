# wlr-which-key integration for Hyprland: self-documenting keybind menus.
#
# Menu entries declared here generate two things from one description —
# a wlr-which-key YAML config, and the Hyprland binds the entries name. The
# menu is therefore always a true account of what the keys do.
#
#   types.nix       the submodule types those entries are declared with
#   generate.nix    the transformation from entries to YAML and binds
#   menu.nix        the base preset every Hyprland host gets
#
# This file is the wiring: options built from the types, config built from
# the generators, plus the assertions that read `config`.
#
# TODO: Layout-context sensitive binds (dwindle vs. scrolling)
# TODO: Scrolling layout optimization (mouse swipe)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;

  cfg = config.nixSpace.hyprland.hyprWhichKey;
  hyprCfg = config.nixSpace.hyprland;

  wkTypes = import ./types.nix { inherit config lib pkgs; };

  hyprWkToggle = pkgs.writeShellApplication {
    name = "hypr-wk-toggle";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.hyprland
    ];
    text = # sh
    ''
      DEBUG_LOG=${if cfg.debugLog then "true" else "false"}
      WK=${lib.getExe cfg.package}
    ''
    + builtins.readFile ./hypr-wk-toggle.sh;
  };

  gen = import ./generate.nix { inherit lib cfg hyprWkToggle; };
in
{
  options.nixSpace.hyprland.hyprWhichKey = {
    enable = mkEnableOption "wlr-which-key menu" // {
      default = true;
      description = "Dynamically configure Hyprland keybinds with wlr-which-key menu entries.";
    };

    debugLog = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Keep a timestamped log per launch under
        $XDG_STATE_HOME/hypr-which-key/. Off by default; the last launch's
        output is kept regardless, for the failure notification.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.wlr-which-key;
      defaultText = lib.literalExpression "pkgs.wlr-which-key";
      description = "The wlr-which-key package.";
    };

    hypr = mkOption {
      type = wkTypes.submodule wkTypes.hyprOpts;
      default = { };
      description = "Hyprland-related configuration and bind-hint rendering.";
    };

    settings = mkOption {
      type = wkTypes.submodule wkTypes.settingsOpts;
      default = { };
      description = "Settings used to generate wlr-which-key config.yaml.";
    };
  };

  config = mkIf (hyprCfg.enable && cfg.enable) {
    # Duplicate binds are a warning, not an error: two entries on one key can
    # be intentional, and the second silently loses.
    warnings = lib.mkAfter (
      let
        bindEntries = lib.filter (entry: (entry.hyprBind or null) != null) gen.allEntries;
        byKey = lib.groupBy (
          entry: lib.concatStringsSep " " (entry.hyprBind.mods ++ [ entry.hyprBind.key ])
        ) bindEntries;
        dupSets = lib.filterAttrs (_: entries: builtins.length entries > 1) byKey;

        showEntry =
          entry:
          "${entry.desc or "<no desc>"} (group=${entry.__hyprWhichKeyGroup or "<unknown>"}, menuKey=${
            toString (entry.menuKey or "?")
          })";

        mkWarn =
          _: entries:
          let
            shown = gen.printHyprKey (builtins.head entries);
            dupKey = if shown == null then "<unknown>" else shown;
          in
          ''
            nixSpace.hyprland.hyprWhichKey: duplicate Hyprland bind "${dupKey}" is used by multiple entries:
              - ${lib.concatStringsSep "\n  - " (map showEntry entries)}
          '';
      in
      lib.mapAttrsToList mkWarn dupSets
    );

    assertions =
      let
        missingMenuGroups = lib.filter (g: !(cfg.settings.menu.groups ? ${g})) cfg.settings.menu.root;
        quoteList = entries: lib.concatStringsSep ", " (map (e: "'${e}'") entries);
      in
      [
        {
          assertion = config.xdg.enable or false;
          message = ''
            nixSpace.hyprland.hyprWhichKey requires xdg to be enabled — the
            config file is written under xdg.configFile.
          '';
        }
        {
          # A string here under Lua renders as
          # hl.bind("$mainMod, Q, exec, alacritty") — valid Lua, wrong
          # semantics, and no error until Hyprland loads it.
          assertion = !gen.luaMode || lib.all lib.isAttrs cfg.hypr.extraBinds;
          message = ''
            nixSpace.hyprland.hyprWhichKey.hypr.extraBinds contains hyprlang
            bind strings while configType = "lua". Supply the attrset form
            with mods, key, and action.
          '';
        }
        {
          assertion = config.wayland.windowManager.hyprland.enable or false;
          message = ''
            nixSpace.hyprland.hyprWhichKey requires Hyprland to be enabled via
            Home Manager: wayland.windowManager.hyprland.enable = true;
          '';
        }
        {
          assertion = missingMenuGroups == [ ];
          message = ''
            nixSpace.hyprland.hyprWhichKey: root references unknown groups:
              ${quoteList missingMenuGroups}

            Defined groups are:
              ${quoteList (builtins.attrNames cfg.settings.menu.groups)}
          '';
        }
      ];

    xdg.configFile."wlr-which-key/config.yaml".text = gen.yamlText;

    home.packages = [
      cfg.package
      hyprWkToggle
    ];

    wayland.windowManager.hyprland.settings = lib.mkMerge [
      # hyprlang: "$name = value" variables. Lua: { name = { _var = value; }; },
      # rendered as `local name = value`.
      (if gen.luaMode then gen.luaKeyVars else cfg.hypr.keyVars)
      {
        bind = lib.mkAfter (
          [ gen.leaderBind ]
          ++ gen.generatedBinds
          ++ map (b: gen.mkHyprBind { hyprBind = b; }) cfg.hypr.extraBinds
        );
      }
    ];
  };
}
