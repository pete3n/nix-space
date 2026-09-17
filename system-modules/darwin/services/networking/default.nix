# Directory hook for the darwin NFS mount module.
{ ... }:
{
  imports = [
    ./nfs-mount.nix
  ];
}
