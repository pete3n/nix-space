# Baseline for the `server` archetype: a headless host that runs the system
# plane and has no one sitting at it.
#
# Imported on every Linux host but gated on the archetype attr, so it applies
# only where `archetype = "server"`. Everything here is `mkDefault` so a
# specific server can still override it in its own configuration.nix.
#
# The SSH posture matches ADR-0001: no agent forwarding anywhere, key-only,
# no root login. A server is reached over SSH, so openssh is on by default —
# unlike a workstation, where remote access is opt-in.
{
  config,
  lib,
  nixSpaceLib,
  nixSpaceAttrs,
  ...
}:
let
  isServer = nixSpaceLib.archetype.isServer nixSpaceAttrs.archetype;
in
{
  config = lib.mkIf isServer {
    services.openssh = {
      enable = lib.mkDefault true;
      settings = {
        PermitRootLogin = lib.mkDefault "no";
        PasswordAuthentication = lib.mkDefault false;
        KbdInteractiveAuthentication = lib.mkDefault false;
        # ADR-0001: agent forwarding is disabled everywhere. A remote host
        # never gets a live channel to a local YubiKey.
        AllowAgentForwarding = lib.mkDefault false;
        X11Forwarding = lib.mkDefault false;
      };
    };

    # A headless box has no browser to read it and no display to render it;
    # drop the big HTML manual from the closure. Man pages stay.
    documentation.nixos.enable = lib.mkDefault false;
  };
}
