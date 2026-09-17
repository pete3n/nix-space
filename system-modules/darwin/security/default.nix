# Directory hook for the darwin YubiKey U2F PAM module.
{ ... }:
{
  imports = [
    ./yk-pam-u2f.nix
  ];
}
