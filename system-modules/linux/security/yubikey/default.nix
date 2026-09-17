# nixSpace.security.yubikey — NixOS.
#
# Human-factor policy for YubiKey-backed authentication: which PAM services
# accept a touch, a fingerprint, an ssh-agent signature, or a password, and
# where pam_u2f finds its credentials.
#
# Machine trust — step-ca, SSH host certificates, internal ACME — is
# deliberately NOT here. That belongs to a separate nixSpace.security.pki
# module, so the corporate deployment can swap either half independently.
#
# Location: system-modules/linux/security/yubikey. Linux-only: this sets
# services.pcscd, security.pam.services.<name>.rules, and systemd units.
# A nix-darwin implementation is later, separate work (nix-darwin manages
# only /etc/pam.d/sudo_local); nothing here is shared with it.
#
# Importing this directory enables nothing. The caller sets
# nixSpace.security.yubikey.enable and then the features it wants.
#
# Replaces the previous yk-*.nix set:
#   yk-u2f.nix                -> u2f.nix       (namespace moved, central mapping added)
#   yk-sshd.nix, yk-fprint.nix -> pam.nix       (policy; nixpkgs' rule stack does the ordering)
#   (new)                     -> ssh-agent.nix (pam_rssh: sudo inside an SSH session)
#   yk-usbip-server/client, yk-ssh.nix
#                             -> dropped. pam_rssh solves the same problem
#                                without sharing the device.
{ ... }:
{
  imports = [
    ./base.nix
    ./pam.nix
    ./ssh-agent.nix
    ./u2f.nix
  ];
}
