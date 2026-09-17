# NFS mounts — darwin.
#
# Same option surface as the Linux module of the same name, so a host config
# reads identically on either platform: the options say WHAT is mounted, each
# module knows HOW. The mechanisms share nothing — this one is launchd
# daemons calling mount_nfs; the Linux one is fileSystems entries.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.services.nfsMount;

  # A launchd daemon rather than an /etc/fstab entry. macOS honours fstab
  # only at boot and gives up on a server that is not yet reachable, which is
  # wrong for a machine that may be on a different network when it starts.
  #
  # KeepAlive.NetworkState re-runs this when the network comes back, and
  # StartInterval retries periodically for the case where the interface is up
  # but the server is not yet answering.
  mountDaemon = remote: local: {
    serviceConfig = {
      # /bin/bash and /sbin/mount_nfs by absolute path: this runs before any
      # Nix profile is on PATH, and mount_nfs is a system binary with no
      # nixpkgs equivalent.
      ProgramArguments = [
        "/bin/bash"
        "-c"
        "/bin/mkdir -p ${local} && /sbin/mount_nfs -o ${lib.concatStringsSep "," cfg.options} ${remote} ${local}"
      ];
      RunAtLoad = true;
      StartInterval = cfg.retryInterval;
      StandardErrorPath = "/var/log/nfs-mount.log";
      KeepAlive.NetworkState = true;
    };
  };
in
{
  options.nixSpace.services.nfsMount = {
    enable = lib.mkEnableOption "NFS mounts";

    server = lib.mkOption {
      type = lib.types.str;
      example = "backupsvr.p22";
      description = "Host serving the shares. Resolved at mount time, not at build time.";
    };

    mountRoot = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nfs";
      description = ''
        Directory the shares are mounted under.

        /mnt does not exist on macOS and cannot be created: the root volume is
        read-only and sealed. The activation script below adds a synthetic
        firmlink so the conventional path works — which is why this default
        matches the Linux module's rather than using /Volumes.

        The firmlink needs a REBOOT the first time. Until then the daemons
        run and fail, and /var/log/nfs-mount.log says the directory does not
        exist.
      '';
    };

    shares = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.remotePath = lib.mkOption {
            type = lib.types.str;
            example = "/mnt/user/share";
            description = "Path on the server. The attribute name is the local mount point under mountRoot.";
          };
        }
      );
      default = { };
      example = lib.literalExpression ''
        {
          share.remotePath = "/mnt/user/share";
          open.remotePath = "/mnt/user/open";
        }
      '';
    };

    options = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "rw"
        # macOS mounts from an unprivileged port by default; most NFS servers
        # require a reserved one and reject the mount with a permissions
        # error that names nothing useful.
        "resvport"
        "vers=4"
      ];
      description = "Passed to mount_nfs -o as a comma-separated list.";
    };

    retryInterval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = ''
        Seconds between mount attempts. Covers the case where the network is
        up but the server is not answering yet — KeepAlive handles the
        network coming back, this handles the server coming back.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.shares != { };
        message = ''
          nixSpace.services.nfsMount is enabled but no shares are configured,
          so nothing would be mounted.
        '';
      }
    ];

    # Synthetic firmlink for the mount root. Without it /mnt cannot exist:
    # the macOS root volume is read-only, and synthetic.conf is the supported
    # way to add a top-level entry backed by a writable location.
    #
    # apfs.util -t asks for the entries to be created now; it succeeds
    # silently on a system that already has them and fails harmlessly on one
    # that needs the reboot, hence the || true.
    system.activationScripts.extraActivation.text =
      let
        # "/mnt/nfs" -> "mnt": synthetic.conf takes a single top-level name,
        # not a path.
        topLevel = builtins.head (lib.filter (s: s != "") (lib.splitString "/" cfg.mountRoot));
      in
      lib.mkAfter ''
        /bin/mkdir -p /private/var/${topLevel}
        if ! grep -q '^${topLevel}' /etc/synthetic.conf 2>/dev/null; then
          printf '${topLevel}\tprivate/var/${topLevel}\n' >> /etc/synthetic.conf
          /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t || true
        fi
      '';

    launchd.daemons = lib.mapAttrs' (
      name: share:
      lib.nameValuePair "nfs-${name}" (
        mountDaemon "${cfg.server}:${share.remotePath}" "${cfg.mountRoot}/${name}"
      )
    ) cfg.shares;
  };
}
