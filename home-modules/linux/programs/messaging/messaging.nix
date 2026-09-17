# Desktop messaging clients.
#
# All three are Electron applications, which is the reason every package here
# is caller-supplied rather than named from pkgs: they need frequent updates
# for protocol compatibility, and at least one needs a locally modified
# derivation to run correctly on this hardware.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.programs.messaging;
in
{
  options.nixSpace.programs.messaging = {
    enable = lib.mkEnableOption "desktop messaging clients";

    signal = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "pkgs.mod.no-gpu-signal-desktop";
      description = ''
        Signal desktop client. null to omit.

        Supplied by the caller rather than named here because the stock
        package may need modifying for the host's graphics stack. On AMD
        hardware Electron's GPU process fails with "Cannot find target for
        triple amdgcn--" and the window renders blank; the fix is forcing
        software GL and disabling the GPU process outright, which is a
        derivation-level change the caller supplies.

        See https://github.com/signalapp/Signal-Desktop/issues/6855

        Signal also enforces a client version floor and eventually refuses to
        connect, so this wants an input that moves rather than a pin.
      '';
    };

    element = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "pkgs.unstable.element-desktop";
      description = ''
        Element Matrix client. null to omit.

        Stores its session keys under ~/.config/Element; losing that
        directory means re-verifying the device rather than just logging in
        again.
      '';
    };

    teams = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "pkgs.unstable.teams-for-linux";
      description = ''
        teams-for-linux, an unofficial Electron wrapper around the Teams web
        client. null to omit.

        Unofficial and tracking a web application Microsoft changes without
        notice, so it breaks more often than the others and wants the same
        moving input.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional messaging clients, supplied by the caller.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      lib.optional (cfg.signal != null) cfg.signal
      ++ lib.optional (cfg.element != null) cfg.element
      ++ lib.optional (cfg.teams != null) cfg.teams
      ++ cfg.extraPackages;
  };
}
