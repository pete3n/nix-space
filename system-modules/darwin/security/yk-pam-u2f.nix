# YubiKey U2F for sudo for nix-darwin.
#
# The system half of nixSpace.security.yubikey.u2f: this registers the PAM
# module, the home-manager side writes the credentials to
# ~/.config/Yubico/u2f_keys. Neither can see the other's configuration, which
# is what the yubi-u2f tag coordinates.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.security.yubikey.u2f;
in
{
  options.nixSpace.security.yubikey.u2f = {
    enable = lib.mkEnableOption "YubiKey U2F authentication for sudo";

    origin = lib.mkOption {
      type = lib.types.str;
      default = "pam://${config.networking.hostName}";
      defaultText = lib.literalExpression ''"pam://''${config.networking.hostName}"'';
      description = ''
        Origin string the credentials were enrolled against.

        Must match what was used at enrolment: pam_u2f compares it, and a
        mismatch rejects a working key with no indication that the origin is
        why. A fleet-wide value such as "pam://p22" lets one enrolment work
        on every host; the per-host default is the safer choice for a single
        machine.
      '';
    };

    appId = lib.mkOption {
      type = lib.types.str;
      default = cfg.origin;
      defaultText = lib.literalExpression "config.nixSpace.security.yubikey.u2f.origin";
      description = ''
        Application identifier, defaulting to the origin. Kept separate
        because pam_u2f treats them as distinct fields and enrolments made
        with only one set are common.
      '';
    };

    cue = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Print a prompt when waiting for a touch.

        Without it sudo appears to hang — the key is waiting and nothing says
        so, which is indistinguishable from a stuck terminal.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.pam_u2f ];

    # sufficient, not required: the key satisfies authentication on its own,
    # and a missing or unplugged key falls through to the password rather
    # than locking sudo out entirely.
    security.pam.services.sudo_local.text = ''
      auth       sufficient     ${pkgs.pam_u2f}/lib/security/pam_u2f.so origin=${cfg.origin} appid=${cfg.appId}${lib.optionalString cfg.cue " cue"}
    '';
  };
}
