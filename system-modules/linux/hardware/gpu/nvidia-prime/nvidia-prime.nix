# NVIDIA discrete GPU with PRIME offload.
#
# This module is intended for a laptop with NVIDIA discrete graphics alongside
# integrated graphics from AMD or Intel. The default PCI addresses are
# from a Framework 16 configuration with an AMD iGPU and RTX-5070 GPU.
#
# This module is NOT for AMD discrete GPUs (RX 7700s, etc.)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.hardware.gpu.nvidiaPrime;

  # PCI addresses are given in `lspci -D` form so option values are
  # copy-pasteable. NixOS prime options want the bus number in decimal; udev
  # uses hex values.
  busHex = addr: lib.elemAt (lib.splitString ":" addr) 1;
  busDec = addr: toString (lib.fromHexString (busHex addr));

  # PRIME takes the integrated GPU under a vendor-specific option name.
  igpuBusOption = {
    amd = "amdgpuBusId";
    intel = "intelBusId";
  };
in
{
  options.nixSpace.hardware.gpu.nvidiaPrime = {
    enable = lib.mkEnableOption "NVIDIA discrete GPU with PRIME offload";

    dgpuAddress = lib.mkOption {
      type = lib.types.str;
      default = "0000:c2:00.0";
      example = "0000:01:00.0";
      description = ''
        Full PCI address of the NVIDIA discrete GPU, as printed by `lspci -D`.
        Default is the RTX 5070 Max-Q slot on a Framework 16.
      '';
    };

    igpuAddress = lib.mkOption {
      type = lib.types.str;
      default = "0000:c3:00.0";
      example = "0000:00:02.0";
      description = ''
        Full PCI address of the integrated GPU, as printed by `lspci -D`.
        Default is the AMD Radeon 880M / 890M on a Framework 16.
      '';
    };

    igpuVendor = lib.mkOption {
      type = lib.types.enum [
        "amd"
        "intel"
      ];
      default = "amd";
      description = ''
        Vendor of the integrated GPU. Selects which PRIME option the iGPU bus
        address is assigned to, and which VA-API driver is installed.
      '';
    };

    displayServer = lib.mkOption {
      type = lib.types.enum [
        "wayland"
        "x11"
      ];
      default = "wayland";
      description = ''
        Which display server this host runs. Affects only NVIDIA-specific
        session variables. The driver is loaded either way.
      '';
    };

    dgpuLink = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/run/dgpu";
      description = ''
        Path to a stable symlink pointing at the dGPU DRM card node. The card
        number is not stable across boots, so it is resolved at device-add
        time. Set to null to skip.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.dgpuAddress != cfg.igpuAddress;
        message = ''
          nixSpace.hardware.gpu.nvidiaPrime: dgpuAddress and igpuAddress are
          identical ("${cfg.dgpuAddress}"). Check `lspci -D` — PRIME needs two
          distinct devices.
        '';
      }
    ];

    system.nixos.tags = [ "nvidia-prime" ];

    # NOT X-only despite the name. This is the master switch that loads the
    # NVIDIA kernel module, blacklists nouveau, and activates every
    # hardware.nvidia.* option. Required under Wayland also.
    services.xserver.videoDrivers = [
      "modesetting"
      "nvidia"
    ];

    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      open = true;
      nvidiaSettings = true;

      prime = {
        # Consumed only by the generated xorg.conf. nixpkgs only checks that
        # these are set when offload is enabled. It does not validate them.
        # Wayland ignores them.
        nvidiaBusId = "PCI:${busDec cfg.dgpuAddress}@0:0:0";

        offload = {
          enable = true;
          enableOffloadCmd = true;
        };
      }
      // {
        ${igpuBusOption.${cfg.igpuVendor}} = "PCI:${busDec cfg.igpuAddress}@0:0:0";
      };
    };

    hardware.graphics = {
      enable = true;
      extraPackages = [
        pkgs.nvidia-vaapi-driver
      ]
      ++ lib.optional (cfg.igpuVendor == "intel") pkgs.intel-media-driver;
      extraPackages32 = [
        pkgs.pkgsi686Linux.nvidia-vaapi-driver
      ]
      ++ lib.optional (cfg.igpuVendor == "intel") pkgs.pkgsi686Linux.intel-media-driver;
    };

    environment.sessionVariables = lib.mkIf (cfg.displayServer == "wayland") {
      LIBVA_DRIVER_NAME = "nvidia";
      NVD_BACKEND = "direct";
    };

    environment.systemPackages = [
      pkgs.nvtopPackages.nvidia
    ];

    services.udev.extraRules = lib.mkIf (cfg.dgpuLink != null) ''
      ACTION=="add", SUBSYSTEM=="pci", KERNELS=="${cfg.dgpuAddress}", ENV{SYSTEMD_WANTS}+="dgpuLink.service", TAG+="systemd"
    '';

    systemd.services.dgpuLink = lib.mkIf (cfg.dgpuLink != null) {
      description = "Create dGPU symbolic link";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -- /sys/bus/pci/devices/${cfg.dgpuAddress}/drm/card*
        card_dir=$1
        card_name="$(basename "$card_dir")"
        ln -sf "/dev/dri/$card_name" ${cfg.dgpuLink}
      '';
    };
  };
}
