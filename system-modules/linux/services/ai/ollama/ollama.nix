# Ollama inference server, with optional additional instances.
#
# GPU acceleration options are chosen by the package selection.
#
# Multi-GPU support. A host can run an instance per accelerator sharing a
# model store. `extraInstances` can be used to configure additional instances.
#
# With egress restricted, `ollama pull` cannot reach anything. ollama-import
# feeds a GGUF fetched by other means into the shared store instead.
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

  cfg = config.nixSpace.services.ollama;

  # A wildcard listen address is not a connectable target; the client goes to
  # loopback in that case.
  clientHost =
    if
      lib.elem cfg.host [
        "0.0.0.0"
        "[::]"
        "::"
      ]
    then
      "127.0.0.1"
    else
      cfg.host;

  # The same build as the primary server, so client and server agree on the
  # API. With a local FROM path the client hashes and uploads the blob itself,
  # so no filesystem access to modelPath is needed by whoever runs this.
  ollamaImport = pkgs.writeShellApplication {
    name = "ollama-import";
    runtimeInputs = [
      cfg.package
      pkgs.coreutils
    ];

    text = # sh
    ''
      export OLLAMA_HOST="''${OLLAMA_HOST:-${clientHost}:${toString cfg.port}}"
    ''
    + builtins.readFile ./ollama-import.sh;
  };

  instanceOpts =
    { name, ... }:
    {
      options = {
        package = mkOption {
          type = types.package;
          example = lib.literalExpression "pkgs.ollama-vulkan";
          description = "Ollama build for this instance's accelerator.";
        };

        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          example = "[::]";
          description = "Address this instance listens on.";
        };

        port = mkOption {
          type = types.port;
          default = 11435;
          description = "Port this instance listens on.";
        };

        stateDir = mkOption {
          type = types.str;
          default = "/var/lib/ollama-${name}";
          description = ''
            Per-instance runtime state. Kept separate from the shared model
            store: history and caches must not be shared, models must be.
          '';
        };

        environment = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = ''
            Extra environment for this instance. Use it to select and hide
            accelerators such as: CUDA_VISIBLE_DEVICES, GGML_VK_VISIBLE_DEVICES,
            VK_DRIVER_FILES.
          '';
        };
      };
    };
in
{
  options.nixSpace.services.ollama = {
    enable = mkEnableOption "Ollama inference server";

    package = mkOption {
      type = types.package;
      default = pkgs.ollama;
      defaultText = lib.literalExpression "pkgs.ollama";
      example = lib.literalExpression "pkgs.unstable.ollama-cuda";
      description = ''
        Ollama build for the primary instance. Set this to the accelerated
        variant your hardware needs.
      '';
    };

    modelPath = mkOption {
      type = types.str;
      default = "/var/lib/ollama-shared/models";
      example = "/mnt/data/ollama/models";
      description = ''
        Shared model store, read by every instance. Multi-GB GGUF blobs are
        stored once rather than per instance. This is a runtime path that is
        not copied to the Nix store.
      '';
    };

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      example = "[::]";
      description = ''
        Address the primary instance listens on.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 11434;
      description = ''
        Port the primary instance listens on.
      '';
    };

    autoStart = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Start instances at boot. Off by default.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = {
        OLLAMA_KEEP_ALIVE = "30m";
        OLLAMA_MAX_LOADED_MODELS = "2"; # Allow embedder + generator for RAG
        OLLAMA_FLASH_ATTENTION = "1";
        OLLAMA_CONTEXT_LENGTH = "8192";
        OLLAMA_KV_CACHE_TYPE = "q8_0";
      };
      description = "Environment for the primary instance.";
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
        Address ranges instances may reach, or null for no restriction.

        Rendered as a systemd cgroup eBPF filter. Longest-prefix match means
        these allows beat the implicit 0.0.0.0/0/::/0 deny, so anything
        outside is dropped. localhost covers the frontend hop and the
        systemd-resolved stub at 127.0.0.53.

        Null disables any network restrictions.
      '';
    };

    extraInstances = mkOption {
      type = types.attrsOf (types.submodule instanceOpts);
      default = { };
      example = lib.literalExpression ''
        {
          vulkan = {
            package = pkgs.unstable.ollama-vulkan;
            port = 11435;
            environment = {
              CUDA_VISIBLE_DEVICES = "-1";
              OLLAMA_IGPU_ENABLE = "1";
              OLLAMA_VULKAN = "1";
              VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";
            };
          };
        }
      '';
      description = ''
        Additional instances, one per accelerator, sharing modelPath.

        Each runs as the static `ollama` user so the shared store is readable.
        nixpkgs' services.ollama uses DynamicUser by default, which assigns
        ephemeral UIDs and makes sharing impossible.
      '';
    };
  };

  config = mkIf cfg.enable (
    let
      egress = lib.optionalAttrs (cfg.restrictEgress != null) {
        IPAddressDeny = "any";
        IPAddressAllow = cfg.restrictEgress;
      };

      # True when models sit outside the default path.
      relocated = cfg.modelPath != "/var/lib/ollama-shared/models";

      mkInstance = name: inst: {
        description = "Ollama instance: ${name}";
        after = [
          "network-online.target"
          "ollama.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = lib.optional cfg.autoStart "multi-user.target";

        unitConfig.RequiresMountsFor = mkIf relocated [ cfg.modelPath ];

        environment =
          cfg.environment
          // {
            OLLAMA_HOST = "${inst.host}:${toString inst.port}";
            OLLAMA_HOME = inst.stateDir;
            OLLAMA_MODELS = cfg.modelPath;
            HOME = inst.stateDir;
            XDG_CACHE_HOME = "${inst.stateDir}/.cache";
            OLLAMA_LOAD_TIMEOUT = "15m";
          }
          // inst.environment;

        serviceConfig = {
          Type = "simple";
          User = "ollama";
          Group = "ollama";
          ExecStart = "${lib.getExe inst.package} serve";
          Restart = "on-failure";
          RestartSec = 3;
          StateDirectory = baseNameOf inst.stateDir;
          WorkingDirectory = inst.stateDir;
          ReadWritePaths = [ cfg.modelPath ];
        }
        // egress;
      };
    in
    {
      services.ollama = {
        enable = true;
        models = cfg.modelPath;
        inherit (cfg) package host port;

        # Static user/group so extra instances can share the model store.
        user = "ollama";
        group = "ollama";

        environmentVariables = cfg.environment;
      };

      environment.systemPackages = [ ollamaImport ];

      # The shared model dir is outside any StateDirectory, so nothing else
      # creates it.
      systemd.tmpfiles.rules = [
        "d ${cfg.modelPath} 0750 ollama ollama - -"
      ];

      systemd.services = lib.mkMerge [
        {
          ollama = {
            unitConfig.RequiresMountsFor = mkIf relocated [ cfg.modelPath ];
            serviceConfig = egress;
            wantedBy = lib.mkForce (lib.optional cfg.autoStart "multi-user.target");
          };
        }
        (lib.mapAttrs' (
          name: inst: lib.nameValuePair "ollama-${name}" (mkInstance name inst)
        ) cfg.extraInstances)
      ];
    }
  );
}
