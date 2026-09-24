# Domain descriptor registry (ADR-0005).
#
# Every value that differs between Identity Domains — the Lab (p22.lan) and the
# Production org network (nxs.lan) — lives here as data, so the same modules
# deploy to both by swapping which descriptor they read. This is the single
# place a per-domain fact is written; modules never hardcode a domain.
#
# Scalars only: names, URLs, addresses. Key material (CA certs/keys, SSH CA
# keys) is NOT stored here — public certs are committed files and private keys
# are agenix secrets, both referenced by the consuming host. See ADR-0008.
#
# Started at Step 2 (step-ca) with only the fields step-ca consumes; it grows as
# later steps (kanidm OIDC, VPN, groups) need more per-domain values.
{ ... }:
{
  "p22.lan" = {
    # kanidm's domain / WebAuthn RP-ID. A bare `.p22` is not a valid RP-ID
    # (ADR-0005), so the identity zone is the registrable `p22.lan`.
    domain = "p22.lan";
    rpId = "p22.lan";

    # The certificate authority for this domain. The root is the existing,
    # offline P22-CA (its cert is already trusted fleet-wide); step-ca runs as
    # an online intermediate signed by it (ADR-0008).
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
    };

    # OIDC issuer for the kanidm-backed provisioner. null until Step 3 stands
    # kanidm up; step-ca's user/elevated cert flow (ADR-0001/0003) waits on it.
    oidcIssuer = null;

    # Identity Nodes of this domain, keyed by hostname. Numbered to allow an HA
    # set later (idm2, …). The infra VLAN has no DHCP, so addresses are static.
    nodes = {
      idm1 = {
        fqdn = "idm1.p22.lan";
        address = "192.168.1.11";
      };
    };
  };
}
