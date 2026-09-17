# Deployment modes: what artifact a configuration produces and how it reaches
# the target machine.

# TODO: `remote` does not yet say WHICH host. When needed, add an optional
# `deployHost` field defaulting to `host` (a derived default in load, not a
# constant in optionalAttrs), and make a null deployHost with
# deployMode = "remote" an error.
{ ... }:
{
  validModes = [
    "local" # build + activate on this machine
    "remote" # build here, activate over SSH (nixos-rebuild --target-host)
    "sd-image" # produce an SD image; dd to card
    "iso" # produce installer media
    "pxe" # netboot
  ];

  # Modes producing an artifact rather than activating a running system.
  mediaModes = [
    "sd-image"
    "iso"
  ];

  # Modes that deploy a whole system. Unavailable when isHomeAlone = true,
  # where the only output is a home-manager activation package.
  systemModes = [
    "sd-image"
    "iso"
    "pxe"
  ];

  # Modes only meaningful for an embedded target.
  embeddedOnlyModes = [ "sd-image" ];
}
