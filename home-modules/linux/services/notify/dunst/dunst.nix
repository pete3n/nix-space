# dunst notification module.
#
# Applies opinionated default styling and messaging settings.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nixSpace.services.dunst;

  # Opinionated baseline. Merged with `cfg.settings` taking precedence: see
  # the note on recursiveUpdate in the config block below.
  defaultSettings = {
    global = {
      corner_radius = 10;
      frame_width = 2;
      background = "#1f2335";
      foreground = "#c0caf5";
      frame_color = "#7aa2f7";
      separator_color = "frame";
      font = "monospace 10";

      # Without a cap, a misbehaving app can paper over the whole output.
      notification_limit = 5;

      # Hold notifications that arrive while away rather than expiring them
      # against an absent user. 120s of no input counts as idle.
      idle_threshold = 120;
    };

    urgency_critical = {
      # Critical notifications should require dismissal, not time out.
      timeout = 0;
    };
  };
in
{
  options.nixSpace.services.dunst = {
    enable = lib.mkEnableOption "the dunst notification daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.dunst;
      defaultText = lib.literalExpression "pkgs.dunst";
      description = "The dunst package to run.";
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      example = lib.literalExpression ''
        {
          global.font = "JetBrainsMono Nerd Font 11";
          urgency_low.timeout = 3;
        }
      '';
      description = ''
        dunst configuration, merged section-by-section over the module's
        defaults so a host can override a single key without restating the
        section it lives in.

        Section names other than `global`, `experimental`, and
        `urgency_low`/`urgency_normal`/`urgency_critical` are treated by dunst
        as matching rules. See the caveat on rule ordering in the module
        source before relying on more than one rule.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(config.services.mako.enable or false);
        message = ''
          nixSpace.services.dunst and services.mako are both enabled. Only one
          notification daemon can own the org.freedesktop.Notifications D-Bus
          name; the loser fails to start, and which one loses depends on
          activation order rather than anything declared.
        '';
      }
      {
        assertion = !(config.services.swaync.enable or false);
        message = ''
          nixSpace.services.dunst and services.swaync are both enabled. Only
          one notification daemon can own the org.freedesktop.Notifications
          D-Bus name.
        '';
      }
    ];

    services.dunst = {
      enable = true;
      inherit (cfg) package;
      settings = lib.recursiveUpdate defaultSettings cfg.settings;
    };

    home.packages = [ pkgs.libnotify ];
  };
}
