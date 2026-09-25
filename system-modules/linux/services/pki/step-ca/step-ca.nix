# step-ca runs as an intermediate signed once by the domain's offline root
# (P22-CA), so every certificate it issues chains under a root the domain already
# trusts.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.services.step-ca;
  hostProvisioner = cfg.ssh.hostProvisioner;

  # The only names and addresses any cert from this CA may carry, shaped as a
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

  # Elevated identities are named `<user>-adm`. The templates below use the
  # suffix to keep each identity on its own provisioner.
  elevatedSuffix = "-adm";

  # The start of every user-cert template. It stops anything that is not a user
  # cert, and reads the login name kanidm put in the token.
  userTemplateHead = ''
    {{- if ne .Type "user" }}{{ fail "this provisioner signs SSH user certificates only" }}{{ end -}}
    {{- $user := .Token.preferred_username | default "" -}}
    {{- if not $user }}{{ fail "the kanidm token has no preferred_username" }}{{ end -}}
  '';

  # Refuses a token whose kanidm login is too old. kanidm reuses a browser
  # session without asking for the passkey again, and its token says when you
  # really logged in (`auth_time`). A token with no `auth_time` counts as
  # infinitely old, so it's refused too. kanidm and step-ca share a clock
  # on the Identity Node, so there's no skew to allow for.
  loginAgeCheck =
    provisioner:
    lib.optionalString (provisioner.maxLoginAge != null) ''
      {{- $loginAge := sub (now | unixEpoch | int64) (.Token.auth_time | default 0 | int64) -}}
      {{- if gt $loginAge ${toString provisioner.maxLoginAge} }}{{ fail "your kanidm login is more than ${toString provisioner.maxLoginAge} seconds old. Log out of kanidm (or use a private window) and try again" }}{{ end -}}
    '';

  # The end of every user-cert template: the stock template, except that the
  # principals are the ones worked out above instead of the ones asked for.
  userTemplateBody = ''
    {
    	"type": {{ toJson .Type }},
    	"keyId": {{ toJson $user }},
    	"principals": {{ toJson $principals }},
    	"extensions": {{ toJson .Extensions }},
    	"criticalOptions": {{ toJson .CriticalOptions }}
    }'';

  # A principal is "<group>/<login>", e.g. "p22-ssh/pete". A host lets login L
  # in when the cert carries "<g>/L" for a group g the host accepts. So one
  # principal says both who you are and which group lets you in. A cert never
  # carries a bare login name, so a host with no principals setup lets no one in.
  #
  # The separator is "/" because the CA-wide name policy sorts principals by
  # kind. "p22-ssh:pete" looks like a URL ("p22-ssh:" as its scheme), and URL
  # principals are always refused in user certs. identity-login's principals
  # script must use the same separator.
  userTemplate =
    provisioner:
    let
      groupsClaim = ".Token.${provisioner.groupsClaim}";
      adminGroup = provisioner.adminGroup;
    in
    if provisioner.kind == "standard" then
      ''
        ${userTemplateHead}
        ${loginAgeCheck provisioner}
        {{- if hasSuffix "${elevatedSuffix}" $user }}{{ fail "elevated identities use the elevated provisioner" }}{{ end -}}
        {{- $principals := list -}}
        {{- range (default (list) ${groupsClaim}) }}{{ if ne . "${adminGroup}" }}{{ $principals = append $principals (printf "%s/%s" . $user) }}{{ end }}{{ end -}}
        {{- if not $principals }}{{ fail "not a member of any SSH group" }}{{ end -}}
        ${userTemplateBody}
      ''
    else
      ''
        ${userTemplateHead}
        ${loginAgeCheck provisioner}
        {{- if not (hasSuffix "${elevatedSuffix}" $user) }}{{ fail "only elevated (${elevatedSuffix}) identities use this provisioner" }}{{ end -}}
        {{- if not (has "${adminGroup}" (default (list) ${groupsClaim})) }}{{ fail "not a member of ${adminGroup}" }}{{ end -}}
        {{- $principals := list (printf "${adminGroup}/%s" $user) -}}
        ${userTemplateBody}
      '';

  # One OIDC provisioner entry in ca.json.
  userProvisionerEntry = provisioner: {
    type = "OIDC";
    inherit (provisioner) name configurationEndpoint listenAddress;
    clientID = provisioner.clientId;
    # A public kanidm client has no secret. step-ca publishes this value to
    # every client anyway, so it could never have been a secret.
    clientSecret = "";
    claims = {
      enableSSHCA = true;
      defaultUserSSHCertDuration = provisioner.defaultCertDuration;
      maxUserSSHCertDuration = provisioner.certDuration;
    };
    options = {
      ssh.template = userTemplate provisioner;
      # An OIDC provisioner would otherwise also hand out TLS certs for the
      # login's email address. These provisioners are for SSH only.
      x509.template = ''{{ fail "this provisioner signs SSH user certificates only" }}'';
    };
  };

  # step-ca reads each OIDC provisioner's discovery document when it starts,
  # and won't start at all if it can't. On the Identity Node that's a trap:
  # kanidm serves its discovery document with a TLS cert that only this
  # step-ca can renew. If the cert has expired (the node was off for days) or
  # is still the NixOS placeholder (a fresh install), step-ca would never
  # start, so the cert could never be renewed.
  #
  # So step-ca checks first. If a discovery document can't be read, it starts
  # without the kanidm user-cert provisioners. ACME and host certs keep
  # working, lego renews kanidm's cert, and step-ca then restarts with the
  # full config (see `rejoinStepCa`). Only user certs wait. With kanidm on
  # another host there's no rejoin hook: restart step-ca by hand.
  #
  # The fallback config is the full one minus the user provisioners.
  fallbackConfigFile = (pkgs.formats.json { }).generate "ca-fallback.json" (
    config.services.step-ca.settings
    // {
      address = "${cfg.address}:${toString cfg.port}";
      authority = config.services.step-ca.settings.authority // {
        provisioners = lib.filter (
          provisioner: provisioner.type != "OIDC"
        ) config.services.step-ca.settings.authority.provisioners;
      };
    }
  );

  # Marks a step-ca that started with the fallback config. It lives in
  # step-ca's runtime directory, so it's gone whenever step-ca stops.
  fallbackMarker = "/run/step-ca/fallback";

  startStepCa = pkgs.writeShellApplication {
    name = "step-ca-start";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      config=/etc/smallstep/ca.json
      for url in ${
        lib.escapeShellArgs (map (provisioner: provisioner.configurationEndpoint) cfg.ssh.userProvisioners)
      }; do
        # The same trust store step-ca uses. A TLS failure isn't retried, so
        # an expired cert falls back at once. The retries are for a kanidm
        # that's still coming up.
        if ! curl --silent --show-error --fail --output /dev/null \
          --cacert /etc/ssl/certs/ca-certificates.crt \
          --max-time 5 --retry 4 --retry-delay 2 --retry-connrefused "$url"; then
          echo "can't read $url, so starting WITHOUT the kanidm user-cert provisioners" >&2
          config=${fallbackConfigFile}
          touch ${fallbackMarker}
          break
        fi
      done
      exec ${config.services.step-ca.package}/bin/step-ca "$config" ${lib.escapeShellArgs config.services.step-ca.extraArgs} \
        --password-file "$CREDENTIALS_DIRECTORY/intermediate_password"
    '';
  };

  # Runs each time kanidm (re)starts, which includes after its cert renews. A
  # step-ca in fallback restarts, and this time the discovery check passes.
  rejoinStepCa = pkgs.writeShellScript "step-ca-rejoin" ''
    if [ -e ${fallbackMarker} ]; then
      ${pkgs.systemd}/bin/systemctl --no-block try-restart step-ca.service
    fi
  '';
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
        `p22-ca.crt` already installed in the domain trust store; step-ca
        publishes it as the chain root. A public cert, so a store path is fine.
      '';
    };

    intermediateCertFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        The intermediate certificate (public), signed once by the offline root.
        A public cert, so a committed store path is fine - the matching private
        key is a secret (see `intermediateKeyFile`).
      '';
    };

    intermediateKeyFile = lib.mkOption {
      type = lib.types.path;
      example = lib.literalExpression ''config.age.secrets."step-ca/intermediate.key".path'';
      description = ''
        Runtime path to the intermediate private key. Supply an agenix/sops
        target, not a path literal (a literal is copied world-readable into the
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
          provisioner. null leaves both provisioners out.

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
          Runtime path to the SSH USER CA private key (agenix target). The
          `userProvisioners` sign with it.
        '';
      };

      userProvisioners = lib.mkOption {
        default = [ ];
        description = ''
          OIDC provisioners that sign SSH user certificates after a kanidm
          login (`step ssh login --provisioner <name>`). Each one pairs with a
          public kanidm OAuth2 client, which decides who can get a token at all.

          A `standard` provisioner signs everyday certs, one principal per SSH
          group the person is in. An `elevated` provisioner signs short admin
          certs for `-adm` identities only. Each refuses the other kind of
          identity, so an admin cert can never come from the long-lived one.
        '';
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.str;
                example = "kanidm";
                description = "Provisioner name, passed as `step ssh login --provisioner`.";
              };

              kind = lib.mkOption {
                type = lib.types.enum [
                  "standard"
                  "elevated"
                ];
                description = "Which identities this provisioner signs for, and how.";
              };

              clientId = lib.mkOption {
                type = lib.types.str;
                example = "step-ca";
                description = "The kanidm OAuth2 client's name. Read it from the domain descriptor.";
              };

              configurationEndpoint = lib.mkOption {
                type = lib.types.str;
                description = "That client's OIDC discovery URL. Read it from the domain descriptor.";
              };

              certDuration = lib.mkOption {
                type = lib.types.str;
                example = "16h";
                description = "The longest cert this provisioner will sign.";
              };

              defaultCertDuration = lib.mkOption {
                type = lib.types.str;
                example = "12h";
                description = "The lifetime a cert gets when the login asks for none.";
              };

              groupsClaim = lib.mkOption {
                type = lib.types.str;
                default = "ssh_groups";
                description = ''
                  The token claim that lists the person's groups. kanidm fills it
                  from a claim map on the OAuth2 client.
                '';
              };

              adminGroup = lib.mkOption {
                type = lib.types.str;
                example = "admins";
                description = ''
                  The group that marks Elevated identities. A standard cert never
                  carries it, and an elevated cert requires it. Read it from the
                  domain descriptor.
                '';
              };

              maxLoginAge = lib.mkOption {
                type = lib.types.nullOr lib.types.ints.positive;
                default = null;
                example = 300;
                description = ''
                  The oldest kanidm login, in seconds, this provisioner signs
                  for. kanidm reuses a browser session without asking for the
                  passkey again, so with no limit a cert can come from a login
                  hours old. `null` means no limit.
                '';
              };

              listenAddress = lib.mkOption {
                type = lib.types.str;
                default = "127.0.0.1:10000";
                description = ''
                  Where `step ssh login` listens for the browser coming back from
                  kanidm. It must match one of the client's redirect URLs.
                '';
              };
            };
          }
        );
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
      inherit (cfg)
        address
        port
        openFirewall
        intermediatePasswordFile
        ;

      # ca.json. step-ca chains our intermediate under the offline root, serves
      # ACME for internal TLS, and signs SSH host+user certificates. The
      # provisioners are ACME, the two SSH host-cert ones, and the kanidm-backed
      # user-cert ones.
      settings = {
        root = cfg.rootCertFile;
        crt = cfg.intermediateCertFile;
        key = cfg.intermediateKeyFile;
        dnsNames = [ cfg.fqdn ];

        # Log every request to the journal. Without this, step-ca logs nothing
        # about requests at all, so a refused cert gives the client only a
        # generic error and there's no record of what was signed.
        logger.format = "text";

        # SSH certificate authority: distinct host and user CA keys.
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
        # User certs need an `ssh.user` rule too. Once there's a host rule,
        # step-ca refuses every user cert unless user certs have rules of
        # their own ("not allowed to sign SSH user certificates when SSH host
        # certificate policy is active").
        #
        # The rule lets any plain principal through. Principals are matched
        # as whole names, and ours ("p22-ssh/pete") are built for each
        # person, so there's no narrower pattern to write. The templates are
        # what limit user certs: `hosts` refuses them, and each user
        # provisioner builds the principals itself and refuses the wrong
        # identities. With no `email` rule, a principal that looks like an
        # email address is still refused.
        authority.policy = {
          x509.allow = domainNames;
          ssh.host.allow = domainNames;
          # Singular, like `dns` and `ip`. step-ca quietly ignores keys it
          # doesn't know, and `principals` left user certs with no rules.
          ssh.user.allow.principal = [ "*" ];
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
          ]
          ++ map userProvisionerEntry cfg.ssh.userProvisioners;
      };
    };

    systemd.services = lib.mkIf (cfg.ssh.userProvisioners != [ ]) (
      lib.mkMerge [
        {
          step-ca.serviceConfig = {
            # Replaces the NixOS module's command with the launcher above. The
            # empty entry clears the command from step-ca's own unit file.
            ExecStart = lib.mkForce [
              ""
              "${startStepCa}/bin/step-ca-start"
            ];
            RuntimeDirectory = "step-ca";
          };
        }

        # When kanidm runs on this same host, wait for it, so the discovery
        # check doesn't catch it still starting.
        (lib.mkIf config.services.kanidm.server.enable {
          step-ca = {
            wants = [ "kanidm.service" ];
            after = [ "kanidm.service" ];
          };
          # "+" runs it as root, which systemctl needs.
          kanidm.serviceConfig.ExecStartPost = [ "+${rejoinStepCa}" ];
        })

        # lego tries to renew once at boot. On the CA's own host, make it wait
        # for step-ca, or that try fails and a fallback step-ca waits a day for
        # the next one.
        (lib.mapAttrs' (
          cert: _:
          lib.nameValuePair "acme-order-renew-${cert}" {
            wants = [ "step-ca.service" ];
            after = [ "step-ca.service" ];
          }
        ) config.security.acme.certs)
      ]
    );
  };
}
