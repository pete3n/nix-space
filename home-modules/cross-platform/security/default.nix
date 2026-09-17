# Directory hook for cross-platform user security modules.
{ ... }:
{
  imports = [
    ./gpg
    ./yubikey
  ];
}
