# Directory hook for the internal ACME client (TLS certs from step-ca) module.
{ ... }:
{
  imports = [ ./internal-acme.nix ];
}
