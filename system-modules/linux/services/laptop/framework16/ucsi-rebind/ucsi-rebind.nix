# Workaround for `ucsi_acpi USBC000:00: error -ETIMEDOUT: PPM init failed` on Framework Laptop 16
# At boot the EC's UCSI interface can miss the driver's initial reset timeout while it
# is still bringing up the PD controllers. The driver retries on -EPROBE_DEFER but not
# on a timeout, so the whole Type-C class stays absent for the boot: no partners, no
# alt-mode state, no charger details for upower. Rebinding the driver once the EC is
# idle runs the same init again and it succeeds.
# See: https://community.frame.work/t/framework-16-ports-randomly-not-working/79206
#
# The driver's probe returns immediately and does the PPM reset and connector
# enumeration asynchronously, so after a rebind the ports appear a few seconds later
# (settleSeconds). initialDelaySeconds leaves the boot-time attempt enough room to
# finish on its own before we judge it.
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

  cfg = config.nixSpace.services.fw16UcsiRebind;

  rebind = pkgs.writeShellApplication {
    name = "fw16-ucsi-rebind";
    runtimeInputs = with pkgs; [
      coreutils
    ];

    text = # sh
    ''
      ATTEMPTS="${toString cfg.attempts}"
      DEVICE="${cfg.device}"
      DEVICE_PATH="/sys/bus/platform/devices/''${DEVICE}"
      DRIVER_PATH="/sys/bus/platform/drivers/ucsi_acpi"
      INITIAL_DELAY_SECONDS="${toString cfg.initialDelaySeconds}"
      SETTLE_SECONDS="${toString cfg.settleSeconds}"
    ''
    + builtins.readFile ./ucsi-rebind.sh;
  };
in
{
  options.nixSpace.services.fw16UcsiRebind = {
    enable = mkEnableOption "Rebind ucsi_acpi when its PPM init timed out at boot";

    device = mkOption {
      type = types.str;
      default = "USBC000:00";
      description = "ACPI platform device name of the UCSI interface, as it appears in `ucsi_acpi` kernel messages.";
    };

    initialDelaySeconds = mkOption {
      type = types.ints.unsigned;
      default = 20;
      description = ''
        Wait after the unit starts before checking, so the boot-time init attempt has
        finished successfull or timed out, rather than being interrupted mid-way.
      '';
    };

    settleSeconds = mkOption {
      type = types.ints.positive;
      default = 10;
      description = "Wait after a rebind for the asynchronous PPM reset and connector enumeration to complete.";
    };

    attempts = mkOption {
      type = types.ints.positive;
      default = 3;
      description = "Rebind attempts before giving up.";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.fw16-ucsi-rebind = {
      description = "Rebind ucsi_acpi if the Type-C class is missing after boot";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${rebind}/bin/fw16-ucsi-rebind";
      };
    };
  };
}
