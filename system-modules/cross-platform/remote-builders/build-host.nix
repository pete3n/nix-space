# Remote builder, server side: the account other machines' nix daemons
# connect as.
#
# The client side is nixSpace.nix.remoteBuilders. A host can be both, so the
# client module filters out any machine entry naming itself.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.nix.buildHost;
in
{
  options.nixSpace.nix.buildHost = {
    enable = lib.mkEnableOption "accepting remote build jobs";

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Public keys permitted to connect as the build account.

        Supplied by the caller: these are the fleet operator's keys, not
        something the library can know. A build host with none accepts no
        jobs, which is a working configuration for a machine that is not
        yet a builder.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "remotebuild";
      description = ''
        Account the connecting daemon authenticates as. Must match the
        client's sshUser.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users = {
      groups.builders = { };
      users.${cfg.user} = {
        isSystemUser = true;
        group = "builders";
        # The nix daemon needs a real shell to run nix-store over SSH.
        useDefaultShell = true;
        openssh.authorizedKeys.keys = cfg.authorizedKeys;
      };
    };

    # trusted-users, not just allowed-users: a remote builder writes to the
    # local store, which allowed-users alone does not permit. The failure is
    # a permission error partway through a build rather than at connect.
    nix.settings = {
      allowed-users = [
        "@builders"
        "root"
      ];
      trusted-users = [
        "@builders"
        "root"
      ];
    };
  };
}
