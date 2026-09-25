# Domain and associated PKI configuration
{ ... }:
{
  "p22.lan" = {
    # kanidm's domain / WebAuthn RP-ID.
    domain = "p22.lan";
    rpId = "p22.lan";

    # The certificate authority for this domain. The root is the existing,
    # offline P22-CA; step-ca runs as an online intermediate signed by it.
    ca = {
      rootCn = "P22-CA";
      intermediateCn = "P22 Intermediate CA";
      # step-ca's own endpoints, served from the Identity Node.
      url = "https://idm1.p22.lan";
      acmeDirectory = "https://idm1.p22.lan/acme/acme/directory";
      # The only names/addresses any certificate from this domain's CA may
      # carry (TLS and SSH host certs). step-ca refuses anything else.
      allowedDomains = [ "*.p22.lan" ];
      allowedAddresses = [ "192.168.1.0/24" ];

      # The SSH Host CA's public key. Every host's ssh client trusts it
      # for this Domain's names (nixSpace.ssh.domainTrust).
      sshHostCAPublicKeyFile = ../hosts/idm1/pki/ssh_host_ca.pub;

      # The SSH User CA's public key. Hosts that accept kanidm logins trust it
      # (nixSpace.identity.login).
      sshUserCAPublicKeyFile = ../hosts/idm1/pki/ssh_user_ca.pub;
    };

    # kanidm, the directory. It shares idm1 with step-ca, which already holds
    # port 443, so kanidm listens on its own default port. Passkeys are bound
    # to rpId, not to this URL, so the URL can move later without re-enrolling.
    idm = {
      origin = "https://idm1.p22.lan:8443";
    };

    # The kanidm OAuth2 clients step-ca trusts for user certificates. The
    # standard one mints day-long certs, the elevated one hour-long admin certs.
    oidc = {
      standard = {
        clientId = "step-ca";
        configurationEndpoint = "https://idm1.p22.lan:8443/oauth2/openid/step-ca/.well-known/openid-configuration";
      };
      elevated = {
        clientId = "step-ca-elevated";
        configurationEndpoint = "https://idm1.p22.lan:8443/oauth2/openid/step-ca-elevated/.well-known/openid-configuration";
      };
    };

    # kanidm group names with a fixed meaning. `admins` holds the Elevated
    # (`-adm`) identities and gets sudo. `sshUsers` is everyday SSH access.
    groups = {
      admins = "admins";
      sshUsers = "p22-ssh";
    };

    # Identity Nodes of this domain, keyed by hostname. Numbered to allow an HA
    # set later (idm2, …). Assumes addresses are static.
    nodes = {
      idm1 = {
        fqdn = "idm1.p22.lan";
        address = "192.168.1.11";
      };
    };
  };
}
