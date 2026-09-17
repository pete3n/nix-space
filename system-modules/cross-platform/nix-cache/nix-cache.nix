# Binary cache substituter module.
#
# URL and key are paired. Adding a substituter requires a key to trust.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.nix.cache;

  substituterOpts =
    { ... }:
    {
      options = {
        url = lib.mkOption {
          type = lib.types.str;
          example = "https://nix-community.cachix.org/";
          description = "Substituter URL. A trailing slash is conventional.";
        };

        publicKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
          description = ''
            	Signing key to trust for this substituter.

            	Null means this cache serves paths signed by someone else, such as
            	pass-through proxy for cache.nixos.org. A cache that signs its own paths 
            	and has no key here will have every path rejected.
          '';
        };

        priority = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = ''
            Advisory only, and usually not needed.

            Nix orders substituters by the priority each one advertises in its
            own nix-cache-info, not by position in this list. A local proxy
            that is not being preferred is advertising a worse priority than
            cache.nixos.org's 40.
          '';
        };
      };
    };
in
{
  options.nixSpace.nix.cache = {
    enable = lib.mkEnableOption "binary cache substituters";

    substituters = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule substituterOpts);
      default = [ ];
      example = lib.literalExpression ''
        [
          {
            # Local nginx pass-through. No key: it re-serves upstream-signed
            # paths and signs nothing itself.
            url = "http://backupsvr.p22:8000/";
          }
          {
            url = "https://nix-community.cachix.org/";
            publicKey = "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=";
          }
        ]
      '';
      description = ''
        Substituters to add, each with the key needed to trust it.

        cache.nixos.org and its key are already NixOS defaults and do not need
        listing. These entries are appended to those defaults.
      '';
    };

    connectTimeout = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = ''
        Seconds before giving up on a substituter connection.

        Kept short so an unreachable local cache costs two seconds rather than
        stalling every build. Raise it if a substituter is across a slow link.
      '';
    };

    stalledDownloadTimeout = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "Seconds of no progress before abandoning a download.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.substituters != [ ];
        message = ''
          nixSpace.nix.cache is enabled but no substituters are configured.
          Either list some, or leave it disabled — cache.nixos.org is already
          a NixOS default and needs nothing here.
        '';
      }
    ];

    nix.settings = {
      substituters = map (sub: sub.url) cfg.substituters;

      trusted-public-keys = lib.filter (key: key != null) (map (sub: sub.publicKey) cfg.substituters);

      connect-timeout = cfg.connectTimeout;
      stalled-download-timeout = cfg.stalledDownloadTimeout;

      # Remote builders fetch from substituters themselves rather than having
      # every path copied over the wire from this machine. Matters as soon as
      # a build server is in play.
      builders-use-substitutes = true;
    };
  };
}
