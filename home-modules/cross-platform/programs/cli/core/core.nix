# This module contains a collection of core CLI tools for quality of life.
#
#   Shell integration: fzf, zoxide, and others each need hooks in every
#   enabled shell. Derived here from which shell modules are on, rather than
#   from the platform.
#
#   Aliases: This module creates aliases for some packages, e.g. `ls = "lsd"`
#		ships with the package that provides lsd.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.core;
  shells = config.nixSpace.programs.shells;

  # From the enabled shells, not the platform.
  integration = {
    enableBashIntegration = shells.bash.enable;
    enableZshIntegration = shells.zsh.enable;
  };

  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  options.nixSpace.programs.core = {
    enable = lib.mkEnableOption "modern CLI tool replacements";

    aliases = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Alias the standard commands to their replacements.

        Contributed only for tools this module actually installs, so an alias
        cannot point at something absent.

        NOT aliased even when installed: `grep` and `find`. ripgrep and fd
        take incompatible arguments, so aliasing them breaks any interactive
        use of the original's flags: `grep -r` in particular means something
        different to each. Alias those in your own config if you want them.

        The same reasoning excludes everything in `utilities`: sd takes a
        different regex dialect to sed, procs takes different flags to ps. 
        None are drop-in.
      '';
    };

    bat = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "A pager with syntax highlighting, replacing cat.";
      };

      theme = lib.mkOption {
        type = lib.types.str;
        default = "TwoDark";
        description = ''
          Syntax highlighting theme.

          `bat --list-themes` shows what is available. A name bat does not
          recognise falls back to its default rather than erroring.
        '';
      };

      extras = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install bat-extras: batdiff, batman, batgrep, batwatch.

          Wrappers pairing bat with diff, man, ripgrep, and entr. batman in
          particular replaces the man pager.
        '';
      };
    };

    lsd = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "ls with icons and colour. Needs a Nerd Font for the icons.";
    };

    ripgrep = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Recursive grep that respects .gitignore.

        NOT aliased to grep (see the aliases option.)
      '';
    };

    fd = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        A simpler find.

        Also a dependency of the shells module's `fds` and `zfile` functions,
        which install it themselves. This is for using it directly.
      '';
    };

    fzf = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Fuzzy finder, with Ctrl-R history search and Ctrl-T file search bound
        in every enabled shell.
      '';
    };

    zoxide = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        A cd that learns which directories you use.

        Provides `z`, which the shells module's `zfile` function calls — that
        function fails on its last line without this.
      '';
    };

    fastfetch = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        System information banner.

        Off by default: it is only useful when something runs it, and the
        bash module's loginGreeting does that when asked.
      '';
    };

    hardware = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isLinux;
      defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isLinux";
      description = ''
        Hardware inspection: pciutils (lspci), usbutils (lsusb), acpi, clinfo.
        clinfo reports the OpenCL platforms actually visible to a process, which 
        is the fastest way to tell whether a runtime is reaching the GPU as 
        opposed to falling back to CPU.

        Defaults to the platform rather than to true, because these read 
        Linux-specific interfaces.
      '';
    };

    serial = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Serial console tooling: tio and screen.

        Access needs group membership on the device node `dialout` on
        NixOS which is a system-level concern this module cannot grant. The
        package alone yields permission denied on /dev/ttyUSB0, which reads as
        a broken adapter rather than a missing group.
      '';
    };

    utilities = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install the unconfigured utility set: age, jq, gron, jc, sd, rsync, zip,
        unzip, file, lsof, duf, dust, procs, most, tldr, entr, hyperfine,
        fdupes, repgrep.

        All are portable across Linux and Darwin. entr uses kqueue rather than
        inotify on darwin and procs reads libproc rather than /proc, but both
        work.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.dust pkgs.dogdns ]";
      description = ''
        Additional replacements, without an option each.

        For tools with no home-manager module and no configuration that are
        not already covered by `utilities`. Alias them in your own config;
        this module only aliases what it installs by name.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      lib.optionals (cfg.bat.enable && cfg.bat.extras) (
        with pkgs.bat-extras;
        [
          batdiff
          batman
          batgrep
          batwatch
        ]
      )
      ++ lib.optional cfg.fd pkgs.fd
      ++ lib.optional cfg.fastfetch pkgs.fastfetch
      ++ lib.optionals cfg.hardware (
        with pkgs;
        [
          pciutils # lspci
          usbutils # lsusb
          acpi # Battery and thermal state
          clinfo # Visible OpenCL platforms
        ]
      )
      ++ lib.optionals cfg.serial (
        with pkgs;
        [
          tio
          screen
        ]
      )
      ++ lib.optionals cfg.utilities (
        with pkgs;
        [
          # Structured data
          gron
          jc
          jq

          gnumake

          # Text and files
          entr
          fdupes
          file
          most
          repgrep
          vim
          sd

          # Transfer and archives
          rsync

          # External media
          # TODO: Script to -> CP USB
          cdrtools
          # TODO: Script to -> ISO -> Record

          unzip
          zip

          # Inspection
          lsof
          duf # Better df
          dust # Better du
          procs # Better ps

          # Help
          tldr
          navi
          nb
          # TODO: Offline repo clones for TLDR and Navi

        ]
        ++ lib.optionals isLinux pkgs.udisks
      )
      ++ cfg.extraPackages;

    programs = {
      bat = lib.mkIf cfg.bat.enable {
        enable = true;
        config.theme = cfg.bat.theme;
      };

      lsd.enable = cfg.lsd;
      ripgrep.enable = cfg.ripgrep;

      fzf = lib.mkIf cfg.fzf ({ enable = true; } // integration);
      zoxide = lib.mkIf cfg.zoxide ({ enable = true; } // integration);
    };

    # Only for what is installed, so an alias cannot name a missing program.
    nixSpace.programs.shells.aliases = lib.mkIf cfg.aliases (
      lib.optionalAttrs cfg.bat.enable {
        cat = "bat";
      }
      // lib.optionalAttrs cfg.lsd {
        lsc = "lsd --classic";
      }
      // lib.optionalAttrs cfg.zoxide {
        cd = "z";
      }
    );
  };
}
