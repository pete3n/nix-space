# Directory hook for the identity login (SSH user certs + kanidm accounts) module.
{ ... }:
{
  imports = [ ./identity-login.nix ];
}
