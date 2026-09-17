# Only modify this file if you know what you are doing.
# You may make the system unbootable.
# See NixOS hardware project: https://github.com/NixOS/nixos-hardware/tree/master/framework/16-inch
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
      luks.devices."luks-85cc3034-424b-4127-8826-f3b80c91b37a".device =
        "/dev/disk/by-uuid/85cc3034-424b-4127-8826-f3b80c91b37a";
      luks.devices."swap".device = "/dev/disk/by-uuid/c32a846a-5ddd-4f52-8353-7d32ff827468";
    };

    kernelModules = [ "kvm-amd" ];
    # Workaround for suspend then sleep issues.
    # Resolved nvme drive sleep issues.
    kernelParams = [
      "rtc_cmos.use_acpi_alarm=1"
      "nvme_core.default_ps_max_latency_us=1000"
    ];
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/13a4de8f-0b23-463f-bc86-17439dd82919";
      fsType = "ext4";
    };
    "/boot" = {
      device = "/dev/disk/by-uuid/401D-5794";
      fsType = "vfat";
      options = [
        "fmask=0077"
        "dmask=0077"
      ];
    };
    "/data" = {
      device = "/dev/disk/by-uuid/b244b8b2-6d32-4af3-86a8-356f754f9a29";
      fsType = "ext4";
    };
  };

  swapDevices = [
    { device = "/dev/mapper/swap"; }
  ];

  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  networking.useDHCP = lib.mkDefault true;
}
