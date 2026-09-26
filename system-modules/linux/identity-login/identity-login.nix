# Identity login: people from the Identity Domain log in to this host, and
# exist here as kanidm accounts.
#
# Two ways to log in, both ending in the same account checks:
#   a. Everyday: a YubiKey SSH key (sk-ssh-ed25519) stored on the person's
#      kanidm account. sshd asks kanidm-unixd for the account's keys, and
#      kanidm-unixd caches them, so logins keep working while kanidm is
#      down. For kanidm accounts, sshd also demands the key's PIN, not
#      just a touch. So `ssh host` is a PIN and a touch, with no browser.
#   b. A short-lived SSH user cert from step-ca, after a kanidm browser
#      login. sshd trusts the domain's SSH User CA and asks a tiny local
#      script which cert principals may log in as a user. The script
#      answers "<group>/<login>" for each group this host accepts, so the
#      cert must name both the person and an accepted group.
#
# Either way, kanidm-unixd makes kanidm accounts (like `pete-adm`) exist on
# this host, PAM refuses kanidm accounts outside the accepted groups, and
# members of the admin group get passwordless sudo. The PIN (or, for a
# cert, the fresh passkey login) is the real check.
#
# Local accounts are untouched. A local user who is also a kanidm person (the
# interim `pete`) still logs in as the local account, as long as the kanidm
# person has no POSIX attributes.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.identity.login;
  descriptor = cfg.domain;

  # sshd runs this for every certificate login, passing the login name. Each
  # line it prints is a principal that may log in as that user. The "/" must
  # match the principals step-ca's user templates build.
  principalsScript = ''
    #!${pkgs.runtimeShell}
    login="$1"
    for group in ${lib.escapeShellArgs cfg.acceptGroups}; do
      printf '%s/%s\n' "$group" "$login"
    done
  '';

  # sshd runs this to fetch a login's SSH keys from kanidm. A local account
  # that overrides a kanidm account of the same name gets no kanidm keys:
  # otherwise the kanidm person's YubiKey would open the local account.
  authorizedKeysScript = ''
    #!${pkgs.runtimeShell}
    login="$1"
    for local_account in ${lib.escapeShellArgs cfg.localAccountOverrides}; do
      [ "$login" = "$local_account" ] && exit 0
    done
    exec ${config.security.wrapperDir}/kanidm_ssh_authorizedkeys "$login"
  '';
in
{
  options.nixSpace.identity.login = {
    enable = lib.mkEnableOption "logins from the Identity Domain (SSH user certs and kanidm accounts)";

    domain = lib.mkOption {
      type = lib.types.attrs;
      example = lib.literalExpression ''nixSpaceLib.domainDescriptor."p22.lan"'';
      description = ''
        The domain descriptor to accept people from. Needs `idm.origin`,
        `groups.admins` and `ca.sshUserCAPublicKeyFile`.
      '';
    };

    acceptGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      example = [
        "p22-ssh"
        "admins"
      ];
      description = ''
        kanidm groups whose members may log in here. Include the domain's
        admin group to allow elevated sessions. Granting a person access is
        then a kanidm group change, never an edit here.
      '';
    };

    localAccountOverrides = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "pete" ];
      description = ''
        Local accounts (in /etc/passwd) that win over a kanidm account of the
        same name on this host. kanidm-unixd otherwise answers first, so a
        kanidm person with POSIX attributes would hide the local account.
        For a host whose own user hasn't moved to kanidm yet.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = config.nixSpace.services.kanidm-server.package;
      defaultText = lib.literalExpression "config.nixSpace.services.kanidm-server.package";
      example = lib.literalExpression "pkgs.kanidm_1_11";
      description = ''
        The kanidm release for kanidm-unixd. Defaults to the server's on an
        Identity Node. Other hosts must set it, to the server's release.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh = {
      settings = {
        TrustedUserCAKeys = "${descriptor.ca.sshUserCAPublicKeyFile}";
        AuthorizedPrincipalsCommand = "/etc/ssh/authorized-principals %u";
        AuthorizedPrincipalsCommandUser = "nobody";
        # Replaces the kanidm module's command, which asks kanidm directly.
        AuthorizedKeysCommand = lib.mkIf (cfg.localAccountOverrides != [ ]) (
          lib.mkForce "/etc/ssh/authorized-keys-kanidm %u"
        );
      };

      # A YubiKey key signs with a touch alone unless the server asks for
      # the PIN too. Only kanidm accounts must use the PIN. Asking every
      # login would lock out a local account whose older YubiKey key was
      # made without a PIN. Non-YubiKey keys and certs ignore this setting.
      extraConfig = lib.mkAfter ''
        Match Group ${lib.concatStringsSep "," cfg.acceptGroups}
          PubkeyAuthOptions verify-required
        Match All
      '';
    };

    # A copied file, not a store symlink: sshd refuses a command unless it and
    # every directory above it belong to root, which /nix/store does not.
    environment.etc."ssh/authorized-keys-kanidm" = lib.mkIf (cfg.localAccountOverrides != [ ]) {
      mode = "0555";
      text = authorizedKeysScript;
    };

    environment.etc."ssh/authorized-principals" = {
      mode = "0555";
      text = principalsScript;
    };

    services.kanidm = {
      # mkDefault so an Identity Node's server setting wins without a clash.
      package = lib.mkDefault cfg.package;
      client.settings.uri = descriptor.idm.origin;
      unix = {
        enable = true;
        # sshd looks up a kanidm account's SSH keys through kanidm-unixd.
        sshIntegration = true;
        settings = {
          kanidm = {
            pam_allowed_login_groups = cfg.acceptGroups;
            allow_local_account_override = cfg.localAccountOverrides;
          };
          # Plain names ("pete-adm") instead of kanidm's default of
          # "pete-adm@p22.lan", so they match the login in the cert principal.
          uid_attr_map = "name";
          gid_attr_map = "name";
          # The home directory itself is /home/<name>, not kanidm's default of
          # /home/<uuid> with the name as a symlink. People keep their LDAP
          # name and uid, so kanidm adopts the /home/<name> they already have.
          # No alias: kanidm's default adds /home/<name>@<domain> as a
          # symlink and reports it as the home, so $HOME would carry the
          # domain.
          home_attr = "name";
          home_alias = "none";
          # A new home starts with the usual dotfiles, as under pam_mkhomedir.
          use_etc_skel = true;
          default_shell = "/run/current-system/sw/bin/bash";
        };
      };
    };

    security.sudo.extraRules = [
      {
        groups = [ descriptor.groups.admins ];
        commands = [
          {
            command = "ALL";
            options = [ "NOPASSWD" ];
          }
        ];
      }
    ];

    assertions = [
      {
        assertion = config.services.openssh.enable;
        message = "nixSpace.identity.login needs services.openssh.enable.";
      }
    ];
  };
}
