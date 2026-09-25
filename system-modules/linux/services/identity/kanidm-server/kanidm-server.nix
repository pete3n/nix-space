# kanidm, the Identity Domain's directory: the one place people, groups and
# their passkeys live. Hosts look people up through kanidm-unixd, and step-ca
# only signs a user certificate after a kanidm login.
#
# A thin layer over the NixOS kanidm server. It fills in what every Identity
# Node does the same way: TLS from the host's internal ACME cert, the listen
# port and firewall, and nightly backups. People, groups and OAuth2 clients
# are per-domain data, so the host sets them in `services.kanidm.provision`.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.services.kanidm-server;

  # Where the internal-acme module keeps this host's cert.
  certDirectory = "/var/lib/acme/${cfg.fqdn}";
in
{
  options.nixSpace.services.kanidm-server = {
    enable = lib.mkEnableOption "the kanidm identity server";

    package = lib.mkOption {
      type = lib.types.package;
      example = lib.literalExpression "pkgs.kanidm_1_11";
      description = ''
        The kanidm release to run. Always pinned by the host: kanidm's
        database only upgrades one minor release at a time, so the version
        must never change by accident.
      '';
    };

    fqdn = lib.mkOption {
      type = lib.types.str;
      example = "idm1.p22.lan";
      description = ''
        This node's name. kanidm serves the internal ACME cert issued for it,
        so the name must also be in `nixSpace.services.internal-acme.certs`.
      '';
    };

    domain = lib.mkOption {
      type = lib.types.str;
      example = "p22.lan";
      description = ''
        The domain kanidm manages, which is also the WebAuthn RP-ID every
        passkey is bound to. Changing it later means re-enrolling every passkey.
        Read it from the domain descriptor.
      '';
    };

    origin = lib.mkOption {
      type = lib.types.strMatching "^https://.*";
      example = "https://idm1.p22.lan:8443";
      description = ''
        The URL people and services use to reach kanidm. It must sit inside
        `domain`. Read it from the domain descriptor.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8443;
      description = "Listen port. Must match the port in `origin`.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the listen port, so other hosts can log in and look people up.";
    };

    backupVersions = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 7;
      description = ''
        How many nightly backups to keep in /var/lib/kanidm/backups. They stay
        on this host, so copy them elsewhere to survive losing the node.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.kanidm = {
      inherit (cfg) package;
      server = {
        enable = true;
        settings = {
          inherit (cfg) domain origin;
          bindaddress = "0.0.0.0:${toString cfg.port}";
          # Plain strings, not Nix paths: a path would copy the private key
          # into the world-readable store.
          tls_chain = "${certDirectory}/fullchain.pem";
          tls_key = "${certDirectory}/key.pem";
          online_backup.versions = cfg.backupVersions;
        };
      };
    };

    # The ACME cert belongs to the acme user. Its group decides who else may
    # read the key, so hand it to kanidm. kanidm only reads the cert when it
    # starts, so it has to restart whenever the cert renews.
    security.acme.certs.${cfg.fqdn} = {
      group = "kanidm";
      reloadServices = [ "kanidm.service" ];
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall cfg.port;

    assertions = [
      {
        assertion = lib.hasSuffix ":${toString cfg.port}" cfg.origin;
        message = "nixSpace.services.kanidm-server: origin ${cfg.origin} does not use port ${toString cfg.port}.";
      }
      {
        assertion = builtins.elem cfg.fqdn config.nixSpace.services.internal-acme.certs;
        message = "nixSpace.services.kanidm-server: add ${cfg.fqdn} to nixSpace.services.internal-acme.certs, or kanidm has no TLS cert to serve.";
      }
    ];
  };
}
