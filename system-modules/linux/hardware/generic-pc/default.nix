# Generic PC chassis.
#
# Fallback when no dedicated chassis module exists. Enough to boot and be
# useful; nothing that assumes particular hardware.
#
# This is what keeps `chassis` a required field. Without it, a user with an
# unsupported machine would need the requirement relaxed, and "unset" would
# become a silent third state alongside "declared" and "invalid".
#
# SCOPE: if something here turns out to be wrong on some machine, it does not
# belong in this file. Add a chassis entry for that machine instead.
{ lib, ... }:
{
  # Firmware for common wireless, graphics, and storage controllers. Broad by
  # design — the point of this chassis is that we do not know what is present.
  hardware.enableRedistributableFirmware = lib.mkDefault true;

  # Microcode for whichever CPU is present. Both are enabled because the
  # vendor is unknown; each is a no-op on the other vendor's hardware.
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;

  # Firmware updates via LVFS. Safe default; a machine with no supported
  # devices simply has nothing to offer.
  services.fwupd.enable = lib.mkDefault true;

  # TODO: consider whether nixos-hardware's common-* profiles belong here, or
  # whether pulling that input in is better left to real chassis modules.
}
