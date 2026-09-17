# Platform predicates over Nix system strings ("x86_64-linux", "aarch64-darwin").
#
# These are for flake-level code that runs before any `pkgs` exists.
# choosing between `nixosSystem` and `darwinSystem`, or deciding localSystem /
# crossSystem when constructing pkgs.
#
# For cross-compilation, Nixpkgs uses three platforms:
#   buildPlatform  - the machine running the build
#   hostPlatform   - the machine the result runs on (target host)
#   targetPlatform - only meaningful when building a compiler
#
# In nixSpace `system` maps to hostPlatform/crossSystem and
# `buildSystem` maps to buildPlatform/localSystem.
{ lib, self }:
{
  isPlatform = system: platform: lib.strings.hasSuffix "-${platform}" system;

  isLinux = system: self.platform.isPlatform system "linux";
  isDarwin = system: self.platform.isPlatform system "darwin";

  # True when the builder and the target differ — i.e. this is a cross build.
  isCross = { buildSystem, system, ... }: buildSystem != system;
}
