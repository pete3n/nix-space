# git, lazygit, and commit linting module.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    mkEnableOption
    mkIf
    types
    ;

  cfg = config.nixSpace.programs.git;

  # Written to the XDG config dir so the hook can name it by path; gitlint has
  # no per-user config file of its own. A stable path also means rule changes
  # reach repositories whose hook was copied at init time.
  gitlintConfigFile = "${config.xdg.configHome}/gitlint";

  gitlintConfig = ''
    [general]
    ignore=${
      lib.concatStringsSep "," (
        [ "title-trailing-punctuation" ] ++ lib.optional (!cfg.gitlint.requireBody) "body-is-missing"
      )
    }
    contrib=contrib-title-conventional-commits

    [title-max-length]
    line-length=${toString cfg.gitlint.titleMaxLength}

    [title-min-length]
    min-length=${toString cfg.gitlint.titleMinLength}
  '';

  # Git copies templateDir into every new repository at init/clone time.
  # Only hooks/, info/, and description are meaningful there.
  commitMsgHook = pkgs.writeShellApplication {
    name = "gitlint-commit-msg";
    runtimeInputs = [ pkgs.gitlint ];

    text = # sh
    ''
      GITLINT_CONFIG_FILE="${gitlintConfigFile}"
    ''
    + builtins.readFile ./gitlint-commit-msg.sh;
  };
