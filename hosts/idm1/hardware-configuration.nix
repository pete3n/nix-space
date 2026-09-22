# idm1 — per-guest disk layout for the libvirt/QEMU-KVM guest.
#
# The generic virtio/guest bits (virtio kernel modules, serial console,
# qemuGuest) come from the libvirt-vm chassis module. This file carries only
# what is specific to THIS guest's disk, and it must match the qcow2 image
# built for the domain.
#
# Devices are by-label, not by-uuid: the image is built fresh (no UUIDs to
# know in advance), so the builder labels the root filesystem `nixos` and the
# EFI system partition `ESP`. Keep these labels in step with the image build.
{
  config,
  lib,
  ...
}:
{
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };
  };

  swapDevices = [ ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
