# Generators for the which-key module: config values in, wlr-which-key YAML
# and Hyprland binds out.
#
# Pure functions of `cfg`, with no module context — this file could be
# evaluated against any attrset of the right shape. It takes `cfg` and the
# toggle script as arguments so that which-key.nix owns the wiring and this
# file owns the transformation.
#
# Two output languages are handled throughout: hyprlang returns bind
# STRINGS, Lua returns attrsets with _args that home-manager renders as
# hl.bind(combo, dispatcher). luaMode selects between them.
{
  lib,
  cfg,
  hyprWkToggle,
}:
let
  inherit (lib) concatLists;

  luaMode = cfg.hypr.configType == "lua";

  # ---- colour -----------------------------------------------------------

  # 0.0–1.0 opacity to the two-digit hex alpha wlr-which-key appends, so the
  # palette can stay alpha-free while this surface is translucent.
  #
  # Candidate for nixSpaceLib.colour alongside sketchybar's argb helper, once
  # a third consumer appears.
  alphaHex =
    o:
    let
      n = builtins.floor (o * 255 + 0.5);
      digits = "0123456789abcdef";
    in
    builtins.substring (n / 16) 1 digits + builtins.substring (n - (n / 16) * 16) 1 digits;

  # ---- wlr-which-key YAML ----------------------------------------------

  # github.com/MaxVerevkin/wlr-which-key/blob/master/README.md
  mkWkCfg =
    {
      style,
      inhibit_compositor_keyboard_shortcuts,
      auto_kbd_layout,
      menu,
    }:
    let
      padding' = if style.padding != null then style.padding else style.cornerRnd;
      columnPadding' = if style.columnPadding != null then style.columnPadding else padding';
      rowsPerColumnAttrs = lib.optionalAttrs (style.rowsPerColumn != null) {
        rows_per_column = style.rowsPerColumn;
      };
    in
    lib.generators.toYAML { } (
      {
        inherit (style) font;
        background = style.background + alphaHex style.opacity;
        inherit (style) color;
        inherit (style) border;
        inherit (style) separator;
        border_width = style.borderWidth;
        corner_r = style.cornerRnd;
        padding = padding';
        column_padding = columnPadding';

        inherit (style) anchor;
        margin_right = style.marginRight;
        margin_left = style.marginLeft;
        margin_bottom = style.marginBottom;
        margin_top = style.marginTop;

        inherit inhibit_compositor_keyboard_shortcuts auto_kbd_layout menu;
      }
      // rowsPerColumnAttrs
    );

  # ---- menu entries -----------------------------------------------------

  # wlr-which-key renders descriptions through Pango, which treats < > & as
  # markup. An unescaped < opens a tag that swallows everything up to the
  # next > and the description vanishes; a bare & is a parse error.
  #
  # & MUST come first: escaping it after < and > would double-escape the
  # &amp; entities those two just introduced.
  #
  # NOT applied to menuKey. wlr-which-key validates that as a KEY NAME before
  # rendering, so "&lt;" fails to deserialize.
  pangoEscape = lib.replaceStrings [ "&" "<" ">" ] [ "&amp;" "&lt;" "&gt;" ];

  # Command wlr-which-key runs when an entry is selected.
  mkHyprCmd =
    entry:
    let
      action = entry.hyprBind.action or { type = "nop"; };
    in
    if action.type == "exec" then
      action.cmd
    else if luaMode then
      let
        call = luaAction action;
      in
      if call == null then "true" else "hyprctl dispatch '${call}'"
    else if action.type == "dispatch" then
      "hyprctl dispatch ${action.dispatch}" + lib.optionalString (action.arg != null) " ${action.arg}"
    else if action.type == "layoutmsg" then
      "hyprctl dispatch layoutmsg ${action.message}"
    else
      "true";

  mkBindHint =
    entry:
    let
      bind = entry.hyprBind or null;
      shown = printHyprKey entry;

      # The hint FORMAT is module-controlled and may contain markup, so it is
      # not escaped. The substituted key names come from user config and are.
      hint =
        if shown == null then
          ""
        else
          lib.replaceStrings [ "{keys}" ] [ (pangoEscape shown) ] cfg.settings.hyprKeyDescFormat;

      want =
        if bind == null then
          false
        else if (bind ? showHint) && bind.showHint != null then
          bind.showHint
        else
          true;
    in
    if want && shown != null then hint else "";

  mkMenuEntry = entry: {
    key = entry.menuKey;
    desc = pangoEscape entry.desc + (if cfg.settings.showHyprKeyInDesc then mkBindHint entry else "");
    cmd =
      if entry.cmd != null then
        entry.cmd
      else if entry.hyprBind != null then
        mkHyprCmd entry
      else
        "true";
  };

  expandFromGroupNode =
    seenPath: entry:
    let
      grp = entry.fromGroup;
      nextSeen = seenPath ++ [ grp ];

      group =
        cfg.settings.menu.groups.${grp}
          or (throw "nixSpace.hyprland.hyprWhichKey: fromGroup references unknown group '${grp}'");

      submenu = submenuForGroup seenPath grp;
    in
    assert lib.assertMsg (!(lib.elem grp seenPath))
      "nixSpace.hyprland.hyprWhichKey: infinite menu recursion while expanding fromGroup: ${lib.concatStringsSep " -> " nextSeen}";
    assert lib.assertMsg (submenu != [ ]) ''
      nixSpace.hyprland.hyprWhichKey: group '${grp}' expands to an empty submenu.

      Fix one of:
        - define settings.menu.entries.${grp} = [ ... ];
        - define settings.menu.groups.${grp}.submenu = [ ... ];
        - remove '${grp}' from any fromGroup reference.
    '';
    (removeAttrs entry [ "fromGroup" ])
    // {
      key = entry.key or (group.key or grp);
      desc = entry.desc or (group.desc or grp);
      inherit submenu;
    };

  expandMenuEntries =
    seenPath: entry:
    let
      withChildren =
        if entry ? submenu then
          entry // { submenu = map (expandMenuEntries seenPath) entry.submenu; }
        else
          entry;
    in
    if withChildren ? fromGroup then expandFromGroupNode seenPath withChildren else withChildren;

  expandMenuEntry = entry: expandMenuEntries [ ] entry;

  # Submenu for a group: groups.<grp>.submenu if set, else entries.<grp>.
  submenuForGroup =
    seenPath: grp:
    let
      group = cfg.settings.menu.groups.${grp} or { };
      sub = group.submenu or null;
      entries = cfg.settings.menu.entries.${grp} or [ ];
    in
    if sub != null then
      map (entry: expandMenuEntries (seenPath ++ [ grp ]) (validateSubmenuEntry entry)) sub
    else
      map mkMenuEntry entries;

  validateEntry =
    entry:
    let
      err =
        msg: throw "nixSpace.hyprland.hyprWhichKey: invalid entry (${entry.desc or "<no desc>"}): ${msg}";
      hb = entry.hyprBind or null;
      action = if hb == null then { type = "nop"; } else hb.action;
    in
    if !(entry ? menuKey) then
      err "missing menuKey"
    else if !(entry ? desc) then
      err "missing desc"
    else if hb != null && !(hb ? key) then
      err "hyprBind.key missing"
    # action.cmd / dispatch / message are options with default = null, so
    # `action ? attr` is always true. Check the value.
    else if action.type == "exec" && action.cmd == null then
      err "hyprBind.action.type=exec requires cmd"
    else if action.type == "dispatch" && action.dispatch == null then
      err "hyprBind.action.type=dispatch requires dispatch"
    else if action.type == "layoutmsg" && action.message == null then
      err "hyprBind.action.type=layoutmsg requires message"
    else if action.type == "luaDispatch" && action.lua == null then
      err "hyprBind.action.type=luaDispatch requires lua"
    else
      entry;

  validateSubmenuEntry =
    entry:
    let
      allowed = [
        "key"
        "desc"
        "cmd"
        "keepOpen"
        "fromGroup"
        "submenu"
      ];
      unknown = lib.filter (k: !(lib.elem k allowed)) (builtins.attrNames entry);

      hasCmd = (entry.cmd or null) != null;
      hasSub = (entry.submenu or null) != null;
      hasFrom = (entry.fromGroup or null) != null;
      n = (if hasCmd then 1 else 0) + (if hasSub then 1 else 0) + (if hasFrom then 1 else 0);
      requireKeyDesc = (hasCmd || hasSub) && !hasFrom;
      recurse = if hasSub then map validateSubmenuEntry entry.submenu else entry.submenu or null;
    in
    if unknown != [ ] then
      throw "nixSpace.hyprland.hyprWhichKey: submenu entry has unknown keys: ${lib.concatStringsSep ", " unknown}"
    else if n > 1 then
      throw "nixSpace.hyprland.hyprWhichKey: submenu entry must set at most one of cmd, submenu, or fromGroup"
    else if requireKeyDesc && ((entry.key or null) == null || (entry.desc or null) == null) then
      throw "nixSpace.hyprland.hyprWhichKey: submenu entry with cmd/submenu must provide key and desc (unless using fromGroup)"
    else
      entry // (if hasSub then { submenu = recurse; } else { });

  # ---- Lua --------------------------------------------------------------

  # $ is a hyprlang sigil, not part of the name, and not legal in a Lua
  # identifier.
  stripSigil = name: lib.removePrefix "$" name;

  # keyVars -> Lua locals: { "$mainMod" = "SUPER"; } becomes
  # { mainMod = { _var = "SUPER"; }; }, rendered as `local mainMod = "SUPER"`.
  luaKeyVars = lib.mapAttrs' (
    name: value: lib.nameValuePair (stripSigil name) { _var = value; }
  ) cfg.hypr.keyVars;

  # Mods stay Lua variables rather than being flattened at eval time, so
  # changing keyVars still changes every bind.
  #
  # NOTE the separator: hyprlang2lua emits `mainMod .. shiftMod .. " + F"`,
  # which concatenates to "SUPERSHIFT + F" — every multi-modifier bind in its
  # output is broken that way. " + " must appear between mods as well.
  luaComboExpr =
    bind:
    let
      modTerm = mod: if cfg.hypr.keyVars ? ${mod} then stripSigil mod else ''"${stripSigil mod}"'';
      terms = (map modTerm (bind.mods or [ ])) ++ [ ''"${bind.key}"'' ];
    in
    lib.generators.mkLuaInline (lib.concatStringsSep " .. \" + \" .. " terms);

  directionNames = {
    l = "left";
    r = "right";
    u = "up";
    d = "down";
  };

  # Numeric workspace ids are Lua numbers; relative ("e+1") and special
  # ("special:magic") are strings. A quoted "1" is not equivalent.
  wsArg = arg: if builtins.match "[0-9]+" arg != null then arg else ''"${arg}"'';

  dispatchMap = {
    killactive = _: "hl.dsp.window.close()";
    togglefloating = _: ''hl.dsp.window.float({ action = "toggle" })'';
    pseudo = _: "hl.dsp.window.pseudo()";
    submap = arg: ''hl.dsp.submap("${arg}")'';
    exit = _: "hl.dsp.exit()";

    fullscreen =
      arg:
      let
        mode = if arg == "1" then "maximized" else "fullscreen";
      in
      ''hl.dsp.window.fullscreen({ mode = "${mode}", action = "toggle" })'';

    # focus takes spelled-out directions while window.move takes single
    # letters.
    movefocus = arg: ''hl.dsp.focus({ direction = "${directionNames.${arg} or arg}" })'';
    movewindow = arg: ''hl.dsp.window.move({ direction = "${arg}" })'';

    workspace = arg: "hl.dsp.focus({ workspace = ${wsArg arg} })";
    movetoworkspace = arg: "hl.dsp.window.move({ workspace = ${wsArg arg} })";
    togglespecialworkspace = arg: ''hl.dsp.workspace.toggle_special("${arg}")'';
  };

  luaAction =
    action:
    if action.type == "exec" then
      ''hl.dsp.exec_cmd("${lib.escape [ ''"'' "\\" ] action.cmd}")''
    else if action.type == "luaDispatch" then
      action.lua
    else if action.type == "layoutmsg" then
      ''hl.dsp.layout("${action.message}")''
    else if action.type == "dispatch" then
      let
        fn =
          dispatchMap.${action.dispatch} or (throw ''
            nixSpace.hyprland.hyprWhichKey: no Lua mapping for dispatcher '${action.dispatch}'.

            hl.dsp is a structured namespace, not a rename of the hyprlang
            dispatchers, so each needs an explicit mapping.

            Fix one of:
              - run the hyprlang line through hyprlang2lua and add the result
                to dispatchMap in generate.nix, or
              - supply the call directly with action.type = "luaDispatch".
          '');
      in
      fn action.arg
    else
      null;

  # ---- binds ------------------------------------------------------------

  mkHyprBind =
    entry:
    let
      bind = entry.hyprBind or null;
      action = if bind == null then { type = "nop"; } else (bind.action or { type = "nop"; });
    in
    if bind == null || action.type == "nop" then
      null
    else if luaMode then
      let
        call = luaAction action;
      in
      if call == null then
        null
      else
        {
          _args = [
            (luaComboExpr bind)
            (lib.generators.mkLuaInline call)
          ];
        }
    else
      let
        modsStr = lib.concatStringsSep " " (bind.mods or [ ]);
        prefix = if modsStr == "" then ", ${bind.key}" else "${modsStr}, ${bind.key}";
      in
      if action.type == "dispatch" then
        "${prefix}, ${action.dispatch}" + lib.optionalString (action.arg != null) ", ${action.arg}"
      else if action.type == "layoutmsg" then
        "${prefix}, layoutmsg, ${action.message}"
      else if action.type == "exec" then
        "${prefix}, exec, ${action.cmd}"
      else if action.type == "luaDispatch" then
        throw ''
          nixSpace.hyprland.hyprWhichKey: action.type = "luaDispatch" requires
          configType = "lua". Entry: ${entry.desc or "<no desc>"}
        ''
      else
        null;

  # Display text for bind hints. Independent of config language, but the
  # lookup handles both spellings since Lua keyVars carry no sigil.
  printHyprMod =
    mod:
    let
      modLookup = cfg.hypr.keyVars.${mod} or cfg.hypr.keyVars."$${mod}" or (stripSigil mod);
    in
    cfg.hypr.printMods.${modLookup} or modLookup;

  printHyprKey =
    entry:
    let
      bind = entry.hyprBind or null;
    in
    if bind == null then
      null
    else
      lib.concatStringsSep "+" ((map printHyprMod (bind.mods or [ ])) ++ [ bind.key ]);

  # Built the same way as any other bind so it is correct under both
  # languages.
  leaderBind =
    if luaMode then
      {
        _args = [
          (luaComboExpr {
            mods = cfg.settings.leaderMods;
            key = cfg.settings.leaderKey;
          })
          (lib.generators.mkLuaInline ''hl.dsp.exec_cmd("${lib.getExe hyprWkToggle}")'')
        ];
      }
    else
      let
        modsStr = lib.concatStringsSep " " cfg.settings.leaderMods;
        prefix =
          if modsStr == "" then ", ${cfg.settings.leaderKey}" else "${modsStr}, ${cfg.settings.leaderKey}";
      in
      "${prefix}, exec, ${lib.getExe hyprWkToggle}";

  # ---- assembly ---------------------------------------------------------

  allEntries = concatLists (builtins.attrValues cfg.settings.menu.entries);
  validatedEntries = map validateEntry allEntries;
  bindEntries = lib.filter (entry: entry.hyprBind != null) validatedEntries;
  generatedBinds = lib.filter (bind: bind != null) (map mkHyprBind bindEntries);
  finalMenu = map (grp: expandMenuEntry { fromGroup = grp; }) cfg.settings.menu.root;

  yamlText = mkWkCfg {
    inherit (cfg.settings) style inhibit_compositor_keyboard_shortcuts auto_kbd_layout;
    menu = finalMenu;
  };
in
{
  inherit
    luaMode
    luaKeyVars
    yamlText
    generatedBinds
    leaderBind
    mkHyprBind
    printHyprKey
    allEntries
    ;
}
