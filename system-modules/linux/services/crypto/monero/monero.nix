# Monero daemon module.
#
# This module accepts a list of config file paths and provides them to the
# monero daemon.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.services.monero;
in
{
  options.nixSpace.services.monero = {
    enable = lib.mkEnableOption "Monero daemon";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/monero";
      example = "/data/monero";
      description = ''
        Blockchain data directory. Nothing here creates or mounts it.
      '';
    };

    prune = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Prune the blockchain. Maps directly to services.monero.prune.

        Pruning discards most historical ring signature data. Reversing it
        requires a full resync, so this is decided once per host.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start the daemon at boot. See bitcoind.autoStart.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional monerod configuration lines.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.monero = {
      enable = true;
      dataDir = cfg.dataDir;
      prune = cfg.prune;
      mining.enable = false;
      extraConfig = cfg.extraConfig;
    };

    systemd.services.monero.wantedBy = lib.mkForce (lib.optional cfg.autoStart "multi-user.target");
  };
}
