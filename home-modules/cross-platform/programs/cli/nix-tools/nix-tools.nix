# Nix development and quality of life tool module.
#
# Grouped by category.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.nixTools;

  # nix helper guard wrapper.
  #
  #	Prevent users from accidentally erasing every profile on the machine during
  #	cleanup - especially for multi-user systems.
  nhWrapped = pkgs.symlinkJoin {
    name = "nh-guarded";
    paths = [ pkgs.nh ];
    buildInputs = [ pkgs.makeWrapper ];

    postBuild = ''
      wrapProgram $out/bin/nh \
        --run ${lib.escapeShellArg guardScript}
    '';

    meta.mainProgram = "nh";
  };

  # Runs before nh itself. Rewrites "$@" in place, which wrapProgram then
  # passes through, so an added --keep reaches nh as a real argument rather
  # than needing nh to read an environment variable.
  guardScript =
    lib.optionalString cfg.helper.cleanWarning # sh
      ''
        printf '\n' >&2
        if [ "''${1:-}" = "clean" ] && [ "''${2:-}" = "all" ]; then
        	printf 'nh clean all removes generations for EVERY user on this\n' >&2
        	printf 'machine and for the system profile, not only yours.\n' >&2
        	printf '\n' >&2
        	printf 'Use `nh clean user` to stay within your own profiles.\n' >&2
        	printf '\n' >&2
        	printf 'Continue? [y/N] ' >&2
        	read -r _nh_reply
        case "''${_nh_reply}" in
        	[yY]*) ;;
        	*) printf 'Aborted.\n' >&2; exit 1 ;;
        esac
        fi
      ''
    +
      lib.optionalString (cfg.helper.minimumKeep != null) # sh
        ''
          if [ "''${1:-}" = "clean" ]; then
          	# Only when neither is already given — an explicit argument wins.
          	case " $* " in
          		*" --keep "*|*" --keep-since "*) ;;
          		*) set -- "$@" --keep ${toString cfg.helper.minimumKeep} ;;
          	esac
          fi
        '';

  searchAlias =
    "${lib.getExe pkgs.nix-search-tv} print"
    + " | ${lib.getExe pkgs.fzf}"
    + " --preview '${lib.getExe pkgs.nix-search-tv} preview {}'"
    + " --scheme history";
