# Directory hook for remote build modules.
{ ... }:
{
  imports = [
    ./build-host.nix
    ./remote-builders.nix
  ];
}
