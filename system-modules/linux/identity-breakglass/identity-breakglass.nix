# Break-glass Account: a local `breakglass` account that works when the
# Identity Domain doesn't.
#
# Everyone else logs in through kanidm. If kanidm is down and a host's cache
# has nothing, or the kanidm setup itself is broken, nobody can get in. This
# account is the way back: it lives in /etc/passwd, its keys are written onto
# the host at deploy, and nothing about it asks kanidm.
#
# Only a short list of YubiKeys opens it: the Directory Administrators'
# Primary and Backup Keys, plus the sealed Safe Key. The list lives in the
# domain descriptor (`breakglass`), so every host gets the same one.
#
# Why each SSH key line starts with `verify-required`: kanidm accounts get
# "PIN and touch" from a `Match Group` rule in sshd (identity-login). This
# account is not in those groups, so without the option a YubiKey would open
# it with a touch alone, and a stolen key would be enough.
#
# Console login uses the same YubiKeys through pam_u2f, when the host has it
# (nixSpace.security.yubikey.u2f). The PIN is demanded there by the service's
# PAM policy (u2fPin), not here.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.identity.breakglass;
  keys = cfg.domain.breakglass;
  u2fOnHost = config.nixSpace.security.yubikey.enable && config.nixSpace.security.yubikey.u2f.enable;
in
{
  options.nixSpace.identity.breakglass = {
    enable = lib.mkEnableOption "the local break-glass account";

    domain = lib.mkOption {
      type = lib.types.attrs;
      example = lib.literalExpression ''nixSpaceLib.domainDescriptor."p22.lan"'';
      description = ''
        The domain descriptor whose `breakglass` list opens the account.
        Needs `breakglass.uid`, `breakglass.sshKeys` and
        `breakglass.u2fCredentials`.
      '';
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = "breakglass";
      description = ''
        The account's name. The Roster must never give a person this name,
        or kanidm's account would hide this one.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.name} = {
      isNormalUser = true;
      # The same uid on every host, so files it leaves behind (e.g. on NFS)
      # always belong to the same number.
      inherit (keys) uid;
      description = "Break-glass account (local, no kanidm)";
      # No password at all: only the YubiKeys below get in.
      hashedPassword = "!";
      openssh.authorizedKeys.keys = map (key: "verify-required ${key}") keys.sshKeys;
    };

    # The point of the account is fixing a broken host, so it gets sudo with
    # no second prompt. The PIN and touch at login were the check.
    security.sudo.extraRules = [
      {
        users = [ cfg.name ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    nixSpace.security.yubikey.u2f.users = lib.mkIf u2fOnHost {
      ${cfg.name} = keys.u2fCredentials;
    };

    assertions = [
      {
        assertion = keys.sshKeys != [ ];
        message = ''
          nixSpace.identity.breakglass is enabled, but the domain's
          breakglass.sshKeys is empty, so nobody could open the account.
        '';
      }
      {
        # Only YubiKey keys: a plain key file on a disk is exactly what a
        # break-glass account must not trust.
        assertion = lib.all (key: lib.hasPrefix "sk-" key) keys.sshKeys;
        message = ''
          Every key in the domain's breakglass.sshKeys must be a YubiKey key
          (sk-ssh-ed25519@openssh.com). Make them with
          `ssh-keygen -t ed25519-sk -O resident -O verify-required`.
        '';
      }
      {
        assertion = !u2fOnHost || keys.u2fCredentials != [ ];
        message = ''
          This host has pam_u2f, but the domain's breakglass.u2fCredentials is
          empty, so the account couldn't log in at the console.
        '';
      }
    ];
  };
}
