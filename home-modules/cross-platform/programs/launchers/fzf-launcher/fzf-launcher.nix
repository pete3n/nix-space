# An fzf-based application launcher module for Nix-Darwin.
#
# This is a poor man's rofi: fzf in a terminal window, indexing  /Applications,
# home-manager's app bundles, and the profile's bin directory. Spotlight only
# shows programs from /Applications.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.launchers.fzf;
  terminals = config.nixSpace.programs.terminals;

  launcher = pkgs.writeShellApplication {
    name = "fzf-launcher";
    runtimeInputs = [
      pkgs.fzf
      pkgs.findutils
      pkgs.gnused
      pkgs.coreutils
    ];
    text = builtins.readFile ./fzf-launcher.sh;
  };
in
{
  options.nixSpace.programs.launchers.fzf = {
    enable = lib.mkEnableOption "fzf application launcher for macOS";

    prompt = lib.mkOption {
      type = lib.types.str;
      default = "Launch: ";
      description = "Prompt shown in the launcher.";
    };

    height = lib.mkOption {
      type = lib.types.str;
      default = "40%";
      description = ''
        Height of the fzf window, as a percentage or a line count.

        This is fzf's own height within the terminal, not the terminal's
        size; the window is whatever the terminal opens at, so a small
        percentage leaves empty space rather than a small window.
      '';
    };

    profileBin = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.profileDirectory}/bin";
      defaultText = lib.literalExpression "\"\${config.home.profileDirectory}/bin\"";
      description = ''
        Directory of profile executables to index.

        From config rather than a literal ~/.nix-profile/bin: home-manager
        knows where it put the profile, and on a machine using the newer
        per-user state path that literal is wrong.
      '';
    };

    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${terminals.primaryCommand} -e ${lib.getExe launcher}";
      defaultText = lib.literalMD "The primary terminal running fzf-launcher.";
      description = ''
        Command that opens the launcher, read by
        nixSpace.programs.launchers.primaryCommand.

        Wrapped in a terminal because fzf is a TUI invoked from a keybind.
        With no terminal it has nowhere to draw and exits immediately.
      '';
    };

    dmenuCommand = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${terminals.primaryCommand} -e ${lib.getExe pkgs.fzf}";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = ''
          nixSpace.programs.launchers.fzf is macOS only.

          On Linux use the rofi launcher.
        '';
      }
    ];

    home.packages = [ launcher ];

    # Passed as environment rather than baked into the script, so the same
    # store path serves a changed prompt without a rebuild.
    home.sessionVariables = {
      NS_LAUNCHER_PROFILE_BIN = cfg.profileBin;
      NS_LAUNCHER_TERMINAL = terminals.primaryCommand;
      NS_LAUNCHER_PROMPT = cfg.prompt;
      NS_LAUNCHER_HEIGHT = cfg.height;
    };
  };
}
