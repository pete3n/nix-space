# Workaround for Framework 16 early wakeup issues from suspend state	
# Disables all wake triggers except the power button
# See: https://community.frame.work/t/guide-framework-laptop-16-suspend-waking-up-early-or-failing-to-suspend-fix/45986/27
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

  cfg = config.nixSpace.services.fw16WakeTriggers;

  disableWakeTriggers = pkgs.writeShellApplication {
    name = "fw16-disable-wake-triggers";
    runtimeInputs = with pkgs; [
      findutils
    ];

    text = # sh
    ''
      DEVICES_DIR="/sys/devices"
      ${lib.toShellVar "KEEP_ENABLED" cfg.keepEnabled}
    ''
    + builtins.readFile ./wake-triggers.sh;
  };
in
{
  options.nixSpace.services.fw16WakeTriggers = {
    enable = mkEnableOption "Disable all wakeup devices except the power button";

    keepEnabled = mkOption {
      type = types.listOf types.str;
      # The power button's path changed in kernel 7.0.5, from
      # LNXSYSTM:00/LNXSYBUS:00/PNP0C0C:00 to platform/PNP0C0C:00. Both are
      # listed so the default holds on either side of that.
      default = [
        "*/platform/PNP0C0C:00/*"
        "*/LNXSYBUS:00/PNP0C0C:00/*"
      ];
      example = [
        "*/platform/PNP0C0C:00/*"
        "*/platform/PNP0C0D:00/*"
      ];
      description = ''
        `find -path` patterns under /sys/devices whose wakeup setting is left
        untouched. Everything else with a power/wakeup attribute is set to
        disabled. The default keeps the ACPI power button (PNP0C0C); the example
        also keeps the lid switch (PNP0C0D).
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.fw16-disable-wake-triggers = {
      description = "Disable wakeup devices except power button.";
      wantedBy = [
        "multi-user.target"
        "sleep.target"
      ];
      before = [ "sleep.target" ];
      after = [ "systemd-udev-settle.service" ];
      wants = [ "systemd-udev-settle.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${disableWakeTriggers}/bin/fw16-disable-wake-triggers";
        RemainAfterExit = false;
      };
    };
  };
}
