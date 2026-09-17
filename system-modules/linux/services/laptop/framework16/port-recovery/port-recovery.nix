# Workaround for USB-C source ports dropping VBUS on the Framework Laptop 16
# The CCG8 PD controllers latch a port's source path off after repeated VBUS faults
# (observed under load transients: app launches, resume from sleep; both ports of a
# controller drop together). CC stays attached, so nothing upstream logs anything,
# and the OS only sees the powered device disappear. Cycling the owning controller 
# with framework_tool emulates the physical reseat that clears the latch.
#
# Every USB device removal is checked. The device is traced back to a Type-C port 
# (firmware `connector` links first, then the slot map). If a card is still 
# attached to that port after the grace period, the owning PD controller is
# cycled. Internal devices and unmapped slots resolve to nothing and are ignored.
#
# Set `mainboard` to select a built-in slot map. Verify on each machine with
# `dryRun = true` before enabling actions. Requires a working EC interface for
# framework_tool (`framework_tool --pd-info` must list the CCG8 controllers).
# See: https://community.frame.work/t/framework-16-ports-randomly-not-working/79206
{
  config,
  lib,
  pkgs,
  ...
}:

# Timings, from the observed failure sequence:
#   - CCG8 retries bring the device back within ~1 s; only the final (latched) drop
#     never returns. graceSeconds separates a retry from a latch.
#   - Type-C detach debounce (tCCDebounce) is 100–200 ms; cycleGapSeconds keeps the
#     controller disabled long enough for the card to register a detach.
#   - A cycle drops every device on that controller; their remove events must not
#     cascade into further cycles. cooldownSeconds is per controller.
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkPackageOption
    mkIf
    types
    ;

  cfg = config.nixSpace.services.fw16PortRecovery;

  # Per-mainboard tables. Slot keys are "<xHCI PCI device ID>/<port path>"; the IDs
  # are defined by the SoC, so a table holds for every board built on it regardless
  # of USB bus numbering. PD controllers are indexed in `framework_tool --pd-info`
  # order. Slots without a PD controller (no Type-C partner ever appears) are
  # intentionally absent: there is nothing to cycle for them.
  mainboards = {
    # AMD Ryzen AI 300 series (Strix Point). Measured on BIOS 04.01, all four PD slots
    # confirmed with devices.
    # xHCIs: 151f = main controller; 151a / 151b = USB4-paired controllers with one
    #        root port each. A USB 3 hub presents the same port numbers on its USB 2
    #        and USB 3 sides, and this board's root ports pair 1:1, so one key covers
    #        USB 2 and USB 3 devices alike in every slot.
    # 151f root port 2 is a Realtek RTS5432 combo hub (0bda:5432 / 0bda:0432) serving
    # expansion slots: hub port 1 = right front, 2 = right middle, 3 = left front.
    # 151f root port 1 is the left middle slot directly; root ports 3 and 4 are the
    # input-deck hubs (05e3:0610); 151e is the camera controller.
    # PD controllers: 0 = Right / Ports 01, 1 = Left / Ports 23, 2 = graphics module.
    # Front slots (151f/2.1, 151f/2.3) have no PD controller and are absent by design.
    AI_300 = {
      controllerForTypecPort = {
        "0" = 0;
        "1" = 0;
        "2" = 1;
        "3" = 1;
        "4" = 2;
      };
      slots = [
        # right back: USB4 slot
        {
          typecPort = 0;
          usbPorts = [ "151a/1" ];
        }
        # right middle: combo hub port 2
        {
          typecPort = 1;
          usbPorts = [ "151f/2.2" ];
        }
        # left middle: root port 1 (3-1 on the USB 2 side, 4-1 on the USB 3 side)
        {
          typecPort = 2;
          usbPorts = [ "151f/1" ];
        }
        # left back: USB4 slot
        {
          typecPort = 3;
          usbPorts = [ "151b/1" ];
        }
      ];
    };
  };
  board = if cfg.mainboard == null then null else mainboards.${cfg.mainboard};

  # The slot list flattened into one lookup, slot key -> Type-C port, handed to the
  # script as a bash associative array. Prefix matching happens at runtime with no
  # defined order, which the assertions below make safe by rejecting nested keys.
  slotKeys = lib.concatMap (slot: slot.usbPorts) cfg.slots;
  slotTypecPort = lib.listToAttrs (
    lib.concatMap (
      slot: map (usbPort: lib.nameValuePair usbPort slot.typecPort) slot.usbPorts
    ) cfg.slots
  );

  recover = pkgs.writeShellApplication {
    name = "fw16-pd-port-recovery";
    runtimeInputs = with pkgs; [
      cfg.package
      coreutils
      util-linux
    ];

    text = # sh
    ''
      ${lib.toShellVar "CONTROLLER_FOR_TYPEC_PORT" cfg.controllerForTypecPort}
      COOLDOWN_SECONDS="${toString cfg.cooldownSeconds}"
      CYCLE_GAP_SECONDS="${toString cfg.cycleGapSeconds}"
      DRY_RUN="${lib.boolToString cfg.dryRun}"
      GRACE_SECONDS="${toString cfg.graceSeconds}"
      PD_PARTNER_GRACE_SECONDS="${toString cfg.pdPartnerGraceSeconds}"
      RESET_ON_FAILURE="${lib.boolToString cfg.resetOnFailure}"
      RETRY_GAP_SECONDS="${toString cfg.retryGapSeconds}"
      ${lib.toShellVar "SLOT_TYPEC_PORT" slotTypecPort}
      STATE_DIR="/run/fw16-pd-port-recovery"
      USB_DEVICES_DIR="/sys/bus/usb/devices"
      VERIFY_SECONDS="${toString cfg.verifySeconds}"
    ''
    + builtins.readFile ./port-recovery.sh;
  };
