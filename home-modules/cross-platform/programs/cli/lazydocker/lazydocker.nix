# lazydocker Docker TUI module with added custom commands for attaching
# interactive shells to containers.
#
# NOTE: This module depends on docker daemon, which home-manager cannot provide.
# The upstream's default: programs.lazydocker.settings ships a non-empty
# default setting commandTemplates.dockerCompose. Any definition replaces it
# entirely, so this module recreates it: (see the composeCommand option.)
#
{
  config,
  lib,
  ...
}:
let
  cfg = config.nixSpace.programs.lazydocker;

  customCommandType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Label shown in lazydocker's menu.";
      };

      command = lib.mkOption {
        type = lib.types.str;
        example = "docker exec -it {{ .Container.ID }} /bin/sh";
        description = ''
          Command to run, as a Go template.

          The template variables are lazydocker's: {{ .Container.ID }},
          {{ .Image.Name }}, and so on, and an unrecognised one renders
          empty rather than failing, giving a command with a missing
          argument.
        '';
      };

      attach = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Attach to the command's terminal.

          True for anything interactive like a shell or an editor. False runs it
          in the background, where an interactive program appears to hang.
        '';
      };

      stream = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Stream output into lazydocker's panel rather than waiting for the
          command to finish.

          For long-running output. Mutually exclusive with attach in
          practice, though lazydocker does not reject both.
        '';
      };

      serviceNames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Compose services this command applies to.

          Empty means every service. A name that matches nothing hides the
          command rather than erroring.
        '';
      };

      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Longer text shown alongside the name.";
      };
    };
  };
in
{
  options.nixSpace.programs.lazydocker = {
    enable = lib.mkEnableOption "lazydocker";

    customCommands = {
      containers = lib.mkOption {
        type = lib.types.listOf customCommandType;
        default = [
          {
            name = "Interactive shell";
            command = "docker exec -it {{ .Container.ID }} /bin/sh";
            attach = true;
            description = "Open a shell in the running container.";
          }
          {
            name = "Interactive bash shell";
            command = "docker exec -it {{ .Container.ID }} /bin/bash";
            attach = true;
            description = "Open a bash shell, for images that have one.";
          }
        ];
        description = ''
          Custom commands available on containers.

          Both sh AND bash by default. Alpine and distroless images have no bash, 
          and a single bash entry fails on them with an exec error.
        '';
      };

      images = lib.mkOption {
        type = lib.types.listOf customCommandType;
        default = [
          {
            name = "Shell in new container";
            command = "docker run -it --rm {{ .Image.ID }} /bin/sh";
            attach = true;
            description = "Run a throwaway container from this image and open a shell.";
          }
        ];
        description = ''
          Custom commands available on images.

          The default uses --rm, so the container is removed on exit — this
          is for inspecting an image rather than starting something.
        '';
      };
    };

    composeCommand = lib.mkOption {
      type = lib.types.str;
      default = "docker compose";
      example = "podman compose";
      description = ''
        Command lazydocker invokes for compose operations.

        Set explicitly because upstream carries this as its `settings`, and a 
        default is discarded the moment any definition exists. So a module 
        that sets settings for any other reason silently reverts this to 
        lazydocker's own default, `docker-compose`, the hyphenated form that 
        modern Docker does not provide.

        The symptom is compose operations failing with command-not-found
        while everything else works.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = lib.literalExpression ''
        {
          gui.theme.activeBorderColor = [ "green" "bold" ];
          logs.timestamps = true;
        }
      '';
      description = ''
        Further lazydocker settings, merged over the custom commands above.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.lazydocker = {
      enable = true;

      settings = {
        commandTemplates.dockerCompose = cfg.composeCommand;
        customCommands = {
          inherit (cfg.customCommands) containers images;
        };
      }
      // cfg.settings;
    };
  };
}
