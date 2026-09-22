# Directory hook for archetype baseline modules.
#
# Each archetype module is imported unconditionally, the way every other
# module in this tree is, and self-gates on `nixSpaceAttrs.archetype`. A
# workstation host imports server.nix too — it just does nothing there.
{ ... }:
{
  imports = [
    ./server.nix
  ];
}
