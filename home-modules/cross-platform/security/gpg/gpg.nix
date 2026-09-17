# GPG module with support for a smartcard-backed key.
#
# Pinentry is chosen at prompt time, not at build time. A graphical pinentry
# cannot fall back when there is no display. It fails with an ioctl error or
# hangs.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.security.gpg;

  pinentryAuto = pkgs.writeShellApplication {
    name = "pinentry-auto";
    text = ''
      PINENTRY_GUI="${lib.getExe cfg.pinentry.graphical}"
      PINENTRY_TTY="${lib.getExe cfg.pinentry.terminal}"
      GRAPHICAL_ALWAYS=${if pkgs.stdenv.hostPlatform.isDarwin then "1" else "0"}
    ''
    + builtins.readFile ./pinentry-auto.sh;
  };
in
{
  options.nixSpace.security.gpg = {
    enable = lib.mkEnableOption "GPG with smartcard support";

    keyFingerprint = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "081B780E59C37C11F59EFA2BC89CFF43D68AD2CB";
      description = ''
        Fingerprint of the default key, or null to let gpg choose.

        This is the full fingerprint rather than a key ID.
      '';
    };

    publicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./pubkey.asc";
      description = ''
        Public key to import and trust ultimately, or null for none.
      '';
    };

    pinentry = {
      graphical = lib.mkOption {
        type = lib.types.package;
        default = pkgs.pinentry-gnome3;
        defaultText = lib.literalExpression "pkgs.pinentry-gnome3";
        description = ''
          Pinentry used when a display is present.

          gnome3 rather than qt or gtk2: it speaks to the session's secret
          service and is the one most likely to theme correctly under a
          Wayland compositor.
        '';
      };

      terminal = lib.mkOption {
        type = lib.types.package;
        default = pkgs.pinentry-curses;
        defaultText = lib.literalExpression "pkgs.pinentry-curses";
        description = ''
          Pinentry used when there is no display.

          Covers a TTY, an ssh session, and anything running before the
          graphical session exists.
        '';
      };

      auto = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Choose between the two at prompt time rather than picking one.
        '';
      };
    };

    ssh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Use gpg-agent as the ssh agent.

          It takes control over SSH_AUTH_SOCK, so a separately-running ssh-agent 
          is shadowed and any key loaded into it becomes unavailable. That is the
          intent when ssh key are stored on a smartcard.
        '';
      };

      keygrips = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "1B73CE32F24F63ADCCC49061D9D95B414B057B7F" ];
        description = ''
          Keygrips of the subkeys to expose over ssh.

          A keygrip is not a fingerprint. It identifies the key material
          rather than the certificate, and gpg-agent indexes using it.

          Find it with:
            gpg --list-keys --with-keygrip
        '';
      };
    };

    cacheTtl = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 60;
      description = ''
        Seconds a passphrase stays cached after use.

        Short is reasonable with a smartcard, where each operation needs a
        touch regardless. The cache saves retyping a PIN, not the physical
        confirmation.
      '';
    };

    maxCacheTtl = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 120;
      description = ''
        Seconds after which a cached passphrase is dropped regardless of use.

        Must exceed cacheTtl, which the assertion below checks — the reverse
        gives a cache that expires before its own idle timeout, so the TTL
        appears to be ignored.
      '';
    };

    disableCcid = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Stop scdaemon using its internal CCID driver.

        pcscd owns the USB interface, and both trying to drive it produces a
        card that works intermittently.

        Only relevant where pcscd runs, which is any host also using the
        YubiKey for PIV or age.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Extra gpg.conf settings, merged over the defaults below.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.maxCacheTtl >= cfg.cacheTtl;
        message = ''
          nixSpace.security.gpg.maxCacheTtl is below cacheTtl, so the cache
          expires before its own idle timeout and the shorter value appears to
          be ignored.
        '';
      }
      {
        assertion = !cfg.ssh.enable || cfg.ssh.keygrips != [ ];
        message = ''
          nixSpace.security.gpg.ssh is enabled with no keygrips, so gpg-agent
          takes over SSH_AUTH_SOCK and offers no keys: every ssh
          authentication will fail.

          Find a keygrip with `gpg --list-keys --with-keygrip`, or set
          ssh.enable = false.
        '';
      }
    ];

    home.packages = lib.optional cfg.pinentry.auto pinentryAuto;

    programs.gpg = {
      enable = true;

      publicKeys = lib.optional (cfg.publicKey != null) {
        source = cfg.publicKey;
        trust = "ultimate";
      };

      settings = {
        # Strongest first. gpg negotiates down to what a recipient supports,
        # so listing these costs nothing and raises the floor where both ends
        # can manage it.
        personal-cipher-preferences = "AES256 AES192 AES";
        personal-digest-preferences = "SHA512 SHA384 SHA256";
        cert-digest-algo = "SHA512";

        # Long key IDs everywhere. The short form is 32 bits and has been
        # collided deliberately against the public keyservers, so a short ID
        # in output is not an identification.
        keyid-format = "0xlong";
        with-fingerprint = true;

        # Refuse a subkey that does not carry a back-signature from itself,
        # which is what stops one key claiming another's subkey.
        require-cross-certification = true;

        # Do not cache symmetric passphrases. They are typically one-off,
        # and caching one means the next unrelated symmetric operation
        # succeeds without asking.
        no-symkey-cache = true;
      }
      // lib.optionalAttrs (cfg.keyFingerprint != null) {
        default-key = cfg.keyFingerprint;
      }
      // cfg.settings;

      scdaemonSettings = lib.mkIf cfg.disableCcid {
        disable-ccid = true;
      };
    };

    # gpg-agent on Darwin needs launchd rather than systemd, which home-manager
    # handles.
    services.gpg-agent = {
      enable = true;

      enableSshSupport = cfg.ssh.enable;
      sshKeys = cfg.ssh.keygrips;

      defaultCacheTtl = cfg.cacheTtl;
      inherit (cfg) maxCacheTtl;

      pinentry.package = if cfg.pinentry.auto then pinentryAuto else cfg.pinentry.graphical;
    };
  };
}
