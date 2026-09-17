# System-level user configuration (NixOS).
#
# Role data (groups, descriptions, trust) lives in nixSpaceLib.users so that
# Linux and Darwin read one registry rather than maintaining parallel copies.
# This file holds only what is NixOS-specific.
{
  config,
  lib,
  nixSpaceAttrs,
  nixSpaceLib,
  pkgs,
  ...
}:
let
  inherit (nixSpaceLib) users hasTag;
  attrs = nixSpaceAttrs;
  isTagged = tag: hasTag tag attrs.tags;

  # Secret modules are colocated with the user. Under flakes these paths
  # resolve against the store copy of the tree, so an untracked file here
  # fails as "does not exist" even though it is present in the worktree.
  userSecrets = ./. + "/${attrs.user}/secrets";
in
{
  imports =
    lib.optionals (isTagged "yubi-age-user") [ (userSecrets + "/yubi-age.nix") ]
    ++ lib.optionals (isTagged "git-ssh-user") [ (userSecrets + "/git-ssh.nix") ]
    ++ lib.optionals (isTagged "vpn-user") [ (userSecrets + "/p22-vpn.nix") ];

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
