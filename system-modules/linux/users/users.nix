# System-level user configuration (NixOS).
#
# Role data — groups, descriptions, trust — lives in nixSpaceLib.users so that
# Linux and Darwin read one registry rather than parallel copies. This file
# holds only what is NixOS-specific.
#
# SECRETS ARE NOT IMPORTED HERE. An earlier version imported the user's
# yubi-age, git-ssh, and vpn secret modules from a path relative to itself,
# which only resolved when this file lived in the userspace tree. The library
# cannot reach a consumer's secrets, so those imports belong in the consumer's
# configuration.nix, gated on the same tags.
{
  config,
  lib,
  nixSpaceAttrs,
  nixSpaceLib,
  pkgs,
  ...
}:
let
  inherit (nixSpaceLib) users;
  inherit (nixSpaceLib.tags) hasTag;
  attrs = nixSpaceAttrs;
  isTagged = tag: hasTag tag attrs.tags;
in
{
  users.users.${attrs.user} = {
    isNormalUser = true;
    description = users.description attrs;
    extraGroups = users.groups attrs;
    openssh.authorizedKeys.keys = lib.optionals (isTagged "ssh-user") attrs.sshPubKeys;
  };

  nix.settings.trusted-users = lib.mkIf (users.isTrusted attrs) (lib.mkAfter [ attrs.user ]);

  services = {
    pcscd.enable = isTagged "yubi-age-user" || isTagged "gpg-user";
  }
  // lib.optionalAttrs (isTagged "yubi-age-user") {
    udev.packages = [ pkgs.yubikey-personalization ];
  };

  assertions = [
    {
      assertion = !(isTagged "vm-user") || config.virtualisation.libvirtd.enable;
      message = ''
        The vm-user tag grants membership in the libvirtd group, but libvirtd
        is not enabled on this host. Add the virtualisation tag, or drop
        vm-user.
      '';
    }
  ];
}
