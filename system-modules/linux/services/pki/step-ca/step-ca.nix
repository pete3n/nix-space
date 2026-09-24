# step-ca — the online certificate authority for an Identity Domain.
#
# step-ca runs as an INTERMEDIATE signed once by the domain's offline root
# (P22-CA), so every certificate it issues chains under a root the Fleet already
# trusts — which is why the Identity Node can serve its own TLS with no
# self-signed bootstrap (ADR-0008).
#
# Step 2 scope: root+intermediate trust, ACME for internal TLS, and the SSH
# HOST CA (operator-signed first cert via JWK, self-renewal via SSHPOP —
# ADR-0009). The SSH USER CA key is loaded and its public key published so hosts
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
  hostProvisioner = cfg.ssh.hostProvisioner;

  # The only names and addresses ANY cert from this CA may carry, shaped as a
  # step-ca name policy. Used for both SSH host and X.509 certs.
  domainNames = {
    dns = cfg.allowedDomains;
    ip = cfg.allowedAddresses;
  };

  # step-ca's built-in SSH certificate template. The `hosts` provisioner puts a
  # type check in front of it. Everything after the check must match this
  # stock template, so the certs themselves come out unchanged.
  defaultSSHTemplate = ''
    {
    	"type": {{ toJson .Type }},
    	"keyId": {{ toJson .KeyID }},
    	"principals": {{ toJson .Principals }},
    	"extensions": {{ toJson .Extensions }},
    	"criticalOptions": {{ toJson .CriticalOptions }}
    }'';

  # Both host-cert provisioners (first issuance and renewal) must agree on the
  # lifetime, or a renewal would quietly change it.
  hostCertClaims = lib.optionalAttrs (hostProvisioner != null) {
    defaultHostSSHCertDuration = hostProvisioner.certDuration;
    maxHostSSHCertDuration = hostProvisioner.certDuration;
  };
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

      hostProvisioner = lib.mkOption {
        default = null;
        description = ''
          The JWK provisioner an operator uses to sign a host's FIRST SSH host
          certificate (`step ssh certificate --host`). Its private key is
          password-encrypted, and the password stays with the operator. So no
          fleet host holds anything that can mint another host's certificate.
          After that first cert, the host renews on its own through the SSHPOP
          provisioner (ADR-0009). null leaves both provisioners out.

          Both files come from `step crypto jwk create` and are safe to commit:
          step-ca publishes the encrypted key on its /provisioners endpoint
          anyway, and it is useless without the password.
        '';
        type = lib.types.nullOr (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                default = "hosts";
                description = "Provisioner name, passed as `step ssh certificate --provisioner`.";
              };

              publicKeyFile = lib.mkOption {
                type = lib.types.path;
                description = "The JWK public key (JSON), from `step crypto jwk create`.";
              };

              encryptedKeyFile = lib.mkOption {
                type = lib.types.path;
                description = ''
                  The password-encrypted JWK private key, in JWE compact form
                  (one line, `step crypto jose format` output).
                '';
              };

              certDuration = lib.mkOption {
                type = lib.types.str;
                default = "720h";
                description = ''
                  Host certificate lifetime (30 days). Hosts renew daily, so a
                  host can be cut off from the CA for most of this window before
                  clients stop trusting it.
                '';
              };
            };
          }
        );
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

    allowedDomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [ "*.p22.lan" ];
      description = ''
        DNS names ANY certificate from this CA may carry, whichever provisioner
        issues it: TLS (X.509) certs and SSH host certs. step-ca refuses
        anything outside them. The Intermediate CA serves one Domain and should
        never vouch for a name outside it. Read from the domain descriptor.
      '';
    };

    allowedAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "192.168.1.0/24" ];
      description = "IP addresses/CIDRs a certificate from this CA may carry. See allowedDomains.";
    };

    acme = {
      enable = lib.mkEnableOption "the ACME provisioner for internal TLS" // {
        default = true;
      };

      certDuration = lib.mkOption {
        type = lib.types.str;
        default = "168h";
        description = ''
          Lifetime of TLS certs issued over ACME (7 days). step-ca's own default
          is 24h, too short for NixOS's once-a-day renewal check. Seven days
          still keeps a leaked key's useful life short. Clients renew with a
          few days to spare (see the internal-acme module), so a CA outage of
          a few days doesn't take TLS down.
        '';
      };
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
      # provisioners are ACME plus the two SSH HOST-cert ones. None issues user
      # certs until the kanidm OIDC issuer exists (Step 3).
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

        # CA-wide name limits. They have to live here: step-ca ignores
        # allow/deny lists in a provisioner's ca.json entry, both as a
        # top-level `policy` key and under `options`, and only accepts
        # per-provisioner lists through its admin API. Probes on 2026-09-23
        # confirmed out-of-domain host and TLS certs were issued in both cases.
        #
        # There are no `ssh.user` rules yet. User certs are refused by the
        # `hosts` template below, and Step 3's OIDC provisioner will add the
        # user rules it needs.
        authority.policy = {
          x509.allow = domainNames;
          ssh.host.allow = domainNames;
        };

        authority.provisioners =
          lib.optional cfg.acme.enable {
            type = "ACME";
            name = "acme";
            # Both default and max. A client can't ask for a longer cert, and
            # every ACME cert gets the same, predictable lifetime.
            claims = {
              defaultTLSCertDuration = cfg.acme.certDuration;
              maxTLSCertDuration = cfg.acme.certDuration;
            };
          }
          ++ lib.optionals (hostProvisioner != null) [
            # Operator-run first issuance of SSH host certificates.
            {
              type = "JWK";
              inherit (hostProvisioner) name;
              key = builtins.fromJSON (builtins.readFile hostProvisioner.publicKeyFile);
              # Trimmed because an editor may leave a trailing newline, and
              # step-ca would then fail to parse the JWE.
              encryptedKey = lib.trim (builtins.readFile hostProvisioner.encryptedKeyFile);
              claims = hostCertClaims // {
                enableSSHCA = true;
              };

              # Refuses every user cert. step-ca renders this template for each
              # SSH cert it signs, and `fail` aborts the signing. (Name limits
              # are CA-wide, in `authority.policy` above.) The probe on
              # 2026-09-23 confirmed this refusal works.
              options.ssh.template = ''
                {{- if ne .Type "host" }}{{ fail "the hosts provisioner signs SSH host certificates only" }}{{ end -}}
                ${defaultSSHTemplate}
              '';
            }
            # Renewal: a host proves it holds a still-valid host cert (and its
            # key) and gets a fresh one with the same principals. No secret
            # beyond the host's own SSH key is needed.
            {
              type = "SSHPOP";
              name = "sshpop";
              claims = hostCertClaims // {
                enableSSHCA = true;
              };
            }
          ];
      };
    };
  };
}
