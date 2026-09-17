# Application launcher module.
#
# Designates the primary launcher for other configuration options; analogous to
# the primary terminal option.
#
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.programs.launchers;
in
{
  imports = [
    ./fzf-launcher
    ./rofi
  ];

  options.nixSpace.programs.launchers = {
    primary = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "fzf"
          "rofi"
        ]
      );
      default = null;
      description = ''
        Launcher that other modules invoke.

        Null means no launcher is configured and those bindings should be set
        by hand. There is no sensible default because the answer is
        platform-dependent in a way this module should not assume: rofi needs
        a Wayland or X11 session, fzf-launcher drives macOS's `open`.
      '';
    };

    primaryCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      readOnly = true;
      default =
        if cfg.primary == null then
          null
        else if cfg.primary == "rofi" then
          cfg.rofi.command
        else
          cfg.fzf.command;
      defaultText = lib.literalMD "The command for `primary`.";
      description = ''
        Full command line for the primary launcher, for modules that need to
        invoke it.
      '';
    };

    dmenuCommand = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      readOnly = true;
      default =
        if cfg.primary == null then
          null
        else if cfg.primary == "rofi" then
          cfg.rofi.dmenuCommand
        else
          cfg.fzf.dmenuCommand;
      description = ''
        Command that reads a list on stdin and prints the selection, for
        callers that supply their own items, such as a clipboard history, a
        wallpaper picker, a session menu.

        Differs from primaryCommand becuase rofi needs `-dmenu` and none of the 
        mode flags, and fzf needs a terminal wrapper it.
      '';
    };
  };

  config = lib.mkIf (cfg.primary != null) {
    assertions = [
      {
        assertion = cfg.${cfg.primary}.enable;
        message = ''
          nixSpace.programs.launchers.primary is "${cfg.primary}", but that
          launcher is not enabled.
        '';
      }
    ];
  };
}
