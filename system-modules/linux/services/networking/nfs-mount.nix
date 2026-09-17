# NFS client mount service module.
# Automounts an nfs share on first access.
#
# UID mapping under sec=sys comes from numeric UIDs on the network, not from
# mount options. If the server's UIDs differ from the client's, files appear
# owned by the wrong user. Match the UIDs or configure idmapd.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.services.nfsMount;

  shareOpts =
    { name, ... }:
    {
      options = {
        remotePath = lib.mkOption {
          type = lib.types.str;
          example = "/mnt/user/share";
          description = "Export path on the server.";
        };

        localPath = lib.mkOption {
          type = lib.types.str;
          default = "/mnt/nfs/${name}";
          description = "Local mount point.";
        };

        options = lib.mkOption {
          type = lib.types.str;
          default = "rw,noatime,sec=sys,vers=4";
          description = ''
            Mount options.

            vers=4 stated explicitly: negotiation can land on v3,
            which changes locking and ID handling without any visible error.
          '';
        };

        idleTimeout = lib.mkOption {
          type = lib.types.str;
          default = "600";
          description = ''
            Seconds of inactivity before unmounting.

            Short timeouts keep a laptop from holding a mount across a network
            change; too short means repeated mount latency. Empty string
            disables idle unmounting.
          '';
        };
      };
    };
in
{
  options.nixSpace.services.nfsMount = {
    enable = lib.mkEnableOption "NFS client mounts";

    server = lib.mkOption {
      type = lib.types.str;
      example = "backupsvr.lan";
      description = "NFS server host, resolvable by name.";
    };

    shares = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule shareOpts);
      default = { };
      example = lib.literalExpression ''
        {
          share.remotePath = "/mnt/user/share";
          open.remotePath = "/mnt/user/open";
        }
      '';
      description = "Exports to mount, keyed by a short local name.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.shares != { }) {
    # systemd invokes mount.nfs4 via its own path, which does not include the
    # system profile. This is what installs the mount helper where systemd will find it.
    boot.supportedFilesystems.nfs = true;

    services.rpcbind.enable = true;
		systemd.services.rpc-statd-notify.wantedBy = lib.mkForce [ ];   # NSM is NFSv3; this client is v4

    systemd.mounts = lib.mapAttrsToList (name: share: {
      type = "nfs";
      what = "${cfg.server}:${share.remotePath}";
      where = share.localPath;
      mountConfig.Options = share.options;

      # No wantedBy: the automount unit triggers this on access. A mount unit
      # wanted by a target would defeat automounting and block boot on an
      # unreachable server.
    }) cfg.shares;

    systemd.automounts = lib.mapAttrsToList (name: share: {
      where = share.localPath;
      wantedBy = [ "multi-user.target" ];
      automountConfig = lib.optionalAttrs (share.idleTimeout != "") {
        TimeoutIdleSec = share.idleTimeout;
      };
    }) cfg.shares;
  };
}
