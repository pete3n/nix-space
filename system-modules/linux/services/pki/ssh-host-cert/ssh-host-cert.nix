# SSH host certificate: sshd presents a certificate signed by the Domain's SSH
# Host CA, so clients that trust the CA need no per-host `known_hosts` entry.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.services.ssh-host-cert;
in
{
  options.nixSpace.services.ssh-host-cert = {
    enable = lib.mkEnableOption "an SSH host certificate from step-ca, renewed automatically";

    caUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://idm1.p22.lan";
      description = ''
        step-ca's URL. Read it from the domain descriptor, e.g.
        `(nixSpaceLib.domainDescriptor."p22.lan").ca.url`.
      '';
    };

    rootCertFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        The Domain's root certificate (public). Renewal uses it to check it is
        talking to the real CA before sending anything.
      '';
    };

    hostKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/ssh/ssh_host_ed25519_key";
      description = "The host private key the certificate is issued for.";
    };

    certFile = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.hostKeyFile}-cert.pub";
      defaultText = lib.literalExpression ''"''${hostKeyFile}-cert.pub"'';
      description = ''
        Where the host certificate lives. The operator puts the first cert here.
        The default is the path OpenSSH expects next to the key.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # A string path, not a store path: the cert is issued and renewed at runtime.
    services.openssh.settings.HostCertificate = cfg.certFile;

    systemd.services.ssh-host-cert-renew = {
      description = "Renew the SSH host certificate from step-ca";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      # Nothing to renew until the operator has put the first cert in place.
      unitConfig.ConditionPathExists = cfg.certFile;
      serviceConfig = {
        Type = "oneshot";
        # Kept narrow on purpose: this only needs to read the host key, write
        # the cert next to it, and tell sshd to reload.
        PrivateTmp = true;
        ProtectHome = true;
        NoNewPrivileges = true;
      };
      script = ''
        # Renew every day, not only near expiry. Each renewal is cheap, and the
        # host keeps nearly the full cert lifetime of slack if the CA goes away.
        ${lib.getExe pkgs.step-cli} ssh renew --force \
          --ca-url ${lib.escapeShellArg cfg.caUrl} \
          --root ${lib.escapeShellArg "${cfg.rootCertFile}"} \
          ${lib.escapeShellArg cfg.certFile} ${lib.escapeShellArg cfg.hostKeyFile}

        # sshd reads HostCertificate only at startup; a reload makes it pick up
        # the new cert without dropping open sessions.
        ${config.systemd.package}/bin/systemctl try-reload-or-restart sshd.service
      '';
    };

    systemd.timers.ssh-host-cert-renew = {
      description = "Daily SSH host certificate renewal";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        # Spread renewals so the fleet doesn't hit the CA all at once.
        RandomizedDelaySec = "1h";
        # Catch up on a renewal missed while the host was off.
        Persistent = true;
      };
    };
  };
}
