# idm1 public CA artifacts

Non-secret public files referenced (as store paths) by `nix-homes` 
`hosts/idm1/configuration.nix` and the `step-ca` module. Private counterparts 
are agenix secrets under `../secrets/step-ca/` (see `../secrets/secrets.nix`).

Required files (the flake will not evaluate until they exist):

- `p22-intermediate.crt` - the intermediate certificate, signed once by the
  offline P22-CA root key. Public.
- `ssh_user_ca.pub` - SSH **user** CA public key. Hosts trust it via
  `TrustedUserCAKeys`. Public.
- `ssh_host_ca.pub` - SSH **host** CA public key. Clients trust it to retire
  `known_hosts`. Public.
- `hosts-provisioner.pub.json` - public key of step-ca's JWK `hosts`
  provisioner (manually-signed first host certificate). Public.
- `hosts-provisioner.key.jwe` - that provisioner's private key, encrypted with
  a password the admin keeps.
