# Directory hook for cross-platform system modules.
{ ... }:
{
  imports = [
    ./nix-cache
    ./remote-builders
  ];
}
