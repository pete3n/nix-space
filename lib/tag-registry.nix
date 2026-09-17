# Tag registry and classification.
#
# WHAT A TAG IS FOR. Tags coordinate configuration across a boundary that
# neither side can see over: the NixOS configuration and the home-manager
# configuration cannot read each other's options, so a fact both need to act
# on — "this host runs Hyprland", "this user's YubiKey does U2F" — is declared
# once in the attrs file and read by both.
#
# The test for adding one: does more than one module system need to agree on
# it? If one side can decide alone, that is an option, not a tag. `office` and
# `messaging` are home-only and their tags are just longer spellings of
# `enable = true`.
#
# WHAT A TAG IS NOT FOR: selecting what gets imported. Every module is
# imported unconditionally, the way nixpkgs and home-manager do it; a tag is
# read at an enable site, not an import site.
{ lib, self }:
let

  # System-level user configuration.
  user = [
    "git-ssh-user"
    "gpg-user"
    "power-user"
    "ssh-user"
    "sudo-user"
    "trusted-user"
    "vm-user"
    "vpn-user"
    "yubi-age-user"
  ];

  # Hardware configuration and accessory tags.
  #
  # The specific GPU tags say WHICH card; hw-amd-gpu says only THAT there is
  # one, and is implied by either specific tag (see impliedTags). Declare the
  # specific tag on a host; require the general one where any AMD GPU will
  # do. The distinction matters because ROCm works on the integrated 890M as
  # well as a discrete card, so a requirement on hw-amd-dgpu alone rejects
  # the machine where ROCm is most deliberately in use.
  hardware = [
		"hw-amd-gpu"
    "hw-amd-dgpu"
    "hw-amd-igpu"
    "hw-amd-gpu"
    "hw-nvidia-dgpu"
    "hw-fprint"
    "hw-uhd-sdr"
  ];

  # Tags that carry others with them. Declaring the key tag makes the listed
  # tags present too, so a host tags what it HAS and a requirement names what
  # it NEEDS without the two having to use the same word.
  #
  # Applied by expandTags below, which attrs loading must call before any
  # check — a requirement on an implied tag cannot be satisfied otherwise.
  impliedTags = {
    hw-amd-dgpu = [ "hw-amd-gpu" ];
    hw-amd-igpu = [ "hw-amd-gpu" ];
  };

  # Applicable only to NixOS or nix-darwin systems, never a home-alone config.
  systemOnly = [
    "cuda"
    "local-ai"
    "rocm"
  ]
  ++ user
  ++ hardware;

  # Window managers and desktop environments, mapped to the display server
  # they present. Plasma is a desktop rather than a compositor — KWin is the
  # compositor — but it sits in this table because the table is really "what
  # owns the session", and only one thing can.
  wm-compositors = {
    aerospace = "quartz";
    awesome-wm = "x11";
    hyprland = "wayland";
    i3 = "x11";
    niri = "wayland";
    plasma = "wayland";
    sway = "wayland";
  };

  darwinOnly = [
    "aerospace"
  ];

  linuxOnly = [
    "i3"
    "niri"
    "sway"
    "awesome-wm"
    "cuda"
    "hyprdesktop"
    "hyprland"
    "local-ai"
    "mpd"
    "plasma"
    "plasmadesktop"
    "rocm"
    "yubi-usbip-client"
    "yubi-usbip-server"
    "yubi-ssh-import"
    "yubi-u2f"
  ]
  ++ hardware;

  piOnly = [
    "pi-usb-gadget" # USB OTG/ethernet gadget mode (Zero 2W, CM4)
    "pi-camera" # libcamera / camera module support
    "pi-gpio" # GPIO access
  ];

  # Applicable to both home and system configurations on any platform.
  misc = [
    "aichat"
    "crypto"
    "gaming"
    "git"
    "laptop"
    "media-creation"
    "messaging"
    "nixvim"
    "office"
    "p22"
    # sdr: software-defined radio userspace (gnuradio, soapysdr). Distinct
    # from hw-uhd-sdr, which is the USRP hardware — rtl-sdr dongles need the
    # software and not that hardware.
    "sdr"
    "virtualisation"
  ];

  valid = lib.unique (systemOnly ++ darwinOnly ++ linuxOnly ++ piOnly ++ misc);

  # Tags that require other tags. Directional, unlike exclusiveGroups.
  #
  # ALL listed tags are required. Where a requirement is satisfiable by
  # alternatives, name a general tag and have the alternatives imply it —
  # see impliedTags and hw-amd-gpu.
  #
  # These are not transitive relationships: If a requires b and b requires c,
  # declaring a alone reports only b as missing; c surfaces on the next pass.
  #
  # This expresses "X is meaningless without Y", not "X and Y are both needed
  # to load a module". That relationship is covered by multiTagModules.
  requiredTags = {
    # CUDA userspace without the NVIDIA kernel driver installs cleanly and
    # fails at runtime with "no CUDA-capable device found".
    cuda = [ "hw-nvidia-dgpu" ];

    hyprdesktop = [ "hyprland" ];

    plasmadesktop = [ "plasma" ];

    # ROCm userspace without an AMD GPU installs cleanly and finds no device.
    # Any AMD GPU will do — the integrated 890M runs it — hence the general
    # tag rather than hw-amd-dgpu.
    rocm = [ "hw-amd-gpu" ];

    # vm-user grants membership in the libvirtd group, which only exists when
    # libvirtd is enabled. Without it, activation fails with "group libvirtd
    # does not exist" — legible, but from the wrong place.
    vm-user = [ "virtualisation" ];
  };

  unknownCompositors = lib.subtractLists valid (builtins.attrNames wm-compositors);

  # Both sides of the dependency map must name registered tags. A dependency
  # on a non-tag can never be satisfied, and a dependency keyed on a non-tag
  # can never fire.
  unknownDeps = lib.subtractLists valid (
    builtins.attrNames requiredTags ++ lib.concatLists (builtins.attrValues requiredTags)
  );

  unknownImplied = lib.subtractLists valid (
    builtins.attrNames impliedTags ++ lib.concatLists (builtins.attrValues impliedTags)
  );