in
{
  options.nixSpace.services.fw16PortRecovery = {
    enable = mkEnableOption "Recover USB-C source ports latched off by the PD controller";

    package = mkPackageOption pkgs "framework-tool" { };

    mainboard = mkOption {
      type = types.nullOr (types.enum (lib.attrNames mainboards));
      default = null;
      example = "AI_300";
      description = ''
        Known mainboard. Selects the built-in `slots` and `controllerForTypecPort`
        tables; either can still be set explicitly to override. Leave null for a
        board without a table and provide `slots` yourself.
      '';
    };

    dryRun = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Log what would be cycled instead of cycling it. Use this to validate a slot
        table on a machine before letting it act.
      '';
    };

    slots = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            typecPort = mkOption {
              type = types.ints.unsigned;
              description = "UCSI Type-C port index (`/sys/class/typec/portN`) of this slot.";
            };
            usbPorts = mkOption {
              type = types.listOf types.str;
              example = [
                "151f/2.2"
                "151f/2.3"
              ];
              description = ''
                Slot keys of the form `<xHCI PCI device ID>/<root port>[.<hub port>...]`
                as printed by `fw16-pd-port-recovery --slot-keys`. USB 2 and USB 3
                devices may take different paths through the same controller; list both.
              '';
            };
          };
        }
      );
      default = if board == null then [ ] else board.slots;
      defaultText = lib.literalMD "the table for `mainboard`, or `[ ]`";
      description = ''
        Slot map. Only consulted when no hub or root port above the removed device
        carries a firmware-provided `connector` link to a Type-C port (none on current
        firmware). Setting this replaces the `mainboard` table entirely.
      '';
    };

    controllerForTypecPort = mkOption {
      type = types.attrsOf (types.ints.between 0 2);
      default =
        if board == null then mainboards.AI_300.controllerForTypecPort else board.controllerForTypecPort;
      defaultText = lib.literalMD "the table for `mainboard`, or the AI_300 layout";
      description = ''
        PD controller owning each UCSI Type-C port, in `framework_tool --pd-info`
        order. Verify once per machine by pulling a card on a known controller and
        noting which `portN-partner` disappears in `udevadm monitor -k -s typec`.
      '';
    };

    graceSeconds = mkOption {
      type = types.numbers.nonnegative;
      default = 2;
      description = ''
        Time to wait after a device disappears before acting. Long enough for a CCG8
        retry to re-enumerate the device on its own.
      '';
    };

    cycleGapSeconds = mkOption {
      type = types.numbers.nonnegative;
      default = 0.5;
      description = "Time to hold the controller disabled between `--pd-disable` and `--pd-enable`.";
    };

    cooldownSeconds = mkOption {
      type = types.ints.unsigned;
      default = 10;
      description = ''
        Minimum interval between cycles of the same controller, as seen by other
        instances. Absorbs the remove events a cycle itself generates on the sibling
        port, and limits a deliberately unplugged device to a single cycle. The
        instance that performs a cycle verifies and retries on its own regardless.
      '';
    };

    pdPartnerGraceSeconds = mkOption {
      type = types.numbers.nonnegative;
      default = 4;
      description = ''
        Additional wait when the slot's partner reports `supports_usb_power_delivery`.
        Such cards have an active CC controller, detach when VBUS drops, and re-attach
        on their own; cycling the controller during that costs more than it saves.
      '';
    };

    verifySeconds = mkOption {
      type = types.ints.positive;
      default = 6;
      description = "How long to wait for the device to re-enumerate after a cycle before retrying.";
    };

    retryGapSeconds = mkOption {
      type = types.numbers.nonnegative;
      default = 2;
      description = "Disable/enable gap for the second attempt, when the first cycle didn't bring the device back.";
    };

    resetOnFailure = mkOption {
      type = types.bool;
      default = false;
      description = ''
        After two failed cycles, reset the PD controller with `framework_tool --pd-reset`.
        Reinitializes the chip, which renegotiates every partner on it including a
        charger. Off by default.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.slots != [ ];
        message = "nixSpace.services.fw16PortRecovery: set `mainboard` to a known board or provide `slots`; with no slot map the service can never act.";
      }
      {
        assertion = lib.length slotKeys == lib.length (lib.unique slotKeys);
        message = "nixSpace.services.fw16PortRecovery: slot keys must be unique across `slots`.";
      }
      {
        assertion = !lib.any (key: lib.any (other: lib.hasPrefix "${other}." key) slotKeys) slotKeys;
        message = "nixSpace.services.fw16PortRecovery: no slot key may lie below another; a hub port already belongs to the slot above it.";
      }
    ];

    # Also provides `fw16-pd-port-recovery --slot-keys` for building a slot table.
    environment.systemPackages = [ recover ];

    # Any usb_device removal is a candidate; the script decides whether it maps to a
    # PD-managed slot. Interfaces (DEVTYPE=usb_interface) are excluded so one device
    # yields one event.
    services.udev.extraRules = ''
      ACTION=="remove", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", RUN+="${config.systemd.package}/bin/systemctl --no-block start fw16-pd-port-recovery@%k.service"
    '';

    # Instantiated by udev with the removed device's kernel name; nothing starts it at boot.
    systemd.services."fw16-pd-port-recovery@" = {
      description = "Recover PD-latched USB-C port after losing %i";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${recover}/bin/fw16-pd-port-recovery %i";
      };
    };
  };
}
