# clip58: base58-encode a string and put it on the clipboard.
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

  cfg = config.nixSpace.programs.clip58;

  clip58 = pkgs.writeShellApplication {
    name = "clip58";
    runtimeInputs = [
      cfg.encoderPackage
      cfg.clipboardPackage
    ];

    text = # sh
    ''
      CLIPBOARD_CMD=${lib.escapeShellArg cfg.clipboardCommand}
      ENCODER_CMD=${lib.escapeShellArg cfg.encoderCommand}
    ''
    + builtins.readFile ./clip58.sh;
  };
in
{
  options.nixSpace.programs.clip58 = {
    enable = mkEnableOption "clip58 base58 clipboard encoder";

    encoderPackage = mkOption {
      type = types.package;
      default = pkgs.python314Packages.base58;
      defaultText = lib.literalExpression "pkgs.python314Packages.base58";
      description = ''
        Package providing the base58 encoder.
      '';
    };

    encoderCommand = mkOption {
      type = types.str;
      default = "base58";
      description = ''
        Command that reads stdin and writes base58 to stdout.
      '';
    };

    clipboardPackage = mkOption {
      type = types.package;
      default = if pkgs.stdenv.hostPlatform.isDarwin then pkgs.coreutils else pkgs.wl-clipboard;
      defaultText = lib.literalMD "`wl-clipboard` on Linux; on Darwin, unused.";
      description = ''
        Package providing the clipboard command.
      '';
    };

    clipboardCommand = mkOption {
      type = types.str;
      default = if pkgs.stdenv.hostPlatform.isDarwin then "pbcopy" else "wl-copy";
      defaultText = lib.literalMD "`pbcopy` on Darwin, `wl-copy` otherwise.";
      description = ''
        Command that reads stdin and puts it on the clipboard.

        Set to `xclip -selection clipboard` on X11, with clipboardPackage
        changed to match: the default assumes Wayland.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ clip58 ];
  };
}
