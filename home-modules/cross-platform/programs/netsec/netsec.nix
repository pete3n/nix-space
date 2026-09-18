{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nixSpace.programs.netsec;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  options.nixSpace.programs.netsec = {
    enable = lib.mkEnableOption "network reconnaissance and binary analysis tooling";

    wireless = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Include 802.11 monitor-mode and handshake tooling. These require an
        adapter that supports monitor mode and, for most of them, root; the
        packages alone grant no capability.
      '';
    };

    cracking = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Include hashcat.

        With the NVIDIA driver present system-side, hashcat reaches the GPU
        through the driver's OpenCL ICD without anything extra here. Its CUDA
        backend additionally wants the CUDA runtime and NVRTC in the closure,
        which this does not provide, so it logs two init failures at startup
        and falls back to OpenCL (still using GPU), within a few percent of
        CUDA on most modes.

        A real CPU fallback only happens when no GPU runtime is visible at
        all.
      '';
    };

    sdr = {
      gnuradio = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression "pkgs.unstable.gnuradio";
        description = ''
          GNU Radio signal-processing framework and flowgraph editor.
          null to omit.

          Caller-supplied: SDR tooling moves quickly and the versions in
          stable lag the drivers, so the host sources these from its unstable
          input.

          A very large closure — Python bindings, Qt, and the graphical
          editor. It also talks to no hardware on its own; that is what
          soapysdr below provides.
        '';
      };

      soapysdr = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression "pkgs.unstable.soapysdr-with-plugins";
        description = ''
          SoapySDR hardware abstraction layer. null to omit.

          Use soapysdr-with-plugins rather than bare soapysdr: the plugin
          modules are what reach actual devices, and the base package is only
          the abstraction. Bare soapysdr enumerates nothing and reports no
          error, the same way zathura without a format backend opens and
          displays nothing.

          Reaching a USB device unprivileged additionally needs udev rules at
          the system level — hardware.rtl-sdr.enable or equivalent for the
          device family. Without them SoapySDRUtil --find comes up empty even
          with the right plugin present.
        '';
      };
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.local.some-recon-tool ]";
      description = ''
        Additional tools, supplied by the calling configuration. This is the
        seam for overlay-provided packages (`pkgs.local.*`, `pkgs.mod.*`) so
        that this module stays importable without those overlays applied.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      (
        with pkgs;
        [
          # Recon and scanning
          chisel
          masscan
          ngrep
          nmap
          rustscan
          socat
          whois

          # Capture and analysis
          wireshark
          termshark

          # Binary analysis
          binwalk
          bingrep
        ]
        ++ lib.optionals isLinux [
          ligolo-ng
          proxychains
        ]
      )
      ++ lib.optionals cfg.wireless (
        with pkgs;
        [
          aircrack-ng
          gpsd
        ]
        ++ lib.optionals isLinux [
          angryoxide
          bettercap
          hcxdumptool
          hcxtools
          reaverwps-t6x
        ]
      )
      ++ lib.optional cfg.cracking pkgs.hashcat
      ++ lib.optional (cfg.sdr.gnuradio != null) cfg.sdr.gnuradio
      ++ lib.optional (cfg.sdr.soapysdr != null) cfg.sdr.soapysdr
      ++ cfg.extraPackages;
  };
}
