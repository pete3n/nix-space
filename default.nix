# Directory hook for nixSpace lib.
{
  lib,
  nixpkgs-unstable,
  nixSpaceAttrs ? null,
}:
let
  nixSpaceLib = import ./lib { inherit lib; };
in
{
  inherit nixSpaceLib;
  overlays = import ./overlays {
    inherit
      lib
      nixSpaceLib
      nixpkgs-unstable
      nixSpaceAttrs
      ;
  };
  homeModules = ./home-modules;
  systemModules = ./system-modules;
  hosts = ./hosts;
}
