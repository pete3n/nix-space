# Bitcoin Core daemon module.
#
# This module accepts a list of config file paths and provides them to the
# bitcoin daemon.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.services.bitcoind;
in
{
  options.nixSpace.services.bitcoind = {
    enable = lib.mkEnableOption "Bitcoin Core daemon";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/bitcoind";
      example = "/data/bitcoind";
      description = ''
        Blockchain data directory.

        The nixpkgs default lives under /var/lib. Point this at a dedicated
        mount if the chain will not fit.
      '';
    };

    prune = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      example = 102400;
      description = ''
        Target size in MiB for the pruned blockchain, or null for a full node.

        Pruning is not reversible without a full resync, so this is a decision
        made once per host rather than a value to tune later.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start the daemon at boot.

        Defaults to false: initial block download is expensive and a node that
        starts unattended on a laptop is rarely what was wanted. Start it with
        `systemctl start bitcoind-main`.
      '';
    };

    extraConfigFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = lib.literalExpression "[ config.age.secrets.bitcoind-rpc-hmac.path ]";
      description = ''
        Additional config files pulled in via `includeconf`.

        This is how secrets reach the daemon without appearing in the Nix
        store. Supply a runtime path such as an agenix or sops target not a path
        literal, which would be copied to the store and be world-readable.

        The decrypted file must be readable by `nixSpace.services.bitcoind.user`.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "bitcoind-main";
      readOnly = true;
      description = ''
        Service account name, exposed so the consumer can set secret ownership
        without hardcoding it:

          age.secrets.bitcoind-rpc-hmac.owner = config.nixSpace.services.bitcoind.user;
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.bitcoind.main = {
      enable = true;
      dataDir = cfg.dataDir;
      prune = lib.mkIf (cfg.prune != null) cfg.prune;
      extraConfig = lib.concatMapStringsSep "\n" (path: "includeconf=${path}") cfg.extraConfigFiles;
    };

    # mkForce because nixpkgs sets wantedBy unconditionally; mkDefault would
    # lose the merge.
    systemd.services.bitcoind-main.wantedBy = lib.mkForce (
      lib.optional cfg.autoStart "multi-user.target"
    );
  };
}
