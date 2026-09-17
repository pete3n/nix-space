# nix-darwin system-module entry point.
{ ... }:
{
  imports = [
    ./cross-platform
    ./darwin
  ];
}
