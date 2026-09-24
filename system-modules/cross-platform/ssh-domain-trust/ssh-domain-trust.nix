# SSH domain trust, client side. This host's ssh client trusts an Identity
# Domain's SSH Host CA, so any Domain host showing a valid host certificate is
# recognised without a per-host `known_hosts` entry or a first-connect prompt
# (ADR-0003, ADR-0009).
#
# Cross-platform (NixOS and nix-darwin): it only writes the system-wide
# known_hosts and ssh_config, which both provide.
#
# It also canonicalizes short names. Host certificates carry the host's FQDN
# (e.g. black8.p22.lan), not its short name, so `ssh black8` would not match
# the cert. With canonicalization the client first tries `black8.<domain>`,
# and uses that name when it resolves. If it doesn't resolve, ssh uses the
# short name as before, so nothing that works today stops working.
#
# Deliberately NOT here: trusting the SSH USER CA (sshd's TrustedUserCAKeys).
# That waits for Step 3, which maps kanidm groups to logins.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.ssh.domainTrust;
in
{
  options.nixSpace.ssh.domainTrust = {
    domains = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      example = lib.literalExpression ''
        lib.optional (hasTag "p22" tags) nixSpaceLib.domainDescriptor."p22.lan"
      '';
      description = ''
        Domain descriptors (ADR-0005) whose SSH Host CA this host trusts.
        Each needs `domain`, `ca.allowedDomains` and
        `ca.sshHostCAPublicKeyFile`. Empty (the default) changes nothing.
      '';
    };
  };

  config = lib.mkIf (cfg.domains != [ ]) {
    # One @cert-authority line per Domain, limited to the Domain's own names.
    # A host cert is only accepted for names the CA is allowed to issue, so a
    # Domain's CA can never vouch for, say, github.com.
    programs.ssh.knownHosts = lib.listToAttrs (
      map (
        descriptor:
        lib.nameValuePair "${descriptor.domain}-ssh-host-ca" {
          certAuthority = true;
          hostNames = descriptor.ca.allowedDomains;
          publicKeyFile = descriptor.ca.sshHostCAPublicKeyFile;
        }
      ) cfg.domains
    );

    # mkBefore: in ssh_config, a line written after a `Host` block belongs to
    # that block. Going first keeps these options global.
    #
    # MaxDots 0: only single-word names like `black8` are tried with the
    # Domain suffix. Names that already have a dot (github.com, black8.p22)
    # are left alone.
    programs.ssh.extraConfig = lib.mkBefore ''
      CanonicalizeHostname yes
      CanonicalDomains ${lib.concatMapStringsSep " " (descriptor: descriptor.domain) cfg.domains}
      CanonicalizeMaxDots 0
      CanonicalizeFallbackLocal yes
    '';
  };
}
