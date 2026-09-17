# rofi application launcher and dmenu replacement module.
#
# rofi needs a Wayland or X11 session. The macOS counterpart is
# nixSpace.programs.launchers.fzf.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.launchers.rofi;

  helpTmux = pkgs.writeShellApplication {
    name = "rofi-help-tmux";
    runtimeInputs = [
      pkgs.gawk
      pkgs.tmux
    ];
    text = builtins.readFile ./help-tmux.sh;
  };

  helpMenu = pkgs.writeShellApplication {
    name = "rofi-help-menu";
    runtimeInputs = [
      config.programs.rofi.finalPackage
      pkgs.gnused
      helpTmux
    ];
    text = builtins.readFile ./help-menu.sh;
  };
in
{
  options.nixSpace.programs.launchers.rofi = {
    enable = lib.mkEnableOption "rofi launcher";

    modes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "combi"
        "window"
        "run"
        "calc"
        "emoji"
      ];
      example = [
        "combi"
        "window"
        "run"
        "calc"
        "emoji"
      ];
      description = ''
        Modes rofi offers.

        A mode from a plugin (calc, emoji) also needs that plugin in the plugins
        option. 
      '';
    };

    plugins = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [
        pkgs.rofi-calc
        pkgs.rofi-emoji
      ];
      example = lib.literalExpression "[ pkgs.rofi-calc pkgs.rofi-emoji ]";
      description = ''
        rofi plugins.

        Each adds a mode that is only reachable if named in `modes`.
      '';
    };

    theme = lib.mkOption {
      type = lib.types.path;
      default = ./theme.rasi;
      defaultText = lib.literalMD "The bundled theme.";
      description = ''
        Path to a .rasi theme file.
      '';
    };

    helpMenu = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Install `rofi-help-menu`, an extensible help menu.
      '';
    };

    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default =
        "${lib.getExe config.programs.rofi.finalPackage}" + " -show-icons -combi-modi drun,run -show combi";
      defaultText = lib.literalMD "rofi in combi mode, showing icons.";
      description = ''
        Command that opens the launcher, read by
        nixSpace.programs.launchers.primaryCommand.
      '';
    };

    dmenuCommand = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${lib.getExe config.programs.rofi.finalPackage} -dmenu";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = ''
          nixSpace.programs.launchers.rofi is Linux only.

          On macOS use nixSpace.programs.launchers.fzf.
        '';
      }
    ];

    home.packages = lib.optionals cfg.helpMenu [
      helpTmux
      helpMenu
    ];

    programs.rofi = {
      enable = true;
      cycle = true;
      location = "center";
      inherit (cfg) plugins;

      inherit (cfg) theme;

      # A small upward offset: centred vertically looks low, because the eye
      # treats the visual centre as above the geometric one.
      xoffset = 0;
      yoffset = -20;

      extraConfig = {
        show-icons = true;

        # Escape and the launcher key itself, so the same keypress that opens
        # it closes it.
        kb-cancel = "Escape,Super+space";

        modi = lib.concatStringsSep "," cfg.modes;
        sort = true;
      };
    };
  };
}
