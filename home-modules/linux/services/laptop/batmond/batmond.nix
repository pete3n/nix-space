# battery monitoring systemd user daemon module.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;

  cfg = config.nixSpace.services.batmond;

  batmond = pkgs.writeShellApplication {
    name = "batmond";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      systemd
    ];

    text = # sh
    ''
      BATTERY_DEVICE="${cfg.batteryDevice}"
      GUI_NOTIFY_CMD="${toString cfg.guiNotifyCmd}"
      HIBERNATE_GUI_MSG=${lib.escapeShellArg cfg.hibernateGuiMsg}
      HIBERNATE_PERCENT="${toString cfg.hibernatePercent}"
      HIBERNATE_SUB_CMD="${toString cfg.hibernateSubCmd}"
      HIBERNATE_TTY_MSG="${cfg.hibernateTtyMsg}"
      LOG_EVENTS="${lib.boolToString cfg.logEvents}"
      RUNTIME_SHELL="${pkgs.runtimeShell}"
      SHUTDOWN_GUI_MSG="${cfg.shutdownGuiMsg}"
      SHUTDOWN_PERCENT="${toString cfg.shutdownPercent}"
      SHUTDOWN_SUB_CMD="${toString cfg.shutdownSubCmd}"
      SHUTDOWN_TTY_MSG="${cfg.shutdownTtyMsg}"
      STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/batmond"
      STATE_FILE="''${STATE_DIR}/bat_last_cap"
      SUSPEND_GUI_MSG="${cfg.suspendGuiMsg}"
      SUSPEND_PERCENT="${toString cfg.suspendPercent}"
      SUSPEND_SUB_CMD="${toString cfg.suspendSubCmd}"
      SUSPEND_TTY_MSG="${cfg.suspendTtyMsg}"
      TTY_NOTIFY_CMD="${toString cfg.ttyNotifyCmd}"
      WARN_BELOW_GUI_MSG="${cfg.warnBelowGuiMsg}"
      WARN_BELOW_PERCENT="${toString cfg.warnBelowPercent}"
      WARN_BELOW_TTY_MSG="${cfg.warnBelowTtyMsg}"
    ''
    + builtins.readFile ./batmond.sh;
  };
