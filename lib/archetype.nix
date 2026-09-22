# Archetype registry.
#
# An archetype is the SHAPE of a host: what a machine is *for*, above the
# hardware it runs on. Two hosts on identical hardware can be different
# archetypes — a workstation someone sits at, or a headless server that runs
# a service and has no one logged in.
#
# This is deliberately separate from `chassis` (which is hardware) and from
# `tags` (which are zero-or-more capabilities). An archetype is exactly one
# per host, and it decides things the other two cannot: whether a per-user
# home-manager desktop is built at all, and which baseline system module a
# host imports.
#
# Kept to a small, closed set on purpose. A new archetype is a real shape with
# its own baseline module, not a spelling of a tag.
{ lib, self }:
let
  archetypes = {
    workstation = {
      description = "A machine a person sits at: desktop, per-user home, graphical session.";
    };
    server = {
      description = "A headless host that runs the system plane. No per-user home, no desktop.";
    };
  };
in
{
  inherit archetypes;

  valid = builtins.attrNames archetypes;

  # The shape a host is assumed to be when its attrs file says nothing.
  # Every existing host is a workstation, so that is the default and no attrs
  # file has to change to keep meaning what it meant.
  default = "workstation";

  # Look up an entry, naming the valid set rather than throwing a bare
  # `attribute missing`. Mirrors hardware.lookup.
  lookup =
    name:
    archetypes.${name}
      or (throw "archetype.lookup: unknown archetype '${toString name}'. Must be one of: ${lib.concatStringsSep ", " (builtins.attrNames archetypes)}");

  isServer = name: name == "server";
  isWorkstation = name: name == "workstation";
}
