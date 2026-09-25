# Identity login: people from the Identity Domain log in to this host with a
# short-lived SSH user certificate, and exist here as kanidm accounts.
#
# Four pieces, all needed together:
#   1. sshd trusts the domain's SSH User CA.
#   2. sshd asks a tiny local script which cert principals may log in as a
#      given user. The script answers "<group>:<login>" for each group this
#      host accepts, so the cert must name both the person and an accepted
#      group. No server is contacted at connect time.
#   3. kanidm-unixd makes kanidm accounts (like `pete-adm`) exist on this
#      host, and PAM refuses kanidm accounts outside the accepted groups.
#   4. Members of the admin group get passwordless sudo. Their cert is
#      short-lived and cost a fresh passkey touch, which is the real check.
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
  # line it prints is a principal that may log in as that user.
  principalsScript = ''
    #!${pkgs.runtimeShell}
    login="$1"
    for group in ${lib.escapeShellArgs cfg.acceptGroups}; do
      printf '%s:%s\n' "$group" "$login"
    done
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

    package = lib.mkOption {
      type = lib.types.package;
      default = config.nixSpace.services.kanidm-server.package;
      defaultText = lib.literalExpression "config.nixSpace.services.kanidm-server.package";
      example = lib.literalExpression "pkgs.kanidm_1_8";
      description = ''
        The kanidm release for kanidm-unixd. Defaults to the server's on an
        Identity Node. Other hosts must set it, to the server's release.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh.settings = {
      TrustedUserCAKeys = "${descriptor.ca.sshUserCAPublicKeyFile}";
      AuthorizedPrincipalsCommand = "/etc/ssh/authorized-principals %u";
      AuthorizedPrincipalsCommandUser = "nobody";
    };

    # A copied file, not a store symlink: sshd refuses a command unless it and
    # every directory above it belong to root, which /nix/store does not.
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
        settings = {
          kanidm.pam_allowed_login_groups = cfg.acceptGroups;
          # Plain names ("pete-adm") instead of kanidm's default of
          # "pete-adm@p22.lan", so they match the login in the cert principal.
          uid_attr_map = "name";
          gid_attr_map = "name";
          home_alias = "name";
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
