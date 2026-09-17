# NixOS module register.
#
# Maps chassis and tags to modules. This is the ONE place that mapping lives —
# a per-host configuration.nix should never repeat it, or a new tag means
# editing every host.
#
# Chassis is a path lookup, not a gate: the `chassis` metadata field resolves
# to a directory that owns its own quirk modules. Component tags stay tags
# because zero-or-more is genuinely a list.
#
# TODO: shell tags for bash/zsh to configuration both user and home shell options
{
  lib,
  nixSpaceLib,
  nixSpaceAttrs,
  ...
}:
let
  hasTag = tag: nixSpaceLib.tags.hasTag tag nixSpaceAttrs.tags;

  chassisDir = ./. + "/${nixSpaceLib.hardware.modulePath nixSpaceAttrs.chassis}";
  displayServer = nixSpaceLib.tags.displayServerFor nixSpaceAttrs.tags;

  # Module attribute set, key is the tag name and value is the path to load
  # for the module
  tagModules = {
    crypto = [
      ./linux/crypto/bitcoind.nix
      ./linux/crypto/monero.nix
      {
        nixSpace.crypto.bitcoind.enable = true;
        nixSpace.crypto.monero.enable = true;
      }
    ];
    hyprland = [ ./linux/wm/hyprland.nix ];
    laptop = [ ./linux/laptop/lidmond.nix ];
    local-ai = [
      ./linux/ai/ollama.nix
      ./linux/ai/open-webui.nix
      {
        nixSpace.ai.ollama.enable = true;
        nixSpace.ai.openWebui.enable = true;
      }
    ];
    virtualisation = [ ./linux/virtualisation.nix ];
    yubi-u2f = [ ./linux/yubikey/yk-u2f.nix ];

    hw-uhd-sdr = [ ./hardware/misc/uhd-sdr.nix ];

    hw-nvidia-dgpu = [
      ./hardware/gpu/nvidia-prime.nix
      {
        nixSpace.hardware.gpu.nvidiaPrime = {
          enable = true;
          inherit displayServer;
        };
      }
    ];

    p22 = [
      ./cross-platform/nix-cache.nix
      { nixSpace.nix.cache.enable = true; }

      ./cross-platform/build-client.nix
      {
        nixSpace.nix.distributedBuilds = {
          enable = true;
          machines.framework-dt = {
            system = "x86_64-linux";
            maxJobs = 28; # 32 cores - 4
            speedFactor = 4;
            publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO70Au6FegohwKFygshDnN9TGll69m4cc1WXMqa8tXl/";
          };
        };
      }
      #./cross-platform/p22-pki.nix
      #./hardware/printers/p22-printers.nix
      ./linux/p22-nfs.nix
      ./linux/nfs-client.nix
      {
        nixSpace.nfs = {
          enable = true;
          server = "backupsvr.p22";
          shares = {
            share.remotePath = "/mnt/user/share";
            open.remotePath = "/mnt/user/open";
          };
        };
      }
    ];
  };

  # Modules that are loaded only if the complete list of tags are matched.
  multiTagModules = [
    {
      tags = [
        "yubi-u2f"
        "hw-fprint"
      ];
      modules = [ ./linux/yubikey/yk-fprint.nix ];
    }
    {
      tags = [
        "yubi-u2f"
        "yubi-usbip-client"
      ];
      modules = [ ./linux/yubikey/yk-usbip-client.nix ];
    }
    {
      tags = [
        "yubi-u2f"
        "yubi-usbip-server"
      ];
      modules = [ ./linux/yubikey/yk-usbip-server.nix ];
    }
  ];

  # Identify all the tags that have module paths assigned.
  handledTags = lib.unique (
    builtins.attrNames tagModules ++ lib.concatMap (entry: entry.tags) multiTagModules
  );

  # NixOS tags handle system level linux configuration.
  expectedTags = lib.subtractLists nixSpaceLib.tags.user (
    nixSpaceLib.tags.systemOnly ++ nixSpaceLib.tags.linuxOnly
  );

  # Invalid tags.
  bogusTags = lib.subtractLists nixSpaceLib.tags.valid handledTags;

  # Tags configured for this host that have no module.
  unhandledTags = lib.subtractLists handledTags (lib.intersectLists expectedTags nixSpaceAttrs.tags);
in
lib.throwIf (bogusTags != [ ])
  "nixos.nix: tag gate(s) reference unregistered tag(s): ${lib.concatStringsSep ", " bogusTags} (typo, or missing from tag-registry.nix)"
  (
    lib.warnIf (unhandledTags != [ ])
      "nixos.nix: host declares tag(s) with no system module: ${lib.concatStringsSep ", " unhandledTags}"
      {
        imports = [
          chassisDir
        ]
        ++ lib.concatLists (
          lib.mapAttrsToList (tag: (modules: lib.optionals (hasTag tag) modules)) tagModules
        )
        ++ lib.concatMap (entry: lib.optionals (lib.all hasTag entry.tags) entry.modules) multiTagModules;
      }
  )
