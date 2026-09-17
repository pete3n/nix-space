# Remote desktop clients.
#
# Two different things despite the shared category: remmina speaks the
# standard protocols and connects to servers that already exist, while
# RustDesk uses its own protocol and needs RustDesk at both ends. A host
# wanting one does not necessarily want the other.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.remote;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isAarch64Darwin = pkgs.stdenv.hostPlatform.system == "aarch64-darwin";
in
{
  options.nixSpace.programs.remote = {
    enable = lib.mkEnableOption "remote desktop clients";

    remmina = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "pkgs.remmina";
      description = ''
        Multi-protocol remote desktop client: RDP, VNC, SPICE, X2Go, SSH.

        Connects to servers that already exist, so nothing is needed at the
        far end beyond whatever that machine already runs.

        Builds and is cached on aarch64-darwin despite being GTK and
        FreeRDP based, so this is a real option on the Mac Mini. Whether it
        is the right one is another question: macOS ships Screen Sharing for
        VNC and Microsoft Remote Desktop covers RDP, neither from nixpkgs,
        and this pulls the whole GTK plus GStreamer plus SPICE stack — about
        1.8 GiB unpacked — for a machine that would otherwise have none of
        it.

        null rather than a platform-derived default for exactly that reason:
        availability and desirability differ here, so the host decides.
      '';
    };

    rustdesk = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      example = lib.literalExpression "pkgs.rustdesk";
      description = ''
        RustDesk remote desktop.

        Its own protocol rather than RDP or VNC, so RustDesk has to be
        running at both ends — unlike remmina, which talks to existing
        servers. That makes it the right tool for reaching a machine you also
        control and the wrong one for anything else.

        NOT AVAILABLE ON aarch64-darwin. The package lists that platform in
        meta.platforms and then excludes it again in meta.badPlatforms, so
        setting this on the Mac Mini fails evaluation rather than the
        attribute simply being absent — see the assertion below.

        Defaults to RustDesk's public relay servers. Pointing it at a
        self-hosted relay means entering the ID and relay addresses in the
        client, which is runtime state in its own settings and not something
        this module can write.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.freerdp pkgs.tigervnc ]";
      description = ''
        Additional clients or protocol tooling, supplied by the caller.

        freerdp on its own gives you xfreerdp for scripted RDP sessions
        without remmina's UI, which is the shape a headless or automated use
        wants.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.rustdesk != null) -> !isAarch64Darwin;
        message = ''
          nixSpace.programs.remote.rustdesk is set on aarch64-darwin, where
          the package declares meta.badPlatforms containing that system.
          badPlatforms overrides meta.platforms, so evaluation fails.

          Use RustDesk's official macOS build outside nixpkgs, or remmina for
          the standard protocols.
        '';
      }
      {
        assertion = (cfg.remmina != null) -> !isDarwin || true;
        message = "unreachable";
      }
    ];

    home.packages =
      lib.optional (cfg.remmina != null) cfg.remmina
      ++ lib.optional (cfg.rustdesk != null) cfg.rustdesk
      ++ cfg.extraPackages;
  };
}
