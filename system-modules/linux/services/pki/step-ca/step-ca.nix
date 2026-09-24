# step-ca — the online certificate authority for an Identity Domain.
#
# step-ca runs as an INTERMEDIATE signed once by the domain's offline root
# (P22-CA), so every certificate it issues chains under a root the Fleet already
# trusts — which is why the Identity Node can serve its own TLS with no
# self-signed bootstrap (ADR-0008).
#
# Step 2 scope: root+intermediate trust, ACME for internal TLS, and the SSH
# HOST CA. The SSH USER CA key is loaded and its public key published so hosts
# can trust it, but the OIDC provisioner that actually MINTS user/elevated certs
# waits on kanidm (Step 3, ADR-0001/0003) — there is deliberately no provisioner
# that issues user certs here yet.
#
# Follows the house service-module shape (see services/crypto/bitcoin): options
# under `nixSpace.services.*`, self-gated on `enable`, secrets supplied as
# runtime paths (agenix targets) so no private key ever lands in the Nix store.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.services.step-ca;
in
{
  options.nixSpace.services.step-ca = {
    enable = lib.mkEnableOption "step-ca certificate authority";

    fqdn = lib.mkOption {
      type = lib.types.str;
      example = "idm1.p22.lan";
      description = ''
        The Identity Node's fully-qualified name. Used as step-ca's TLS name and
        as the CA URL host. Read from the domain descriptor by the consumer, e.g.
        `(nixSpaceLib.domainDescriptor."p22.lan").nodes.idm1.fqdn`.
      '';
    };

    rootCertFile = lib.mkOption {
      type = lib.types.path;
      example = lib.literalExpression "../../secrets/certs/p22-ca.crt";
      description = ''
        The domain's offline ROOT certificate (public). This is the same
        `p22-ca.crt` already installed in the Fleet trust store; step-ca
        publishes it as the chain root. A public cert, so a store path is fine.
      '';
    };

    intermediateCertFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        The intermediate certificate (public), signed once by the offline root.
        A public cert, so a committed store path is fine — the matching private
        key is a secret (see `intermediateKeyFile`).
      '';
    };

    intermediateKeyFile = lib.mkOption {
      type = lib.types.path;
      example = lib.literalExpression ''config.age.secrets."step-ca/intermediate.key".path'';
      description = ''
        Runtime path to the intermediate private key. Supply an agenix/sops
        target, NOT a path literal (a literal is copied world-readable into the
        store). The decrypted file must be owned by `nixSpace.services.step-ca.user`.
      '';
    };

    intermediatePasswordFile = lib.mkOption {
      type = lib.types.path;
      example = lib.literalExpression ''config.age.secrets."step-ca/intermediate.password".path'';
      description = ''
        Runtime path to the password protecting the intermediate key. step-ca
        needs this at startup to unlock the key. Also an agenix target.
      '';
    };

    ssh = {
      hostCAKeyFile = lib.mkOption {
        type = lib.types.path;
        example = lib.literalExpression ''config.age.secrets."step-ca/ssh_host_ca".path'';
        description = ''
          Runtime path to the SSH HOST CA private key (agenix target). step-ca
          signs host certificates with it so clients can retire `known_hosts`.
        '';
      };

      userCAKeyFile = lib.mkOption {
        type = lib.types.path;
        example = lib.literalExpression ''config.age.secrets."step-ca/ssh_user_ca".path'';
        description = ''
          Runtime path to the SSH USER CA private key (agenix target). Loaded now
          so the key lives in one place; the provisioner that mints user certs
          from it arrives with kanidm OIDC in Step 3.
        '';
      };
    };

    acme.enable = lib.mkEnableOption "the ACME provisioner for internal TLS" // {
      default = true;
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "0.0.0.0";
      description = "Listen address for step-ca (passed through to services.step-ca).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "Listen port for step-ca. Also the port opened when openFirewall is set.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open the step-ca listen port in the firewall.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "step-ca";
      readOnly = true;
      description = ''
        Service account name, exposed so the consumer can own the decrypted
        secrets without hardcoding it:

          age.secrets."step-ca/ssh_host_ca".owner = config.nixSpace.services.step-ca.user;
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.step-ca = {
      enable = true;
      inherit (cfg) address port openFirewall intermediatePasswordFile;

      # ca.json. step-ca chains our intermediate under the offline root, serves
      # ACME for internal TLS, and signs SSH host+user certificates. The
      # provisioner list carries ONLY ACME — no user-cert provisioner until the
      # kanidm OIDC issuer exists (Step 3).
      settings = {
        root = cfg.rootCertFile;
        crt = cfg.intermediateCertFile;
        key = cfg.intermediateKeyFile;
        dnsNames = [ cfg.fqdn ];

        # SSH certificate authority: distinct host and user CA keys (ADR-0003).
        ssh = {
          hostKey = cfg.ssh.hostCAKeyFile;
          userKey = cfg.ssh.userCAKeyFile;
        };

        db = {
          type = "badgerv2";
          dataSource = "/var/lib/step-ca/db";
        };

        authority.provisioners = lib.optional cfg.acme.enable {
          type = "ACME";
          name = "acme";
        };
      };
    };
  };
}
