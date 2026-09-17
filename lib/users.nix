# System-level user role registry.
#
# One entry per user tag, holding every facet of that role together.
#
# `groups` is Linux-only because Darwin has no equivalent supplementary-group model.
# Darwin reads `description` and `trusted` and ignores `groups`.
{ lib, self }:
let
  roles = {
    git-ssh-user = {
      groups = [ "users" ];
      description = "User with git configuration and git ssh key.";
      trusted = false;
    };
    gpg-user = {
      groups = [ "users" ];
      description = "User with gpg configuration and system level gpg services.";
      trusted = false;
    };
    power-user = {
      groups = [
        "adbusers"
        "cdrom"
        "networkmanager"
        "users"
        "wheel"
      ];
      description = "Trusted user and sudoer with netman and adbuser membership.";
      trusted = true;
    };
    ssh-user = {
      groups = [ "users" ];
      description = "User is authorized SSH access with the assigned ssh keys.";
      trusted = false;
    };
    sudo-user = {
      groups = [
        "cdrom"
        "users"
        "wheel"
      ];
      description = "User with sudo (wheel) access.";
      trusted = false;
    };
    trusted-user = {
      groups = [ "users" ];
      description = "Add user to nix trusted users.";
      trusted = true;
    };
    vm-user = {
      groups = [
        "libvirtd"
        "users"
      ];
      description = "User with access to libvirt virtual machines.";
      trusted = false;
    };
    vpn-user = {
      groups = [ "users" ];
      description = "User with openvpn configuration for P22.";
      trusted = false;
    };
    yubi-age-user = {
      groups = [ "users" ];
      description = "User that uses a hardware Yubikey to manage age secrets.";
      trusted = false;
    };
  };

  # Completeness check, evaluated once when the library is constructed. Catches
  # a tag added to tag-registry.nix but never defined here.
  unmapped = lib.subtractLists (builtins.attrNames roles) self.tags.user;
  unknown = lib.subtractLists self.tags.user (builtins.attrNames roles);
in
lib.throwIf (unmapped != [ ])
  "users.roles: tag(s) in tags.user with no role entry: ${lib.concatStringsSep ", " unmapped}"
  (
    lib.throwIf (unknown != [ ])
      "users.roles: role entry for tag(s) not in tags.user: ${lib.concatStringsSep ", " unknown}"
      {
        inherit roles;

        # User tags actually present in this attrs.
        active = attrs: builtins.filter (tag: builtins.elem tag self.tags.user) attrs.tags;

        # Supplementary groups implied by the active roles. Linux only.
        groups = attrs: lib.unique (lib.concatMap (tag: roles.${tag}.groups) (self.users.active attrs));

        # Concatenated role descriptions, for users.users.<name>.description.
        # Note this lands in the GECOS field; it is informational only.
        description =
          attrs: lib.concatMapStringsSep "; " (tag: roles.${tag}.description) (self.users.active attrs);

        # Whether this user belongs in nix.settings.trusted-users.
        isTrusted = attrs: lib.any (tag: roles.${tag}.trusted) (self.users.active attrs);
      }
  )