in
{
  options.nixSpace.programs.nixTools = {
    enable = lib.mkEnableOption "Nix development and inspection tools";

    formatting = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install nixfmt, nixfmt-tree, statix, and deadnix.

        nixfmt formats a file; nixfmt-tree walks a project. statix finds
        antipatterns, deadnix finds unreachable bindings.
      '';
    };

    exploration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install nix-inspect, nix-melt, and nix-tree.

        nix-inspect browses a flake's outputs, nix-melt reads a lock file, and
        nix-tree walks a derivation's runtime closure. The first two answer
        "what does this flake provide"; the third answers "why is this in my
        closure", which is a different question entirely.
      '';
    };

    search = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install nix-search-tv and the `ns` alias.

        The alias pipes its index into fzf with a preview.
      '';
    };

    helper = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install nh, a wrapper over nixos-rebuild and home-manager.

          Mostly better output and a shorter command line.

          WARNING: `nh clean all` elevates and walks EVERY user's profiles plus 
          the system profile, so one user running it discards another's rollback 
          history without asking. Current generations survive; the ability to go 
          back to last week's does not.

          Prefer `nh clean user`, which stays within the caller's own
          profiles, and leave system collection to nix.gc on the NixOS side, 
          because that is scheduled, declarative, and cannot be triggered by one user
          against another.
        '';
      };

      flake = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/home/user/myflake";
        description = ''
          Flake nh operates on, exported as NH_FLAKE.

          This is the fallback for the other env vars. If the system and
          home configurations live in one repository, this is the only one
          worth setting.

          An absolute path, not a flake reference: nh hands it to
          nixos-rebuild and home-manager, which resolve a relative path
          against the working directory rather than against this.
        '';
      };

      osFlake = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Flake for `nh os`, exported as NH_OS_FLAKE.

          Only worth setting where the NixOS configuration lives somewhere
          other than `flake`.
        '';
      };

      homeFlake = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Flake for `nh home`, exported as NH_HOME_FLAKE.

          Only worth setting where the home-manager configuration lives
          somewhere other than `flake`.
        '';
      };

      darwinFlake = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Flake for `nh darwin`, exported as NH_DARWIN_FLAKE.

          Ignored on Linux — the subcommand does not apply — so setting it in
          shared configuration is harmless.
        '';
      };

      minimumKeep = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = 5;
        description = ''
          Generations `nh clean` keeps when not told otherwise, or null to
          leave nh's own default alone.

          nh KEEPS ONE by default, which is no rollback at all — and on a
          multi-user host `clean all` applies that to every user's profiles,
          including ones whose owner is not present to object. A dry run on a
          two-user machine shows it walking /home/<other>/.local/state/nix
          directly.

          The wrapper adds --keep only when neither --keep nor --keep-since
          is already present, so an explicit argument still wins.
        '';
      };

      cleanWarning = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Wrap `nh` so that `clean all` prints a warning before running.

          On a single-user machine this is noise. On a shared one it is the
          difference between discarding your own generations and discarding
          everyone's, which nh itself does not mention.
        '';
      };
    };

    devShells = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install devenv, for per-project development shells.

        Off by default: it maintains its own state directory per project and
        is only useful where projects actually use it — on a machine that
        does not, it is a large closure for nothing.
      '';
    };

    flakehub = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install fh, the FlakeHub client.

        Off by default: it is only useful with FlakeHub inputs, and it
        authenticates against a hosted service, which is a decision rather
        than a default.
      '';
    };

    searchAliasName = lib.mkOption {
      type = lib.types.str;
      default = "ns";
      description = ''
        Name of the nix-search-tv alias.

        Short because it is typed often; `ns` collides with nothing in
        coreutils, unlike `nf` or `nt`.
      '';
    };

    foreign = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isLinux;
      defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isLinux";
      description = ''
        patchelf, for running binaries that expect an FHS layout.

        Rewrites a binary's interpreter path and RUNPATH so it can find a
        loader and libraries that exist. Linux-only: it operates on ELF
        headers.

        For running a foreign binary rather than repairing one, steam-run or a
        buildFHSEnv wrapper is usually less work than patching, but patchelf is
        for the case where you want the binary itself fixed in place.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      lib.optionals cfg.formatting [
        pkgs.nixfmt
        pkgs.nixfmt-tree
        pkgs.statix
        pkgs.deadnix
      ]
      ++ lib.optionals cfg.exploration [
        pkgs.nix-inspect
        pkgs.nix-melt
        pkgs.nix-tree
      ]
      ++ lib.optionals cfg.search [
        pkgs.nix-search-tv
        # fzf explicitly: the alias pipes into it, so it is a dependency of
        # this module rather than something assumed to be installed. The
        # shells module also installs it for `fds`, and home-manager dedupes
        # identical store paths.
        pkgs.fzf
      ]
      ++ lib.optional cfg.devShells pkgs.devenv
      ++ lib.optional cfg.helper.enable (if cfg.helper.cleanWarning then nhWrapped else pkgs.nh)
      ++ lib.optional cfg.flakehub pkgs.fh
      ++ lib.optional cfg.foreign pkgs.patchelf;

    # Contributed to the shared alias set, so it applies to every enabled
    # shell rather than being declared per shell.
    nixSpace.programs.shells.aliases = lib.mkIf cfg.search {
      ${cfg.searchAliasName} = searchAlias;
    };

    home.sessionVariables = lib.mkIf cfg.helper.enable (
      lib.filterAttrs (_n: v: v != null) {
        NH_FLAKE = cfg.helper.flake;
        NH_OS_FLAKE = cfg.helper.osFlake;
        NH_HOME_FLAKE = cfg.helper.homeFlake;
        NH_DARWIN_FLAKE = cfg.helper.darwinFlake;
      }
    );
  };
}
