# llama.cpp reranking server.
#
# Ollama has no rerank endpoint, so cross-encoder reranking for RAG has to
# come from llama-server. This runs one instance in reranking mode and
# nothing else: no chat, no completion, one model, one job.
#
# Defaults to CPU. A 568M cross-encoder scoring a handful of candidates per
# query costs little next to generation, and keeping it off the GPU means it
# never competes with Ollama for VRAM -- Ollama's scheduler cannot see this
# process and will happily try to allocate memory it already holds.
#
# With egress restricted, llama-server's --hf-repo fetch cannot reach
# anything. Place the GGUF under modelDir by other means, as with
# ollama-import.
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

  cfg = config.nixSpace.services.llama-reranker;

  flags = [
    "--model"
    cfg.model
    "--alias"
    cfg.alias

    # Reranking mode. Older builds spell this "--rerank"; some also want an
    # explicit "--embedding". Check `llama-server --help` against the build
    # in your closure before assuming.
    "--reranking"
    "--pooling"
    "rank"

    # The reranker sees query + candidate, not the whole corpus. Sized to the
    # largest chunk you index, not to the model's trained context: llama-server
    # allocates KV for the full window up front.
    "--ctx-size"
    (toString cfg.contextSize)

    "--gpu-layers"
    (toString cfg.gpuLayers)

    "--host"
    cfg.host
    "--port"
    (toString cfg.port)

    # Nothing here is interactive.
    "--no-webui"

    # A cross-encoder scores query+document as one indivisible sequence with
    # full bidirectional attention -- it cannot be split across physical
    # batches the way a generative prompt can. So the batch sizes have to
    # match the context, or any chunk over the 512-token default fails at
    # request time rather than at startup.
    "--ctx-size"
    (toString cfg.contextSize)
    "--batch-size"
    (toString cfg.contextSize)
    "--ubatch-size"
    (toString cfg.contextSize)
  ]
  ++ cfg.extraFlags;
in
{
  options.nixSpace.services.llama-reranker = {
    enable = mkEnableOption "llama.cpp reranking server";

    package = mkOption {
      type = types.package;
      default = pkgs.llama-cpp;
      defaultText = lib.literalExpression "pkgs.llama-cpp";
      example = lib.literalExpression "pkgs.llama-cpp-vulkan";
      description = ''
        llama.cpp build. The CPU default is deliberate; see the header.

        If you do move this to the GPU, llama-cpp-vulkan is usually the
        less fragile choice on AMD than llama-cpp-rocm, which has a
        history of needing AMDGPU_TARGETS pinned to a specific gfx
        target. Set gpuLayers as well -- the accelerated package alone
        offloads nothing.
      '';
    };

    modelDir = mkOption {
      type = types.str;
      default = "/var/lib/llama-models";
      description = ''
        Directory holding reranker GGUFs. Deliberately not Ollama's blob
        store: those blobs are content-addressed and garbage-collected, so
        an `ollama rm` elsewhere would take this service's model with it.
      '';
    };

    model = mkOption {
      type = types.str;
      example = "/var/lib/llama-models/bge-reranker-v2-m3-q8_0.gguf";
      description = ''
        Path to the reranker GGUF.

        Prefer Q8 over Q4 here. A generator samples from a distribution and
        absorbs quantization noise; a reranker's entire output is the scalar
        you sort by, so the noise lands directly in the ordering.
      '';
    };

    alias = mkOption {
      type = types.str;
      default = "reranker";
      example = "bge-reranker-v2-m3";
      description = ''
        Model name the server reports and clients must send. Without it
        llama-server answers with the full GGUF path, which makes the
        client-side config both ugly and dependent on this path.
      '';
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Address the server listens on.";
    };

    port = mkOption {
      type = types.port;
      default = 8081;
      description = ''
        Listen port. Not llama.cpp's own 8080 default, which collides with
        too much else.
      '';
    };

    contextSize = mkOption {
      type = types.int;
      default = 8192;
      description = "Context window, in tokens. Sized to chunk length, not model maximum.";
    };

    gpuLayers = mkOption {
      type = types.int;
      default = 0;
      example = 99;
      description = ''
        Layers offloaded to the GPU. Zero is CPU-only. Raise this only
        after measuring: if reranking is not a visible share of query
        latency, the VRAM is better spent keeping Ollama's models resident.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "ollama";
      description = ''
        Service user. Defaults to the Ollama user so a single modelDir can
        be managed alongside the Ollama store without a second set of
        permissions to reason about.
      '';
    };

    group = mkOption {
      type = types.str;
      default = "ollama";
      description = "Service group.";
    };

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = "Start at boot. Off by default, matching the Ollama instances.";
    };

    restrictEgress = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = [
        "localhost"
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
      ];
      description = ''
        Address ranges this service may reach, or null for no restriction.

        Same cgroup eBPF filter as the Ollama instances. Reranking is purely
        local once the GGUF is on disk, so this can be tightened to
        localhost alone if nothing off-host calls the endpoint.
      '';
    };

    extraFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [
        "--threads"
        "8"
      ];
      description = "Additional llama-server arguments, appended last.";
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.modelDir} 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.llama-reranker = {
      description = "llama.cpp reranking server";
      after = [ "network.target" ];
      wantedBy = lib.optional cfg.autoStart "multi-user.target";

      unitConfig.RequiresMountsFor = [ cfg.modelDir ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;

        ExecStart = "${lib.getExe' cfg.package "llama-server"} ${lib.escapeShellArgs flags}";

        Restart = "on-failure";
        RestartSec = 3;

        ReadOnlyPaths = [ cfg.modelDir ];

        # Nothing is written at runtime; the model is read and held in memory.
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;

        # Loosen these two if gpuLayers is raised: GPU backends need the
        # render nodes and, on the Vulkan path, a writable shader cache.
        PrivateDevices = cfg.gpuLayers == 0;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      }
      // lib.optionalAttrs (cfg.restrictEgress != null) {
        IPAddressDeny = "any";
        IPAddressAllow = cfg.restrictEgress;
      };
    };
  };
}
