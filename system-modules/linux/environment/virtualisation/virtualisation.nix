# Virtual machines and container module.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.virtualisation;
in
{
  options.nixSpace.virtualisation = {
    enable = lib.mkEnableOption "virtual machine and container support";

    emulatedSystems = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "aarch64-linux" ];
      description = ''
        Architectures to run transparently via qemu-user + binfmt.

        This is the qemu-user-static path, registered as kernel binfmt
        handlers rather than installed as a loose binary, so an aarch64 ELF
        just runs, and `nix build` can produce aarch64 output on this host.

        For a remote builder this is the mechanism that lets it serve targets 
        without the real hardware. Note emulated builds are correct but slow; 
        a native remote builder beats this when one is available.

        Left empty by default: it registers kernel handlers and pulls a
        static qemu per architecture, which a machine that does not
        cross-build should not carry.
      '';
    };

    libvirt = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run libvirtd for QEMU/KVM guests.";
      };

      gui = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install virt-manager and quickemu.

          On by default: disable for hypervisors and headless machines.
        '';
      };

      qemuPackage = lib.mkOption {
        type = lib.types.enum [
          "minimal"
          "default"
          "full"
        ];
        default = "default";
        description = ''
          How much of QEMU to install alongside the daemon.
          "minimal" is qemu-utils only: qemu-img and the disk tooling, no
          system emulator. For a machine that manages disk images but runs
          its guests elsewhere.

          "default" is pkgs.qemu: KVM acceleration for the host architecture
          plus the common device models. What almost every machine wants.

          "full" is pkgs.qemu_full: every target architecture, all display
          backends, every device model. A large closure, only for emulating 
          foreign architectures through the system emulator, which for 
          cross-building is usually better served by emulatedSystems below.
        '';
      };
    };

    docker = {
      mode = lib.mkOption {
        type = lib.types.enum [
          "none"
          "rootless"
          "system"
        ];
        default = "rootless";
        description = ''
          How Docker runs, or whether it runs at all.

          "rootless" is the safe default: the daemon runs as the invoking user
          and a container escape does not yield root.

          "system" is required for GPU passthrough.
        '';
      };

      compose = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install docker-compose. Ignored when mode = \"none\".";
      };
    };

  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          !(config.hardware.nvidia-container-toolkit.enable or false) || cfg.docker.mode == "system";
        message = ''
          nvidia-container-toolkit is enabled but nixSpace.virtualisation.docker.mode
          is "${cfg.docker.mode}". GPU passthrough needs the system Docker daemon;
          the CDI hook cannot reach the device from a rootless daemon.

          Set nixSpace.virtualisation.docker.mode = "system".
        '';
      }
    ];

    boot.binfmt.emulatedSystems = cfg.emulatedSystems;

    virtualisation = {
      libvirtd = lib.mkIf cfg.libvirt.enable {
        enable = true;
        qemu = {
          package =
            {
              minimal = pkgs.qemu-utils;
              default = pkgs.qemu;
              full = pkgs.qemu_full;
            }
            .${cfg.libvirt.qemuPackage};
        };
      };

      docker = {
        enable = cfg.docker.mode == "system";
        rootless = lib.mkIf (cfg.docker.mode == "rootless") {
          enable = true;
          setSocketVariable = true;
        };
      };
    };

    programs.virt-manager.enable = cfg.libvirt.enable && cfg.libvirt.gui;

    environment.systemPackages =
      lib.optionals cfg.libvirt.enable (
        [
          (
            {
              minimal = pkgs.qemu-utils;
              default = pkgs.qemu;
              full = pkgs.qemu_full;
            }
            .${cfg.libvirt.qemuPackage}
          )
        ]
        ++ lib.optional (cfg.libvirt.qemuPackage != "minimal") pkgs.qemu-utils
      )
      ++ lib.optional (cfg.libvirt.enable && cfg.libvirt.gui) pkgs.quickemu
      ++ lib.optional (cfg.docker.mode != "none" && cfg.docker.compose) pkgs.docker-compose;
  };
}
