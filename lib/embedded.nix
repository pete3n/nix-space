# Embedded platform registry.
#
# `embeddedTarget` is the top-level discriminator for embedded systems.
# Embedded systems have unique hardware-specific considerations.
#
# Each target here has a corresponding implementation module (raspberry-pi ->
# pi.nix). Adding a target means adding to validTargets and a corresponding module.
{ lib, self }:
{
  validTargets = [
    "raspberry-pi"
    # "riscv"  # Not yet implemented
  ];

  # Map an embeddedTarget to the library namespace implementing it.
  implFor =
    target:
    let
      implMap = {
        "raspberry-pi" = self.pi;
      };
    in
    implMap.${target}
      or (throw "embedded.implFor: no implementation for embeddedTarget '${toString target}'. Known: ${lib.concatStringsSep ", " (builtins.attrNames implMap)}");
}
