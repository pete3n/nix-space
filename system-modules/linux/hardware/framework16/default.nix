# Framework 16 chassis entry point.
#
# This module configures EC quirks, PCI layout, firmware, kernel
# params for the Framework 16. Component modules that also exist on other
# machines (nvidia-prime, etc.) are imported by nixos.nix under their own tags;
# this module only supplies the Framework16 specific values.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  gpuCfg = config.nixSpace.hardware.gpu.nvidiaPrime or { };
in
{
  config = lib.mkMerge [
    {
      hardware = {
        cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
        graphics.enable = true;
        enableRedistributableFirmware = true;
      };

      boot = {
        loader.efi.canTouchEfiVariables = true;
        initrd = {
          availableKernelModules = [
            "nvme"
            "xhci_pci"
            "thunderbolt"
            "usbhid"
            "usb_storage"
            "sd_mod"
          ];
          kernelModules = [ ];
        };
        kernelModules = [ "kvm-amd" ];
        extraModulePackages = [ ];

        # Workaround for suspend then sleep issues.
        # Resolved nvme drive sleep issues.
        kernelParams = [
          "rtc_cmos.use_acpi_alarm=1"
          "nvme_core.default_ps_max_latency_us=1000"
        ];

      };

      services.fwupd.enable = true;

      environment.systemPackages = [
        pkgs.nvtopPackages.amd
      ];
    }

    # These PCI addresses only exists when nixos.nix imported nvidia-prime.nix
    # under the hw-nvidia-dgpu tag.
    (lib.mkIf (gpuCfg.enable or false) {
      nixSpace.hardware.gpu.nvidiaPrime = {
        #   0000:c2:00.0  NVIDIA GB206M [GeForce RTX 5070 Max-Q]
        #   0000:c3:00.0  AMD Strix [Radeon 880M / 890M]
        dgpuAddress = lib.mkDefault "0000:c2:00.0";
        igpuAddress = lib.mkDefault "0000:c3:00.0";
        igpuVendor = lib.mkDefault "amd";
      };
    })
  ];
}
