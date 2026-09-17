# Only modify this file if you know what you are doing.
# You may make the system unbootable.
# See NixOS hardware project: https://github.com/NixOS/nixos-hardware/tree/master/framework/desktop
{
  config,
  lib,
  ...
}:

{
  boot = {
    initrd = {
      availableKernelModules = [
        "nvme"
        "xhci_pci"
        "thunderbolt"
        "usbhid"
        "usb_storage"
        "sd_mod"
      ];

      luks.devices."luks-c688da58-6308-4c45-93ac-cc25ddca5e10" = {
        device = "/dev/disk/by-uuid/c688da58-6308-4c45-93ac-cc25ddca5e10";
      };

      luks.devices."luks-swap" = {
        device = "/dev/disk/by-uuid/80c7a27c-1dcb-4084-9b52-95ccd2c567be";
      };
    };

    kernelModules = [ "kvm-amd" ];
    extraModulePackages = [ ];
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/e3cba730-cdd9-48d8-bbd9-a5e3866c7216";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/3DB0-66EC";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };
  };

  swapDevices = [
    { device = "/dev/mapper/luks-swap"; }
  ];

  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
