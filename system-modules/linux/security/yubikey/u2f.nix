# pam_u2f: settings shared by every service, and the credential mapping.
#
# WHAT THIS DOES NOT DO: it never sets security.pam.u2f.enable. That option
# only supplies the default for every service's u2f.enable, which is how the
# old module changed authentication system-wide. pam_u2f reads
# security.pam.u2f.settings regardless of the global enable, so settings live
# here and enabling happens per service in pam.nix. Policy is the only gate.
#
# CREDENTIALS ARE SYSTEM INPUT. The file pam_u2f reads is consulted by root
# inside the sudo/login stack, so it is rendered from the system configuration
# into /etc, not into a user's home. The lines are a key handle plus a public
# key: they identify a credential on the token and cannot authenticate without
# it, so the Nix store is an acceptable home. What matters is integrity, and
# a root-owned file in /etc provides it.
#
# Revocation is one commit: remove a credential from the user's attrs, switch
# the fleet.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.security.yubikey;
  ucfg = cfg.u2f;

  central = ucfg.users != { };
  mappingPath = "/etc/u2f_mappings";
in
{
  options.nixSpace.security.yubikey.u2f = {
    enable = lib.mkEnableOption "pam_u2f settings and credential mapping";

    origin = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "pam://p22";
      description = ''
        Origin recorded at enrolment and checked at authentication.

        Baked into every credential produced by pamu2fcfg, so changing it
        invalidates every enrolled key on every host that shares it.

        pam_u2f's own default is pam://$HOSTNAME, which scopes a credential
        to one machine. A shared realm value means one enrolment works
        fleet-wide, which is the point of the central mapping below.
      '';
    };

    appid = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Legacy U2F application ID. Defaults to the origin.

        Only consulted for credentials registered through the older U2F API.
        Set it only when migrating an existing U2F deployment that used a
        different value.
      '';
    };

    cue = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Prompt the user to touch the key. Without it, authentication appears
        to hang while the key waits for a touch nothing asked for.
      '';
    };

    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = {
        pete = [
          "jPXIHluUKJNDbiCS...,FQlfOdBDXUlixODc...,es256,+presence"
          "4a218pdZXDWigFWV...,ftm749QLZ7sgH9IT...,es256,+presence"
        ];
      };
      description = ''
        Credentials per user, rendered to ${mappingPath} as

          user:credential:credential

        Each credential is one line of pamu2fcfg output with the leading
        "user:" removed. Enrol with the same origin the fleet uses:

          pamu2fcfg -n -o pam://<realm> -i pam://<realm>

        List EVERY key a user owns, backup token included: a token not on
        the line cannot authenticate. The fields are key handle, public key,
        COSE algorithm, and flags. `+presence` means touch only; `+pin` means
        the credential itself demands a PIN. Either flag can be overridden per
        service with pam.services.<name>.u2fPin, so touch-only enrolment is
        the flexible choice.

        Empty (the default) leaves pam_u2f on its per-user file,
        ~/.config/Yubico/u2f_keys. Prefer the central file: it is readable
        before an encrypted or network home is, and revocation is a commit.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && ucfg.enable) {
    assertions = [
      {
        assertion = ucfg.origin != null;
        message = ''
          nixSpace.security.yubikey.u2f.origin must be set explicitly.

          It is recorded in every credential at enrolment; changing it later
          invalidates every enrolled key. Choose deliberately:
            "pam://<realm>"   one enrolment valid fleet-wide
            "pam://<host>"    credentials scoped to this machine
        '';
      }
    ]
    ++ lib.mapAttrsToList (user: creds: {
      assertion = creds != [ ];
      message = ''
        nixSpace.security.yubikey.u2f.users.${user} is an empty list, so the
        mapping would list the user with no keys. pam_u2f treats that as "no
        key registered" and, depending on the stack, denies or falls through
        to a password. Enrol with `pamu2fcfg -n -o <origin> -i <origin>`.
      '';
    }) ucfg.users;

    security.pam.u2f.settings = {
      origin = ucfg.origin;
      appid = if ucfg.appid != null then ucfg.appid else ucfg.origin;
      inherit (ucfg) cue;
    }
    // lib.optionalAttrs central {
      authfile = mappingPath;
    };

    environment.etc.${lib.removePrefix "/etc/" mappingPath} = lib.mkIf central {
      mode = "0444";
      text = lib.concatLines (
        lib.mapAttrsToList (user: creds: "${user}:${lib.concatStringsSep ":" creds}") ucfg.users
      );
    };
  };
}
