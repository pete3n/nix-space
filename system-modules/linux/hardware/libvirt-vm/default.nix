# libvirt/QEMU-KVM virtio guest chassis.
#
# The hardware a NixOS guest sees under libvirt with a q35 + UEFI (OVMF)
# machine and virtio devices: virtio disk/net/scsi controllers, the guest
# agent the host talks to, and a serial console so `virsh console` works on a
# box with no display.
#
# SELF-GATED, unlike the framework16 chassis module beside it: this config is
# only correct inside a VM (a serial console and qemuGuest on a bare-metal
# laptop would be wrong), so it applies only when the host declares this
# chassis. It is still imported on every host via the hardware directory hook;
# it simply does nothing off-VM.
#
# SCOPE: generic to any libvirt virtio guest. Per-guest specifics — the disk
# layout, filesystems, boot device — live in that host's
# hardware-configuration.nix, not here.
{
  config,
  lib,
  nixSpaceAttrs,
  ...
}:
let
  isThisChassis = nixSpaceAttrs.chassis == "libvirt-vm";
in
{
  config = lib.mkIf isThisChassis {
    boot = {
      initrd.availableKernelModules = [
        "virtio_pci"
        "virtio_blk"
        "virtio_scsi"
        "virtio_net"
        "sr_mod" # virtual CD-ROM, used at install
        "sd_mod"
      ];

      # UEFI guest (OVMF). systemd-boot rather than GRUB — nothing here needs
      # GRUB, and it matches the workstation hosts.
      loader.systemd-boot.enable = lib.mkDefault true;
      loader.efi.canTouchEfiVariables = lib.mkDefault true;

      # A headless guest has no screen. Keep tty0 for a graphical console if
      # one is ever attached, but put the kernel console on the serial port so
      # `virsh console idm1` shows boot and login.
      kernelParams = [
        "console=tty0"
        "console=ttyS0,115200"
      ];
    };

    # Lets the host query IP/hostname, quiesce filesystems for snapshots, and
    # shut the guest down cleanly.
    services.qemuGuest.enable = true;
  };
}
