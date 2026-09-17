# Cryptocurrency wallets and node tooling.
#
# All of these are supplied by the caller through package options rather than
# named from pkgs directly: the versions in nixpkgs stable lag the networks
# they talk to, and a wallet that cannot reach consensus is worse than one
# that is absent. That makes them the same case as nixvim and the firefox
# extensions — the module owns the shape, the host owns the derivation.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.programs.crypto;
in
{
  options.nixSpace.programs.crypto = {
    enable = lib.mkEnableOption "cryptocurrency wallets and node tooling";

    bisq = {
      version = lib.mkOption {
        type = lib.types.enum [
          "none"
          "v1"
          "v2"
        ];
        default = "v2";
        description = ''
          Which Bisq to install.

          An enum rather than a boolean each because the two CANNOT COEXIST
          in one profile: both are built with jpackage, which lays a Java
          application out as lib/app/desktop.jar named after the build target
          rather than the application. Two of them put different files at the
          same path, and buildEnv rejects that with

            two given paths contain a conflicting subpath:
              .../bisq2-2.1.11/lib/app/desktop.jar
              .../bisq1-1.10.4/lib/app/desktop.jar

          Expressed as two booleans the illegal state is writable and fails at
          build time; expressed as an enum it cannot be written at all.

          These are separate networks rather than versions of one
          application — v1 is the original multisig protocol, v2 the newer
          one — so running both is a real thing to want. For occasional use
          of the other, `nix run nixpkgs#bisq1` executes the derivation
          directly and never touches the profile, which is why that works
          when installing both does not.
        '';
      };

      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression "pkgs.unstable.bisq2";
        description = ''
          The Bisq derivation, supplied by the calling configuration.

          Not defaulted to pkgs.bisq2: the host tracks unstable for these,
          and this module does not know that attribute exists. Ignored when
          version is "none".
        '';
      };
    };

    monero = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Monero wallet and node tooling.

          cli provides monerod and the blockchain utilities; gui provides
          only monero-wallet-gui and drives a daemon, either the local
          monerod or a remote node. They share no paths, so unlike Bisq both
          install together — the GUI's version number runs ahead of the CLI's
          without that meaning two daemons.
        '';
      };

      cliPackage = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression "pkgs.unstable.monero-cli";
        description = "monerod and the blockchain utilities. Supplied by the caller.";
      };

      guiPackage = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        example = lib.literalExpression "pkgs.unstable.monero-gui";
        description = ''
          monero-wallet-gui. Supplied by the caller.

          Linux-only in practice, and a large Qt closure. null installs the
          CLI tooling alone, which is the right shape for a headless node.
        '';
      };
    };

    sparrow = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "pkgs.unstable.sparrow";
      description = ''
        Sparrow Bitcoin wallet, supplied by the caller. null to omit.

        Also a Java desktop application. If it is packaged with jpackage it
        can collide with Bisq the same way the two Bisqs collide with each
        other — see the assertion below.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional wallets or tooling, supplied by the caller.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.bisq.version == "none" -> true;
        message = "unreachable";
      }
      {
        assertion = (cfg.bisq.version != "none") -> (cfg.bisq.package != null);
        message = ''
          nixSpace.programs.crypto.bisq.version is "${cfg.bisq.version}" but
          bisq.package is null.

          Supply the derivation from the calling configuration, where the
          unstable package set is in scope:

            nixSpace.programs.crypto.bisq.package = pkgs.unstable.bisq2;
        '';
      }
      {
        assertion = cfg.monero.enable -> (cfg.monero.cliPackage != null || cfg.monero.guiPackage != null);
        message = ''
          nixSpace.programs.crypto.monero is enabled but neither cliPackage
          nor guiPackage was supplied, so it would install nothing.
        '';
      }
    ];

    home.packages =
      lib.optional (cfg.bisq.version != "none" && cfg.bisq.package != null) cfg.bisq.package
      ++ lib.optionals cfg.monero.enable (
        lib.optional (cfg.monero.cliPackage != null) cfg.monero.cliPackage
        ++ lib.optional (cfg.monero.guiPackage != null) cfg.monero.guiPackage
      )
      ++ lib.optional (cfg.sparrow != null) cfg.sparrow
      ++ cfg.extraPackages;
  };
}
