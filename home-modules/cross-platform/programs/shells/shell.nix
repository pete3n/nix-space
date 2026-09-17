# Shell function module shared across shells.
#
# Written to $XDG_CONFIG_HOME/shell/ and sourced by whichever shells are
# enabled. Functions are POSIX sh: no bash or zsh specific syntax.
#
# Commands are called by name, not by store path.
# The packages are installed by this module, so the name resolves.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.shells;

  functionsDir = "${config.xdg.configHome}/shell";

  # Each entry: the file, the packages it calls, and whether it is wanted.
  available = {
    nixpath = {
      source = ./functions/nixpath.sh;
      packages = [ ];
      enable = cfg.functions.nixpath;
    };

    zfile = {
      source = ./functions/zfile.sh;
      packages = [ pkgs.fd ];
      enable = cfg.functions.zfile;
    };

    fds = {
      source = ./functions/fds.sh;
      packages = [
        pkgs.fd
        pkgs.ripgrep
        pkgs.fzf
        pkgs.bat
      ];
      enable = cfg.functions.fds;
    };

    smart-help = {
      source = ./functions/smart-help.sh;
      packages = [
        pkgs.curl
        pkgs.jq
        pkgs.gnused
        pkgs.gnugrep
        pkgs.tldr
        pkgs.ddgr
      ];
      enable = cfg.functions.smartHelp;
    };

    tmux-path = {
      source = ./functions/tmux-path.sh;
      packages = [ ];
      enable = cfg.functions.tmuxPath;
    };

    sudo-wrapper = {
      source = ./functions/sudo-wrapper.sh;
      packages = [ ];
      enable = cfg.functions.sudoWrapper;
    };
  };

  enabled = lib.filterAttrs (_n: f: f.enable) available;

  # Sourced in attribute-name order, which is stable. Definition order would
  # be whatever the attrset happened to iterate as, and a function that
  # depends on another being defined first would break.
  sourceLines = lib.concatMapStringsSep "\n" (name: ''
    [ -r "${functionsDir}/${name}.sh" ] && . "${functionsDir}/${name}.sh"
  '') (lib.attrNames enabled);
in
{
  options.nixSpace.programs.shells = {
    # This namespace doesn't have an enable option.
    # The function options are gated with their own enable options.
    functions = {
      nixpath = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "`nixpath <cmd>` - resolve a command to its store path.";
      };

      zfile = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          `zfile <name>` - jump to the directory holding a matching file.

          Needs zoxide for `z`, which this module does not install.
        '';
      };

      fds = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "`fds` - fd, optionally piped through ripgrep and fzf.";
      };

      smartHelp = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          `smart_help` - tldr, then cheat.sh, then DuckDuckGo.

          NOTE: This curls cheat.sh and duckduckgo.com.
        '';
      };

      tmuxPath = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Save and restore path across tmux.

          For hosts where Nix does not manage the OS, and tmux may be started 
          by something that never read the shell rc files. 
        '';
      };

      sudoWrapper = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Resolve commands to their store path before handing them to sudo.

          For hosts not managed by Nix, sudo resets PATH to a secure_path that
          excludes the Nix profile, so `sudo somenixtool` fails. Resolving
          first sidesteps that.

          This bipasses sudo's path sanitisation which is a risk:
          a command found on a compromised PATH is then run as root by 
          absolute path.
        '';
      };
    };

    aliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = lib.literalExpression ''
        {
          lsc = "lsd --classic";
          "?" = "smart_help";
        }
      '';
      description = ''
        Aliases applied to every enabled shell.
      '';
    };

    initExtra = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        Extra lines appended to every enabled shell's interactive init, after
        the functions are sourced.

        For anything shell-agnostic. Shell-specific syntax belongs in that
        shell's own module.
      '';
    };
  };

  # Ungated. Each function is optional individually, and with none enabled
  # this writes no files and installs nothing.
  config = {
    home.packages = lib.unique (lib.concatMap (f: f.packages) (lib.attrValues enabled));

    xdg.configFile = lib.mapAttrs' (
      name: f: lib.nameValuePair "shell/${name}.sh" { inherit (f) source; }
    ) enabled;
  };

  options.nixSpace.programs.shells.sourceScript = lib.mkOption {
    type = lib.types.lines;
    readOnly = true;
    internal = true;
    default = sourceLines;
    description = "Lines that source the enabled function files.";
  };
}