in
{
  options.nixSpace.programs.git = {
    enable = mkEnableOption "git configuration";

    userName = mkOption {
      type = types.str;
      example = "darthgit";
      description = "Name recorded in commits.";
    };

    userEmail = mkOption {
      type = types.str;
      example = "darthgit@mail.com";
      description = "Email recorded in commits.";
    };

    defaultBranch = mkOption {
      type = types.str;
      default = "main";
      description = "Branch name used by git init.";
    };

    editor = mkOption {
      type = types.str;
      default = "vi";
      example = "nvim";
      description = ''
        Editor for commit messages and interactive rebase.

        Defaults to vi, which is present on every POSIX system. Setting nvim
        here without the nixvim tag gives git an editor that is not installed,
        and the failure appears at commit time rather than at build time.
      '';
    };

    signingKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "0x1234ABCD";
      description = ''
        GPG key ID for commit signing, or null to leave signing unconfigured.

        Setting this enables signing for all commits. With a key on a YubiKey,
        every commit then requires a touch, worth knowing before a rebase of
        forty commits.
      '';
    };

    sshHosts = mkOption {
      type = types.attrsOf (
        types.submodule (
          { name, ... }:
          {
            options = {
              hostName = mkOption {
                type = types.str;
                default = name;
                description = "Real hostname to connect to.";
              };

              user = mkOption {
                type = types.str;
                default = "git";
                description = "SSH user. Forges almost always use 'git'.";
              };

              identityFiles = mkOption {
                type = types.listOf types.str;
                default = [ ];
                example = [ ".ssh/id_ed25519_sk_rk_github" ];
                description = ''
                  Identity files, relative to the home directory.

                  Relative so the module can resolve them against
                  config.home.homeDirectory: /home/<user> is wrong on Darwin.

                  Order matters: ssh offers them in sequence, and a server
                  with a low MaxAuthTries can disconnect before reaching the
                  right one.
                '';
              };
            };
          }
        )
      );
      default = { };
      example = lib.literalExpression ''
        {
          "github github.com" = {
            hostName = "github.com";
            identityFiles = [
              ".ssh/id_ed25519_sk_rk_github"
              ".ssh/id_ed25519_user"
            ];
          };
        }
      '';
      description = ''
        SSH host entries for git forges. The attribute name is the Host
        pattern, so it may list several aliases separated by spaces.
      '';
    };

    keychain = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Run keychain to hold decrypted SSH keys across shell sessions.

          Unnecessary for hardware-backed keys. A FIDO2 key requires a touch
          per use regardless, so there is nothing to cache.
        '';
      };

      keys = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "darthgit" ];
        description = "Key names in ~/.ssh for keychain to load.";
      };

      shells = mkOption {
        type = types.listOf (
          types.enum [
            "bash"
            "zsh"
          ]
        );
        default = [ "bash" ];
        description = ''
          Shells to add keychain integration to.
        '';
      };
    };

    gitlint = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Write the gitlint config and install gitlint.

          Enabling this alone does not enforce anything; it makes `gitlint`
          available. Run it by hand with `gitlint -C ~/.config/gitlint`, since
          gitlint reads only a repository's ./.gitlint on its own. See
          installHook for enforcement.
        '';
      };

      installHook = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Install a commit-msg hook in the git template directory, so NEW
          repositories reject non-conforming commit messages.

          Templates apply only at git init and git clone. Existing
          repositories are unaffected, and there is no retroactive mechanism
          short of re-running git init in each.

          The hook is a hard stop. It fires again on every commit touched by a
          rebase, so an interactive rebase across old non-conforming commits
          will hit it repeatedly. The failure message names --no-verify.
        '';
      };

      requireBody = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Reject commits whose message is a title alone (gitlint rule B6).

          Off by default so `git commit -m "type: description"` works. When a
          body is present it must still be at least 20 characters (B5).
        '';
      };

      titleMaxLength = mkOption {
        type = types.int;
        default = 80;
        description = "Maximum commit title length.";
      };

      titleMinLength = mkOption {
        type = types.int;
        default = 5;
        description = "Minimum commit title length.";
      };
    };

    pager = mkOption {
      type = types.enum [
        "default"
        "diff-so-fancy"
        "delta"
      ];
      default = "diff-so-fancy";
      description = ''
        Diff pager.

        "default" leaves core.pager unset, which means less.
      '';
    };

  };

  config = mkIf cfg.enable {
    programs = {
      git = {
        enable = true;
        lfs.enable = true;

        settings = {
          core = {
            inherit (cfg) editor;
          }
          // lib.optionalAttrs (cfg.pager == "diff-so-fancy") {
            pager = "diff-so-fancy | less --tabs=4 -RF";
          };

          interactive = lib.optionalAttrs (cfg.pager == "diff-so-fancy") {
            diffFilter = "diff-so-fancy --patch";
          };

          init = {
            inherit (cfg) defaultBranch;
          }
          // lib.optionalAttrs cfg.gitlint.installHook {
            templateDir = "${config.home.homeDirectory}/.git-templates";
          };

          user = {
            name = cfg.userName;
            email = cfg.userEmail;
          }
          // lib.optionalAttrs (cfg.signingKey != null) {
            signingkey = cfg.signingKey;
          };

          commit = lib.optionalAttrs (cfg.signingKey != null) {
            gpgsign = true;
          };
        };
      };

      delta.enable = cfg.pager == "delta";
      lazygit.enable = true;

      keychain = mkIf cfg.keychain.enable {
        enable = true;
        inherit (cfg.keychain) keys;
        enableBashIntegration = builtins.elem "bash" cfg.keychain.shells;
        enableZshIntegration = builtins.elem "zsh" cfg.keychain.shells;
      };

      ssh.settings = lib.mapAttrs (_: host: {
        HostName = host.hostName;
        User = host.user;
        IdentityFile = map (f: "${config.home.homeDirectory}/${f}") host.identityFiles;
        IdentitiesOnly = true;
      }) cfg.sshHosts;
    };

    home.packages =
      lib.optional cfg.gitlint.enable pkgs.gitlint
      ++ lib.optional (cfg.pager == "diff-so-fancy") pkgs.diff-so-fancy;

    xdg.configFile = mkIf cfg.gitlint.enable {
      gitlint.text = gitlintConfig;
    };

    home.file = mkIf cfg.gitlint.installHook {
      ".git-templates/hooks/commit-msg" = {
        source = lib.getExe commitMsgHook;
        executable = true;
      };
    };
  };
}