in
{
  options.nixSpace.services.batmond = {
    enable = mkEnableOption "Battery monitoring service with warning + suspend/hibernate/shutdown actions";

    logEvents = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to log events with logger -t batmond

        Default: true
      '';
    };

    guiNotifyCmd = mkOption {
      type = types.str;
      default = "${pkgs.libnotify}/bin/notify-send -u critical";
      description = ''
        Command used for GUI notifications.
        It will be executed as:
        $GUI_NOTIFY_CMD "Battery %" "$notifyMsg"

        Default: '${pkgs.libnotify}/bin/notify-send -u critical'
      '';
    };

    ttyNotifyCmd = mkOption {
      type = types.str;
      default = "${pkgs.util-linux}/bin/wall -n";
      description = ''
        Command used for non-GUI notifications.
        Message will be passed on stdin.
        Set to ':' to disable.

        Default: '${pkgs.util-linux}/bin/wall -n'
      '';
    };

    warnBelowPercent = mkOption {
      type = types.ints.between 0 100;
      default = 15;
      description = ''
        Battery percentage below continuous warnings are given.
        Set to 0 to disable repeat warnings. 

        Default: 15
      '';
    };

    warnBelowGuiMsg = mkOption {
      type = types.str;
      default = "🪫‼️ Warning battery is running low!";
      description = ''
        Notification message to display for repeated battery warnings in a graphical environment 
        when the battery is below the warnBelowPercent level.

        Default: '🪫‼️ Warning battery is running low!'
      '';
    };

    warnBelowTtyMsg = mkOption {
      type = types.str;
      default = "!! Warning battery is running low!";
      description = ''
        Notification message to display for repeated battery warnings in a TTY environemnt 
        when the battery is below the warnBelowPercent level.

        Default: 'Battery low. Suspending system...'
      '';
    };

    suspendPercent = mkOption {
      type = types.ints.between 0 100;
      default = 10;
      description = ''
        Battery percentage at or below which the system will suspend.
        Triggers once per discharge cycle when crossing this threshold.
        Set to 0 to disable suspend. 

        Default: 10
      '';
    };

    suspendSubCmd = mkOption {
      type = types.enum [
        "suspend"
        "hibernate"
        "hybrid-sleep"
        "suspend-then-hibernate"
      ];
      default = "suspend";
      description = ''
        systemctl sub-command to execute when suspendPercent is triggered.
        Must be one of: suspend hibernate hybrid-sleep suspend-then-hibernate

        Default: suspend
      '';
    };

    suspendTtyMsg = mkOption {
      type = types.str;
      default = "Battery low. Suspending system...";
      description = ''
        Notification shown when suspending system in a TTY environment.

        Default: 'Battery low. Suspending system...'
      '';
    };

    suspendGuiMsg = mkOption {
      type = types.str;
      default = "🪫‼️ Battery low. 🌙 Suspending system...";
      description = ''
        Notification shown when suspending system in a graphical environment.

        Default: '🪫‼️ Battery low. 🌙 Suspending system...'
      '';
    };

    hibernatePercent = mkOption {
      type = types.ints.between 0 100;
      default = 0;
      description = ''
        Battery percentage at or below which the system will hibernate.
        Triggers once per discharge cycle when crossing this threshold.
        Set to 0 to disable hibernate.
        NOTE: You must have swap+resume correctly configured for this to function.

        Default: 0
      '';
    };

    hibernateSubCmd = mkOption {
      type = types.enum [
        "suspend"
        "hibernate"
        "hybrid-sleep"
        "suspend-then-hibernate"
      ];
      default = "hibernate";
      description = ''
        systemctl sub-command to execute when hibernatePercent is triggered.
        Must be one of: suspend hibernate hybrid-sleep suspend-then-hibernate

        Default: hibernate
      '';
    };

    hibernateTtyMsg = mkOption {
      type = types.str;
      default = "Battery severely low. Hibernating system...";
      description = ''
        Notification shown when hibernating system in a TTY environment.

        Default: 'Battery severely low. Hibernating system...'
      '';
    };

    hibernateGuiMsg = mkOption {
      type = types.str;
      default = "🪫‼️ Battery severely low.  Hibernating system...";
      description = ''
        Notification shown when hibernating system in a graphical environment.

        Default: '🪫‼️ Battery severely low.  Hibernating system...'
      '';
    };

    shutdownPercent = mkOption {
      type = types.ints.between 0 100;
      default = 1;
      description = ''
        Battery percentage at which the system will shutdown.
        Triggers once per discharge cycle when crossing this threshold.
        Set to 0 to disable shutdown. 

        Default: 1
      '';
    };

    shutdownSubCmd = mkOption {
      type = types.enum [
        "suspend"
        "hibernate"
        "hybrid-sleep"
        "suspend-then-hibernate"
        "poweroff"
      ];
      default = "poweroff";
      description = ''
        systemctl sub-command to execute when shutdownPercent is triggered.
        Must be one of: suspend hibernate hybrid-sleep suspend-then-hibernate poweroff

        Default: poweroff
      '';
    };

    shutdownGuiMsg = mkOption {
      type = types.str;
      default = "🪫‼️ Battery critically low. ⏻ Shutting down...";
      description = ''
        Notification shown when shutting down the system in a graphical environment.

        Default: '🪫‼️ Battery critically low. ⏻ Shutting down...'
      '';
    };

    shutdownTtyMsg = mkOption {
      type = types.str;
      default = "Battery critically low. Shutting down system...";
      description = ''
        Notification shown when shutting down the system in a TTY environment.

        Default: 'Battery critically low. Shutting down system...'
      '';
    };

    batteryDevice = mkOption {
      type = types.str;
      default = "";
      example = "BAT1";
      description = ''
        Battery to monitor, as named under /sys/class/power_supply.

        Empty picks the first device whose type is Battery.
      '';
    };

    batteryInterval = mkOption {
      type = types.ints.positive;
      default = 30;
      description = "How often (in seconds) to check the battery bat_status.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      batmond
    ];

    systemd.user.services."batmond" = {
      Unit = {
        Description = "Battery level warning notifications and actions daemon";
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${batmond}/bin/batmond";
      };
    };

    systemd.user.timers."batmond" = {
      Unit = {
        Description = "Periodic battery level check";
      };

      Timer = {
        OnStartupSec = "1min";
        OnUnitActiveSec = "${toString cfg.batteryInterval}s";
        AccuracySec = "10s";

        # NOTE: Persistent has deliberately NOT been set. It only applies
        # to OnCalendar timers — on an OnUnitActiveSec timer it is inert,
        # and setting it implies a catch-up behaviour that does not exist.
      };

      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
