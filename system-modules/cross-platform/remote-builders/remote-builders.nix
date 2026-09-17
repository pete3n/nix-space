# Remote builders, client side module.
#
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.nix.remoteBuilders;

  machineOpts =
    { name, ... }:
    {
      options = {
        hostName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = ''
            Host to reach the builder at. Resolvable via DNS or an ssh config
            alias.
          '';
        };

        aliases = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [ "192.168.1.8" ];
          description = ''
            Additional names the host key is valid for.

            An IP here is a maintenance hazard: it must be updated when the
            builder moves, and nothing detects a stale entry until a build
            fails host verification. Prefer relying on DNS.
          '';
        };

        publicKey = lib.mkOption {
          type = lib.types.str;
          example = "ssh-ed25519 AAAAC3Nz...";
          description = ''
            Builder's SSH host key, added to programs.ssh.knownHosts.

            Required. Without it the daemon falls back to trust-on-first-use,
            and a first connection waits for a confirmation prompt on a tty
            that does not exist the build hangs rather than failing.
          '';
        };

        system = lib.mkOption {
          type = lib.types.str;
          example = "x86_64-linux";
          description = "System the builder produces.";
        };

        sshUser = lib.mkOption {
          type = lib.types.str;
          default = "remotebuild";
          description = "Account to connect as. Must be a trusted user on the builder.";
        };

        sshKeyFile = lib.mkOption {
          type = lib.types.str;
          example = lib.literalExpression "config.age.secrets.p22-build-key.path";
          description = ''
            Private key path, readable by root. The nix daemon connects to this
            path not the current user. An agenix secret must set owner = "root", 
            or builds fail with a permission error attributed to ssh.

            Use a runtime path, not a path literal. Literal paths are copied to the
            store and world-readable.
          '';
        };

        maxJobs = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = ''
            Concurrent jobs the builder will accept. A property of the builder,
            not of this client.
          '';
        };

        settings = {
          fallback = cfg.fallback;
          # The builder substitutes its own dependencies rather than the client
          # uploading them. Without it, every store path the build needs is
          # copied over SSH even when the builder could fetch it directly.
          builders-use-substitutes = true;
        };

        speedFactor = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Relative speed, used to rank builders. Higher wins.";
        };

        supportedFeatures = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "big-parallel"
            "benchmark"
            "kvm"
            "nixos-test"
          ];
          description = ''
            Features the builder advertises. A derivation requiring a feature
            no builder offers is built locally instead.
          '';
        };

        protocol = lib.mkOption {
          type = lib.types.str;
          default = "ssh-ng";
          description = "ssh-ng is the default for modern Nix daemons.";
        };
      };
    };

  # A builder must not list itself. Self-referential distributed builds
  # deadlock: the daemon connects to its own sshd and waits for a slot it is
  # holding. Filtering here means one machine list can be shared fleet-wide,
  # including with the builder.
  remoteMachines = lib.filter (m: m.hostName != config.networking.hostName) (
    lib.attrValues cfg.machines
  );
in
{
  options.nixSpace.nix.remoteBuilders = {
    enable = lib.mkEnableOption "remote builders";

    machines = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule machineOpts);
      default = { };
      description = ''
        Build machines, keyed by host name. Entries naming this host are
        skipped automatically.
      '';
    };

    fallback = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Build locally when no builder is reachable.

        True keeps an unreachable builder from being fatal, at the cost of a
        slow local build that looks like the remote one succeeded. False makes
        builder outages loud, only appropriate where local builds are impractical,
        such as a Pi that cannot build its own closure.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && remoteMachines != [ ]) {
    nix = {
      distributedBuilds = true;

      buildMachines = map (key: {
        inherit (key)
          hostName
          system
          sshUser
          maxJobs
          speedFactor
          supportedFeatures
          protocol
          ;
        sshKey = key.sshKeyFile;
      }) remoteMachines;

      # nix.settings, not extraOptions. extraOptions appends raw text to
      # nix.conf, so a setting written both ways lands twice with no conflict
      # detection.
      settings.fallback = cfg.fallback;
    };

    programs.ssh.knownHosts = lib.listToAttrs (
      map (
        m:
        lib.nameValuePair m.hostName {
          hostNames = [ m.hostName ] ++ m.aliases;
          publicKey = m.publicKey;
        }
      ) remoteMachines
    );
  };
}
