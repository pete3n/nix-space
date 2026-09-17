# This is the top-level entry point for the nixSpace library.
# nixSpaceLib provides validation for top-level configuration
# attributes that manage both user and system level configuration.
#
{ lib }:
lib.makeExtensible (
  self:
  let
    callLib = path: import path { inherit lib self; };
  in
  {
    # Attrs provides three accessor functions based on source:
    #		fromAttrs		- an in-memory attrset
    #		fromFile		- one user@host.nix attrs file
    #		fromDir			- a directory of user@host.nix attrs files
    attrs = (callLib ./validate-attrs.nix) // {
      fromDir = callLib ./attrs-dir.nix;
    };

    # Contains platform specific helper functions for either NixOS or Nix-Darwin.
    platform = callLib ./platform.nix;

    # Hardware registry for hardware specific configuration.
    hardware = callLib ./hardware.nix;

    # Contains lists of all valid tags, tag conditions, and tag functions.
    tags = callLib ./tag-registry.nix;

    # Registers specific emdedded system modules.
    embedded = callLib ./embedded.nix;

    # Registers board specific configuration options for raspberry-pi.
    pi = callLib ./pi.nix;

    # Defines local and remote deployment types.
    deploy = callLib ./deploy.nix;

    # Defines system-level configuration for users.
    users = callLib ./users.nix;
  }
)
