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
    };

    # OIDC issuer for the kanidm-backed provisioner.
    oidcIssuer = null;

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
