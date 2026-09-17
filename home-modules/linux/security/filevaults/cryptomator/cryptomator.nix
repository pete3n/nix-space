# Encrypted file vaults.
#
# A namespace grouping related tools rather than an abstraction over them.
# Vault software differs in ways that resist a shared interface — per-file
# versus container encryption, mounted versus in-place, GUI versus CLI-only —
# so each tool gets its own option group and nothing is shared but the
# namespace. A second tool added here should be a sibling block, not a
# conformance exercise.
#
# All packages are caller-supplied. These track upstream closely and the host
# sources them from its unstable input, which this module does not know about.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.security.filevaults;

  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  isX86Linux = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
in
{
  options.nixSpace.security.filevaults = {
    enable = lib.mkEnableOption "encrypted file vault tooling";

    cryptomator = {
      gui = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = if isX86Linux then pkgs.cryptomator else null;
        defaultText = lib.literalMD "`pkgs.cryptomator` on x86_64-linux, otherwise `null`";
        example = lib.literalExpression "pkgs.unstable.cryptomator";
        description = ''
          Cryptomator desktop application. null to omit.

          The default is conditional rather than flat: pkgs.cryptomator
          declares platforms = [ "x86_64-linux" ], and this option is read
          unconditionally when building home.packages — so a flat default
          would fail evaluation on the Pi nodes before anyone opted out.

          Stable and unstable currently ship the same version, so this takes
          the stable attribute and stays independent of the unstable overlay.
        '';
      };

      cli = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = if isLinux then pkgs.cryptomator-cli else null;
        defaultText = lib.literalMD "`pkgs.cryptomator-cli` on Linux, otherwise `null`";
        description = ''
          Cryptomator command-line vault access. null to omit.

          x86_64-linux AND aarch64-linux: its installPhase selects the jfuse
          native-access module per architecture, so unlike the GUI this runs
          on the Pi nodes.

          Opens the same vault format as the GUI, so a vault created on the
          workstation is readable headlessly.
        '';
      };
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional vault tooling, supplied by the caller.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.cryptomator.gui != null) -> isX86Linux;
        message = ''
          nixSpace.security.filevaults.cryptomator.gui is set on a host that is
          not x86_64-linux. The package hardcodes the amd64 jfuse native
          access module and declares platforms = [ "x86_64-linux" ]; there is
          no build for this system.

          cryptomator.cli supports aarch64-linux and opens the same vaults.
        '';
      }
      {
        assertion = (cfg.cryptomator.cli != null) -> isLinux;
        message = ''
          nixSpace.security.filevaults.cryptomator.cli is set on a non-Linux
          host. The package declares Linux platforms only — it links libfuse3
          and selects a linux.* jfuse module.
        '';
      }
    ];

    # Mounting needs nothing from the system side. The wrappers supply
    # libfuse3, and an unprivileged FUSE mount is visible to the user who
    # created it — which is what a personal vault wants.
    #
    # programs.fuse.userAllowOther in the NixOS configuration is only needed
    # to expose the mountpoint to OTHER users: a service running under a
    # different account, or a container bind-mounting the vault path. Not
    # needed here, and confirmed unnecessary in practice — vaults mount as
    # fuse.fuse-nio-adapter with user_id set and no allow_other.
    home.packages =
      lib.optional (cfg.cryptomator.gui != null) cfg.cryptomator.gui
      ++ lib.optional (cfg.cryptomator.cli != null) cfg.cryptomator.cli
      ++ cfg.extraPackages;
  };
}
