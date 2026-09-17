# YubiKey-backed secrets and keys module.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.security.yubikey;

  ageDecrypt = pkgs.writeShellApplication {
    name = "yubi-age-decrypt";

    # age-plugin-yubikey must be on PATH rather than referenced by store
    # path: age discovers plugins by looking for age-plugin-* in PATH, so a
    # store-path invocation of age alone would not find it.
    runtimeInputs = [
      pkgs.age
      pkgs.age-plugin-yubikey
      pkgs.coreutils
    ];

    text = ''
      PCSCD_SOCKET="${cfg.pcscdSocket}"

    ''
    + builtins.readFile ./age-decrypt.sh;
  };

  sshImport = pkgs.writeShellApplication {
    name = "yubi-ssh-import";
    runtimeInputs = [
      pkgs.openssh
      pkgs.findutils
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = builtins.readFile ./ssh-import.sh;
  };
in
{
  options.nixSpace.security.yubikey = {
    enable = lib.mkEnableOption "YubiKey-backed secrets and keys";

    pcscdSocket = lib.mkOption {
      type = lib.types.str;
      default = "/run/pcscd/pcscd.comm";
      description = ''
        Path to the pcscd socket, checked before attempting a decrypt.

        The check exists because age's failure without pcscd is confusing: it
        reports that no identity matched, which reads as a wrong key rather
        than an unreachable one.

        The path is the NixOS default; a host running pcscd another way, or
        macOS, will differ.
      '';
    };

    tools = {
      enable = lib.mkEnableOption "YubiKey management tools" // {
        default = true;
        description = ''
          Install the tools for configuring and inspecting a YubiKey.

          ykman for slot and application configuration, opensc for the PKCS#11
          provider that lets ssh and browsers talk to the PIV applet.

          SEPARATE FROM the activation scripts, which carry their own
          dependencies internally — this is what you need to set a key up in
          the first place, not what the scripts need to use one.
        '';
      };

      legacyOtp = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install yubikey-personalization, for the legacy OTP slots.

          Off by default: it configures the two programmable slots on older
          keys, which is a different mechanism from FIDO2, PIV, and OATH. On a 
          key used for those, the slots are usually left alone.
        '';
      };

      oathGui = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install yubioath-flutter, a graphical OATH client.

          `ykman oath accounts code` does the same from a terminal.
        '';
      };
    };

    u2f = {
      enable = lib.mkEnableOption "pam_u2f credential mapping";

      credentials = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "jPXIHluUKJNDbiCS...,FQlfOdBDXUlixODc...,es256,+presence"
        ];
        description = ''
          Registered credentials, one per key, WITHOUT the leading username.

          Each is the output of `pamu2fcfg` with the `username:` prefix
          removed. This module prepends the current user. The fields are key
          handle, public key, COSE algorithm, and options; `+presence` means a
          touch is required.

          Generate one with:
            pamu2fcfg -n

          These are public. A key handle and public key identify a credential
          on the token but cannot authenticate without it, so the Nix store is
          an acceptable home for them.

          List every key. A backup token registered but not listed here cannot
          be used.

          The system side is SEPARATE AND REQUIRED. This file is only the
          mapping; what reads it is pam_u2f, a PAM module the system loads:

            security.pam.u2f.enable = true;
            security.pam.services.sudo.u2fAuth = true;

          Without that, the file is written and nothing reads it.
        '';
      };

      pamtester = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install pamtester, for testing a PAM stack without a login.

          Worth having wherever u2f authentication is configured: a
          misconfigured stack is otherwise discovered by being locked out of
          sudo.

            pamtester sudo "$USER" authenticate
        '';
      };
    };

    ageSecrets = {
      enable = lib.mkEnableOption "decrypting age secrets with a YubiKey at activation" // {
        default = true;
      };
      secrets = lib.mkOption {
        default = [ ];
        description = ''
          Secrets to decrypt during activation.

          Each is decrypted ONCE: a secret whose output file already exists is
          skipped, so rotating one means removing the plaintext first. That
          keeps activation from demanding a touch on every rebuild.
        '';

        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              outputFile = lib.mkOption {
                # str, NOT path.
                #
                # A path-typed option copies its value into the store, which
                # is right for the inputs below and wrong here — the
                # destination would become a read-only store path, and the
                # decrypt would fail trying to write it.
                type = lib.types.str;
                example = "/home/user/.ssh/id_git";
                description = "Where to write the decrypted file. Created with mode 600.";
              };

              ageFile = lib.mkOption {
                type = lib.types.path;
                example = lib.literalExpression "./secrets/git-key.age";
                description = ''
                  The encrypted file.

                  Path-typed, so it is copied into the store. An age file is 
                  ciphertext, and having it in the store means activation does 
                  not depend on the working tree being present.
                '';
              };

              identityFile = lib.mkOption {
                type = lib.types.path;
                example = lib.literalExpression "./secrets/age-yubikey-identities.txt";
                description = ''
                  The age-plugin-yubikey identity file.

                  Also ciphertext: it names a key on the token rather than 
                  containing one, so the store is an acceptable home for it.
                '';
              };
            };
          }
        );
      };
    };

    sshImport = {
      enable = lib.mkEnableOption "importing resident SSH keys from a security key";
      expectedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "id_ed25519_sk_rk_aws"
          "id_ed25519_sk_rk_github"
        ];
        description = ''
          Key filenames expected in ~/.ssh. A missing one triggers an import.

          These are the names `ssh-keygen -K` produces, which it derives from
          the credential's application string rather than letting you choose.
        '';
      };
    };

    ageTools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install age, age-plugin-yubikey, and ragenix.

        For creating, editing, and rekeying secrets by hand.

        ragenix ships bin/agenix as well as bin/ragenix, so both names resolve
        to it. Adding pkgs.agenix alongside collides on bin/agenix at
        activation rather than shadowing silently.

        age discovers plugins by finding age-plugin-* on PATH, so the plugin
        has to be installed rather than referenced by store path. Without it,
        decryption fails reporting that no identity matched.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.enable && cfg.tools.enable) {
      home.packages = [
        pkgs.yubikey-manager
        pkgs.opensc
      ]
      ++ lib.optional cfg.tools.legacyOtp pkgs.yubikey-personalization
      ++ lib.optional cfg.tools.oathGui pkgs.yubioath-flutter;
    })

    (lib.mkIf (cfg.enable && cfg.ageSecrets.enable) {
      home.packages = [
        ageDecrypt

        # Also on PATH, not only inside the wrapper.
        pkgs.age
        pkgs.age-plugin-yubikey
      ];

      home.activation.yubiAgeDecrypt = lib.hm.dag.entryAfter [ "writeBoundary" ] (
        lib.concatMapStrings (secret: ''
          $DRY_RUN_CMD ${lib.getExe ageDecrypt} \
            ${lib.escapeShellArg secret.outputFile} \
            ${lib.escapeShellArg (toString secret.ageFile)} \
            ${lib.escapeShellArg (toString secret.identityFile)}
        '') cfg.ageSecrets.secrets
      );
    })

    (lib.mkIf (cfg.enable && cfg.sshImport.enable) {
      home.packages = [ sshImport ];

      home.activation.yubiSshImport = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        # || true, deliberately: a failed import should not fail the whole
        # activation. The script reports the reason itself, and the keys can
        # be imported later by running yubi-ssh-import by hand.
        $DRY_RUN_CMD ${lib.getExe sshImport} ${lib.escapeShellArgs cfg.sshImport.expectedKeys} || true
      '';
    })

    (lib.mkIf (cfg.enable && cfg.ageTools) {
      home.packages = [
        pkgs.age
        pkgs.age-plugin-yubikey
        pkgs.ragenix
      ];
    })

    (lib.mkIf (cfg.enable && cfg.u2f.enable) {
      assertions = [
        {
          assertion = cfg.u2f.credentials != [ ];
          message = ''
            nixSpace.security.yubikey.u2f is enabled with no credentials, so
            the mapping file would list this user with no keys.

            pam_u2f treats that as "no key registered", which depending on
            the PAM stack, either denies authentication or falls through to a
            password. Generate one with `pamu2fcfg -n`.
          '';
        }
      ];

      home.packages = lib.optional cfg.u2f.pamtester pkgs.pamtester;

      # NOT pam_u2f. It is a PAM module, loaded by the system from its own
      # module path.
      home.file.".config/Yubico/u2f_keys".text =
        "${config.home.username}:" + lib.concatStringsSep ":" cfg.u2f.credentials + "\n";
    })
  ];
}
