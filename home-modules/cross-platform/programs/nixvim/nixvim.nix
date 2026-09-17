{
  config,
  lib,
  ...
}:

let
  cfg = config.nixSpace.programs.nixvim;
in
{
  options.nixSpace.programs.nixvim = {
    enable = lib.mkEnableOption "the nixvim-based Neovim build";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression ''inputs.nixvim.packages.''${system}.default'';
      description = ''
        The pre-built nixvim derivation. This must be supplied by the calling
        configuration, which is where the flake `inputs` are in lexical scope.
        This module deliberately does not reference `inputs` itself, so it
        carries no dependency on the caller's input names.
      '';
    };

    binaryName = lib.mkOption {
      type = lib.types.str;
      default = "nvim";
      description = ''
        Name of the executable inside `package`, used to resolve EDITOR.
        Only consulted when `defaultEditor` is enabled.
      '';
    };

    defaultEditor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Point EDITOR and VISUAL at this nixvim build.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = ''
          nixSpace.programs.nixvim is enabled but no package was supplied.

          Set it from a context where the flake inputs are in scope, e.g. in
          the per-user per-host flake:

            nixSpace.programs.nixvim.package =
              inputs.nixvim.packages.''${nixSpaceAttrs.system}.default;
        '';
      }
      {
        assertion = !config.programs.neovim.enable;
        message = ''
          nixSpace.programs.nixvim and home-manager's programs.neovim both
          install an `nvim` binary into the profile; they collide on
          activation. Enable only one.
        '';
      }
    ];

    home.packages = lib.optional (cfg.package != null) cfg.package;

    home.sessionVariables = lib.mkIf (cfg.defaultEditor && cfg.package != null) {
      EDITOR = lib.getExe' cfg.package cfg.binaryName;
      VISUAL = lib.getExe' cfg.package cfg.binaryName;
    };
  };
}
