# Module to configure internal ACME TLS certificates.
#
# A thin layer over NixOS `security.acme` (the lego client). It points lego at
# step-ca's ACME directory and sets the renewal margin to match step-ca's short
# certs. Each listed name gets its cert in /var/lib/acme/<name>/ (fullchain.pem,
# key.pem), which a service like kanidm or nginx then serves.
#
# lego must trust step-ca's own HTTPS. It uses the system trust store,
# so this module is only useful on a host that trusts the Domain root
# (security.pki.certificateFiles, which every p22 host already has).
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.services.internal-acme;
in
{
  options.nixSpace.services.internal-acme = {
    enable = lib.mkEnableOption "TLS certificates from the Domain's step-ca over ACME";

    directoryUrl = lib.mkOption {
      type = lib.types.str;
      example = "https://idm1.p22.lan/acme/acme/directory";
      description = ''
        step-ca's ACME directory. Read it from the domain descriptor:
        `(nixSpaceLib.domainDescriptor."p22.lan").ca.acmeDirectory`.
      '';
    };

    certs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "idm1.p22.lan" ];
      description = ''
        Names to get a certificate for, one cert each. Every name must resolve
        to this host (step-ca checks), and must be inside the Domain, or the
        CA's name policy refuses it.
      '';
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = "root@${config.networking.fqdnOrHostName}";
      defaultText = lib.literalExpression ''"root@''${config.networking.fqdnOrHostName}"'';
      description = ''
        ACME account contact. step-ca never sends mail. NixOS just requires
        one, so the default names the host itself.
      '';
    };

    validMinDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = ''
        Renew once fewer than this many days are left. With step-ca's 7-day
        ACME certs, a cert renews on day 4 or 5, which leaves about 3 days of
        slack if the CA is unreachable.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Open port 80 so step-ca can reach the http-01 challenge. Nothing
        listens there except while lego is running a challenge.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && cfg.certs != [ ]) {
    security.acme = {
      acceptTerms = true;
      defaults = {
        server = cfg.directoryUrl;
        inherit (cfg) email validMinDays;
        # lego's own short-lived listener answers the http-01 challenge.
        listenHTTP = ":80";
      };
      certs = lib.genAttrs cfg.certs (_name: { });
    };

    networking.firewall.allowedTCPPorts = lib.optional cfg.openFirewall 80;
  };
}
