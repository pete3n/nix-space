# Home-manager module register for Linux specific modules.
#
# Maps tags to home-manager modules. Companion to darwin.nix.
#
# Home-alone: this register serves both NixOS hosts and machines whose OS is
# not managed by nix (Debian, Fedora). Modules that assume a system-level
# counterpart must handle isHomeAlone themselves.
{
  lib,
  nixSpaceLib,
  nixSpaceAttrs,
  ...
}:
let
  hasTag = tag: nixSpaceLib.tags.hasTag tag nixSpaceAttrs.tags;

  # Module attribute set, key is the tag name and value is the path to load
  # for the module
  tagModules = {
    aichat = [ ./aichat ];
    awesome-wm = [ ./linux/awesome-wm ];
    git = [ ./git ];
    gpg-user = [ ./gpg ];
    hyprdesktop = [ ./linux/hyprland/hyprdesktop/ ];
    hyprland = [ ./linux/hyprland ];
    laptop = [ ./linux/laptop ];
    media-creation = [ ./media-creation ];
    messaging = [ ./messaging ];
    mpd = [ ./linux/mpd ];
    nixvim = [ ./nixvim ];
    sdr = [ ./sdr ];
    p22 = [ ./p22 ];
    yubi-u2f = [ ./linux/yubikey/u2f ];
  	yubi-age-user = [ ./security/yubikey ];
  };

  # Modules that are loaded only if the complete list of tags are matched.
  multiTagModules = [
    {
      tags = [
        "hyprdesktop"
        "mpd"
      ];
      modules = [
        ./linux/wm/waybar/mpd.nix
        ./linux/wm/hyprland/desktop/mpd-visualizer.nix
      ];
    }
    {
      tags = [
        "laptop"
        "hyprland"
      ];
      modules = [ ./linux/wm/hyprland/hyprlidmon.nix ];
    }
  ];

  # Identify all the tags that have module paths assigned.
  handledTags = lib.unique (
    builtins.attrNames tagModules ++ lib.concatMap (entry: entry.tags) multiTagModules
  );

  # Tags this register could plausibly handle. The registry has no homeOnly
  # category, so this is derived by subtraction: everything valid, minus what
  # only a system layer can act on, minus Darwin-only and Pi-only.
  expectedTags = lib.subtractLists (
    nixSpaceLib.tags.systemOnly ++ nixSpaceLib.tags.darwinOnly ++ nixSpaceLib.tags.piOnly
  ) nixSpaceLib.tags.valid;

  # Invalid tags.
  bogusTags = lib.subtractLists nixSpaceLib.tags.valid handledTags;

  # Tags configured for this host that have no module.
  unhandledTags = lib.subtractLists handledTags (lib.intersectLists expectedTags nixSpaceAttrs.tags);
in
lib.throwIf (bogusTags != [ ])
  "home-modules/linux.nix: tag gate(s) reference unregistered tag(s): ${lib.concatStringsSep ", " bogusTags} (typo, or missing from tag-registry.nix)"
  (
    lib.warnIf (unhandledTags != [ ])
      "home-modules/linux.nix: host declares tag(s) with no home module: ${lib.concatStringsSep ", " unhandledTags}"
      {
        imports = [
          # Always present: identity, stateVersion, XDG, and the Linux
          # session variables that differ because the OS is Linux rather
          # than because of any feature.
          ./base
          ./linux/base
        ]
        ++ lib.concatLists (
          lib.mapAttrsToList (tag: (modules: lib.optionals (hasTag tag) modules)) tagModules
        )
        ++ lib.concatMap (entry: lib.optionals (lib.all hasTag entry.tags) entry.modules) multiTagModules;
      }
  )
