# pam_rssh: sudo authenticated by a signature from the calling user's agent.
#
# This is what replaces the USB/IP hack. The problem USB/IP solved was "sudo
# in an SSH session needs a touch"; pam_rssh forwards the PAM request to the
# client-side agent as a signature request, so the key never leaves the
# machine it is plugged into, the remote receives a signature rather than a
# device, and the touch requirement on sk keys bounds what a compromised
# remote root can do with the forwarded agent to "while you are touching".
#
# It is enabled by policy, not here: any pam.services.<name>.sshAgent = true
# turns it on. This file only says where the authorised keys come from.
#
# TRUST BOUNDARY. The default key file is user-writable ~/.ssh/authorized_keys
# upstream, which lets any program the user runs grant itself sudo. NixOS
# already renders a ROOT-OWNED /etc/ssh/authorized_keys.d/<user> from
# users.users.<user>.openssh.authorizedKeys, so that is the default here.
# A user without declared keys has no file, and pam_rssh simply fails
# through to the next factor.
#
# Phase 3 replaces the file with a command — kanidm_ssh_authorizedkeys — so
# the key inventory moves to the identity provider without touching policy.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.security.yubikey;
  acfg = cfg.sshAgent;

  anySshAgent = lib.any (s: s.sshAgent) (lib.attrValues cfg.pam.services);
in
{
  options.nixSpace.security.yubikey.sshAgent = {
    keysFile = lib.mkOption {
      type = lib.types.str;
      # "\${user}" is a literal ${user}: pam_rssh expands it from PAM_USER.
      default = "/etc/ssh/authorized_keys.d/\${user}";
      description = ''
        authorized_keys file consulted for the user being authenticated.

        pam_rssh expands ''${user}, ''${service}, ''${tty}, ''${rhost} and
        ''${ruser} from the PAM items. Keep this root-owned; see the header.
        Ignored when keysCommand is set.
      '';
    };

    keysCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/current-system/sw/bin/kanidm_ssh_authorizedkeys";
      description = ''
        Command whose stdout is parsed as authorized_keys. It receives the
        username as its single argument. Set this once kanidm distributes
        keys; until then the file is the source of truth.
      '';
    };

    keysCommandUser = lib.mkOption {
      type = lib.types.str;
      default = "nobody";
      description = "User the keysCommand runs as. Unused without keysCommand.";
    };

    cue = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Print a prompt to touch the device. As with pam_u2f, without it the
        wait for a touch looks like a hang.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && anySshAgent) {
    security.pam.rssh = {
      enable = true;
      settings = {
        auth_key_file = acfg.keysFile;
        inherit (acfg) cue;
      }
      // lib.optionalAttrs (acfg.keysCommand != null) {
        authorized_keys_command = acfg.keysCommand;
        authorized_keys_command_user = acfg.keysCommandUser;
      };
    };
  };
}
