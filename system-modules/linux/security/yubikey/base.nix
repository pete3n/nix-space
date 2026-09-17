# System prerequisites for a YubiKey used for authentication.
#
# The home-manager side (nixSpace.security.yubikey there) assumes pcscd is
# running and documents the socket path; this is where it is actually
# enabled, so the dependency is owned rather than presumed.
#
# FIDO/HID access needs no rule from us: systemd's 60-fido-id.rules runs the
# fido_id builtin, tags the device ID_SECURITY_TOKEN=1, and 70-uaccess grants
# the active seat an ACL. That covers local sessions. Inside an SSH session
# there is no seat and therefore no ACL, which is exactly why pam_u2f (root)
# works there but a user-level `ssh-add` of an sk key does not.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.security.yubikey;
in
{
  options.nixSpace.security.yubikey = {
    enable = lib.mkEnableOption "YubiKey-backed system authentication";

    pcscd = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run pcscd for the CCID interface (PIV, OpenPGP, age-plugin-yubikey).

        Not needed for FIDO2/U2F, which talks HID directly, but every host
        here also uses the smartcard applets. A host that only ever uses
        FIDO can turn it off.
      '';
    };

    pamtester = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install pamtester so a PAM stack can be exercised without a login:

          pamtester sudo "$USER" authenticate

        It lives here, not in home-manager, because it tests the SYSTEM stack.
        A misconfigured stack is otherwise discovered by losing sudo.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Defined only when true, so a host that disables it here and enables it
    # elsewhere does not produce a conflicting-definition error.
    services.pcscd.enable = lib.mkIf cfg.pcscd true;

    # 69-yubikey.rules: uaccess for the OTP/HID interface, needed by ykman and
    # ykpersonalize as a non-root user. Harmless where those are unused.
    services.udev.packages = [ pkgs.yubikey-personalization ];

    environment.systemPackages = [
      # pamu2fcfg is in pam_u2f: this is the enrolment tool, not the PAM
      # module (which nixpkgs loads by store path regardless).
      pkgs.pam_u2f
      pkgs.libfido2 # fido2-token: inspect and reset the FIDO applet
    ]
    ++ lib.optional cfg.pamtester pkgs.pamtester;
  };
}
