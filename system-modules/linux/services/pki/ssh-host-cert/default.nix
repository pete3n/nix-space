# Directory hook for the SSH host certificate (sshd presents + renews) module.
{ ... }:
{
  imports = [ ./ssh-host-cert.nix ];
}