in
lib.throwIf (unknownCompositors != [ ])
  "tag-registry: compositors table references unregistered tag(s): ${lib.concatStringsSep ", " unknownCompositors}"
  (
    lib.throwIf (unknownDeps != [ ])
      "tag-registry: requiredTags references unregistered tag(s): ${lib.concatStringsSep ", " unknownDeps}"
      (
        lib.throwIf (unknownImplied != [ ])
          "tag-registry: impliedTags references unregistered tag(s): ${lib.concatStringsSep ", " unknownImplied}"
          {
            inherit
              user
              hardware
              systemOnly
              darwinOnly
              linuxOnly
              piOnly
              misc
              valid
              wm-compositors
              ;

            inherit requiredTags impliedTags;

            # Adds every implied tag to a declared list. Idempotent, and
            # one level only — an implication that itself implies something
            # is not followed, for the same reason requiredTags is not
            # transitive.
            expandTags =
              tags: lib.unique (tags ++ lib.concatMap (t: impliedTags.${t} or [ ]) tags);

            # Mutually exclusive tag groups. Members cannot co-exist.
            exclusiveGroups = {
              # Discrete cards only. An AMD iGPU alongside an NVIDIA dGPU is
              # the framework16, and is fine.
              dgpu = [
                "hw-amd-dgpu"
                "hw-nvidia-dgpu"
              ];
              wm-compositor = builtins.attrNames wm-compositors;

              # A machine either shares its own key or attaches someone
              # else's. Both at once would have vhci_hcd and usbip_host
              # contending for the same device.
              usbip-role = [
                "yubi-usbip-client"
                "yubi-usbip-server"
              ];
            };

            displayServerFor =
              tagList:
              let
                matched = builtins.filter (tag: wm-compositors ? ${tag}) tagList;
              in
              if matched == [ ] then null else wm-compositors.${builtins.head matched};

            hasTag = tag: (tags: builtins.elem tag tags);

            invalidTags = tags: builtins.filter (tag: !builtins.elem tag self.tags.valid) tags;

            # Returns a list of human-readable misuse strings for a given
            # context. Returning strings rather than tracing lets the caller
            # decide whether these are warnings or errors, and lets both the
            # directory loader and the single-file loader share one
            # implementation.
            #
            # Expects EXPANDED tags. Pass declared tags through expandTags
            # first, or requirements on implied tags will report as missing.
            misuse =
              {
                tags,
                system,
                isHomeAlone ? false,
                isPi ? false,
              }:
              let
                matchedTags = category: builtins.filter (tag: builtins.elem tag category) tags;
                checkTags =
                  cond: category: label:
                  let
                    used = matchedTags category;
                  in
                  lib.optional (cond && used != [ ]) "${label}: ${lib.concatStringsSep ", " used}";

                exclusive = lib.concatLists (
                  lib.mapAttrsToList (
                    group: members:
                    let
                      used = matchedTags members;
                    in
                    lib.optional (
                      builtins.length used > 1
                    ) "mutually exclusive ${group} tags: ${lib.concatStringsSep ", " used}"
                  ) self.tags.exclusiveGroups
                );

                missingDeps = lib.concatLists (
                  lib.mapAttrsToList (
                    tag: needs:
                    let
                      absent = lib.subtractLists tags needs;
                    in
                    lib.optional (
                      builtins.elem tag tags && absent != [ ]
                    ) "tag '${tag}' requires: ${lib.concatStringsSep ", " absent}"
                  ) self.tags.requiredTags
                );
              in
              checkTags isHomeAlone self.tags.systemOnly "home-alone configs cannot use system-only tags"
              ++
                checkTags (self.platform.isLinux system) self.tags.darwinOnly
                  "Linux configs cannot use Darwin-only tags"
              ++
                checkTags (self.platform.isDarwin system) self.tags.linuxOnly
                  "Darwin configs cannot use Linux-only tags"
              ++ checkTags (
                self.platform.isLinux system && !isPi
              ) self.tags.piOnly "Chassis must be set to raspberry-pi to use Pi only tags"
              ++ exclusive
              ++ missingDeps;
          }
      )
  )
