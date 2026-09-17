# Open WebUI — frontend for Ollama and other OpenAI-compatible backends.
#
# Separate module from ollama.nix: a frontend can point at a remote backend,
# and an inference host may run headless with no frontend at all. Bundling
# them made "which accelerator" and "is there a web UI" the same decision.
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.services.openWebui;
in
{
  options.nixSpace.services.openWebui = {
    enable = lib.mkEnableOption "Open WebUI";

    backends = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "http://127.0.0.1:11434" ];
      example = [
        "http://127.0.0.1:11434"
        "http://127.0.0.1:11435"
      ];
      description = ''
        Ollama API endpoints, in priority order. One entry per instance on a
        multi-accelerator host; a remote address is equally valid.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start at boot. Off by default to match the inference services — a
        frontend running without a backend is only a source of errors.
      '';
    };

    restrictEgress = lib.mkOption {
      type = lib.types.nullOr (lib.types.listOf lib.types.str);
      default = [
        "localhost"
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
      ];
      description = ''
        Address ranges reachable from the service, or null for none.

        CAUTION: Open WebUI reaches out to Hugging Face on first run for
        embedding models and to check for updates. Under this restriction
        those attempts fail — usually a slow startup rather than a hard error,
        but set RAG_EMBEDDING_ENGINE and friends deliberately, or widen this,
        if the UI hangs on first load.
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Extra environment. Use environmentFile in services.open-webui for
        anything secret — values here land in the world-readable Nix store.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.open-webui = {
      enable = true;
      environment = {
        OLLAMA_BASE_URLS = lib.concatStringsSep "," cfg.backends;
      }
      // cfg.environment;
    };

    systemd.services.open-webui = {
      wantedBy = lib.mkForce (lib.optional cfg.autoStart "multi-user.target");
      serviceConfig = lib.optionalAttrs (cfg.restrictEgress != null) {
        IPAddressDeny = "any";
        IPAddressAllow = cfg.restrictEgress;
      };
    };
  };
}
