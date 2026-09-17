# Waybar module.
#
# Feature modules contribute widgets rather than this file referencing them.
#
# The Hyprland workspace widget is the one exception: see hyprlandWorkspaces below.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.waybar;

  # `style` and `autoPlace` are NOT waybar options — both are stripped here.
  # Everything else goes verbatim into the JSON, so leaving them in would
  # write unknown keys that waybar ignores silently.
  widgetSettings = lib.mapAttrs (
    _name: w:
    removeAttrs w [
      "style"
      "autoPlace"
    ]
  ) cfg.modules;

  # Widgets asking to place themselves, grouped by side.
  #
  # Defining a widget and putting it on the bar were two separate acts in two
  # separate files, and they came apart four times while this was being
  # written — workspaces, snowflake, wdisplays, backlight all ended up defined
  # and invisible. Nothing errors: waybar happily writes a widget nobody
  # references.
  autoPlaced =
    side: lib.attrNames (lib.filterAttrs (_name: w: (w.autoPlace or null) == side) cfg.modules);

  # Explicit list first, then auto-placed in attribute-name order.
  #
  # Explicit wins on ORDER because a hand-written list is a statement about
  # sequence — the mpd controls only read correctly as prev/track/next. A
  # widget named in both is placed once, so adding it to the list is how you
  # take control of where an auto-placed widget sits.
  placement = side: explicit: explicit ++ lib.subtractLists explicit (autoPlaced side);

  inlineStyles = lib.filterAttrs (_name: css: css != "") (
    lib.mapAttrs (_name: w: w.style or "") cfg.modules
  );

  # Renders one commented CSS block per widget, in attribute-name order.
  # mapAttrsToList sorts by name, which is what makes the output stable
  # across rebuilds — types.lines would join in definition order, i.e.
  # module-import order, which is effectively arbitrary.
  renderStyles =
    label: attrs: lib.mapAttrsToList (name: css: "/* " + label + ": " + name + " */\n" + css) attrs;

in
{
  options.nixSpace.waybar = {
    enable = lib.mkEnableOption "Waybar status bar";

    position = lib.mkOption {
      type = lib.types.enum [
        "top"
        "bottom"
        "left"
        "right"
      ];
      default = "top";
      description = "Bar edge.";
    };

    height = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = ''
        Bar height in pixels.

        Popup modules that position themselves below the bar need this value;
        read it rather than hardcoding, or a height change silently leaves
        popups overlapping.
      '';
    };

    modules = lib.mkOption {
      # attrsOf attrsOf, so the module system merges PER KEY rather than
      # per widget. Two features can then contribute different fields to the
      # same widget without either knowing the other exists — the clock is
      # defined by the pomodoro module while the calendar attaches its own
      # on-click, and neither imports the other.
      #
      # Two modules writing the SAME field of the same widget is a genuine
      # conflict and the module system reports it, rather than one silently
      # winning as it would with //.
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      example = lib.literalExpression ''
        {
          "custom/calendar" = {
            format = "";
            on-click = "calendar-toggle";
          };
        }
      '';
      description = ''
        Widget definitions, keyed by waybar module name.

        A `style` key is special: it is stripped before the config is written
        and folded into the stylesheet instead, so a widget can carry its own
        CSS rather than declaring it in a parallel attrset. Everything else is
        passed to waybar verbatim.

        Feature modules write here rather than this file importing them. A
        widget definition alone does not place it on the bar — add the same
        key to modulesLeft, modulesCenter, or modulesRight.
      '';
    };

    modulesLeft = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Module names on the left, in order.";
    };

    modulesCenter = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Module names in the centre, in order.";
    };

    modulesRight = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Module names on the right, in order.";
    };

    hyprlandWorkspaces = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Include the hyprland/workspaces widget.

        Set from the hyprland tag in the register rather than declared per
        host. It is the one compositor-specific thing in this file, kept here
        because a workspace indicator is core bar functionality rather than a
        desktop-environment extra.

        KNOWN BROKEN UPSTREAM: clicking a workspace number does not switch to
        it under a Lua Hyprland config. Waybar's internal click handler issues
        a legacy dispatcher call, and an explicit on-click does not override
        it — so there is no configuration fix. Keyboard binds are unaffected.
      '';
    };

    baseStyle = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        CSS applied before any per-widget rules.

        Global defaults — fonts, the bar background, hover behaviour. Anything
        naming a specific widget belongs in moduleStyles instead, so it
        travels with the module that defines that widget.
      '';
    };

    moduleStyles = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = { };
      description = ''
        CSS per widget, keyed by the SAME name used in `modules`.

        Keyed rather than folded into one block for two reasons.

        ORDER. types.lines joins definitions in definition order, which is
        module-import order and effectively arbitrary — two modules emitting
        rules for the same selector would win unpredictably between rebuilds.
        Keying sorts by widget name, which is stable.

        OVERRIDE. A user replaces one widget's styling by assigning to its
        key, without restating the rest. Everything sharing a single lines
        option can only be appended to.

        Note the KEY is the waybar module name ("custom/snowflake") while the
        CSS SELECTOR is waybar's rendering of it ("#custom-snowflake") — the
        slash becomes a hyphen.
      '';
    };

    style = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        CSS appended after everything else.

        Last, so it wins by cascade over both baseStyle and moduleStyles —
        the override hook for adjusting the bundled look rather than
        replacing it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.waybar = {
      enable = true;
      systemd.enable = true;

      settings.mainBar = {
        layer = "top";
        position = cfg.position;
        height = cfg.height;

        # NOT prepended. hyprlandWorkspaces decides whether the widget is
        # DEFINED; where it sits is placement, and mixing the two meant the
        # flag silently forced it leftmost — so anything a bundle added to
        # modulesLeft landed to its right with no way to get in front.
        modules-left = placement "left" cfg.modulesLeft;
        modules-center = placement "center" cfg.modulesCenter;
        modules-right = placement "right" cfg.modulesRight;
      }
      // widgetSettings;

      # NOTE on the // above: cfg.modules has ALREADY been merged per key by the
      # module system, so this only splices the finished widget set into the bar
      # config. The per-key merging happens at the option, not here.

      # Four tiers, later winning by CSS source order:
      #
      #   baseStyle     global defaults
      #   inline        a widget's own `style`, from whichever module defines it
      #   moduleStyles  styling for a widget defined ELSEWHERE, or an override
      #                 of an inline block
      #   style         the user's last word
      #
      # inline before moduleStyles is what makes the override direction work:
      # a widget carries its own look, and anyone can adjust it by key without
      # editing the module that defined it.
      style = lib.concatStringsSep "\n" (
        lib.filter (block: block != "") (
          [ cfg.baseStyle ]
          ++ renderStyles "widget" inlineStyles
          ++ renderStyles "override" cfg.moduleStyles
          ++ [ cfg.style ]
        )
      );
    };

    # Waybar queries the desktop portal for the appearance setting at startup.
    # Without ordering it can beat the portal and block on D-Bus activation for
    # 25 seconds before dying — systemd restarts it and the second attempt
    # succeeds, which presents as the bar appearing late rather than never.
    systemd.user.services.waybar.Unit = {
      After = [ "xdg-desktop-portal.service" ];
      Wants = [ "xdg-desktop-portal.service" ];
    };
  };
}
