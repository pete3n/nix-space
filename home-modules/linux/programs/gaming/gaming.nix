# Game launchers and emulators.
#
# LINUX ONLY. Every launcher here depends on 32-bit libraries, udev rules for
# controllers, or both — none of which exist on Darwin.
#
# STEAM IS DIFFERENT FROM THE REST. It needs system-level setup that
# home-manager cannot provide: 32-bit driver libraries, udev rules for
# controllers, and firewall openings for Remote Play. Installing the package
# alone gives a Steam that starts and then fails to run most games.
#
#   programs.steam.enable = true;   # on the SYSTEM
#
# So this module does NOT install it, and says so rather than appearing to.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.gaming;

  # 86Box's Qt interface under native Wayland has historically rendered blank
  # or lost input, so it is pinned to XWayland.
  #
  # TEST BEFORE ASSUMING THIS IS STILL NEEDED — it costs a wrapper and gives
  # up Wayland's scaling:
  #
  #   QT_QPA_PLATFORM=wayland 86Box
  #
  # A window that appears and takes input means the override can go.
  box86 =
    if cfg.emulation.forceX11 then
      pkgs._86box-with-roms.overrideAttrs (old: {
        preFixup = (old.preFixup or "") + ''
          makeWrapperArgs+=(--set QT_QPA_PLATFORM "xcb")
        '';
      })
    else
      pkgs._86box-with-roms;
in
{
  options.nixSpace.programs.gaming = {
    enable = lib.mkEnableOption "game launchers and emulators";

    launchers = {
      heroic = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install Heroic Games Launcher.

          This is how GOG and Epic titles run on Linux — neither publisher
          ships a native client, and Heroic wraps their APIs plus Wine.
        '';
      };

      lutris = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install Lutris.

          Covers everything the storefront launchers do not: standalone
          installers, older Windows titles, and per-game Wine configuration.
        '';
      };

      bottles = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install Bottles, a Wine prefix manager.

          Overlaps heavily with Lutris — worth having only if you manage
          prefixes for non-game Windows software as well.
        '';
      };
    };

    emulation = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install emulators.

          Off by default: these are large, and unlike the launchers they are
          useless without media you supply yourself.
        '';
      };

      retroarch = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install RetroArch.

          A frontend, NOT an emulator — it needs cores, which are separate
          packages. Add them through emulation.retroarchCores; RetroArch with
          none installed presents an interface that can load nothing.
        '';
      };

      retroarchCores = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        example = lib.literalExpression ''
          with pkgs.libretro; [ snes9x mgba genesis-plus-gx ]
        '';
        description = ''
          Libretro cores to install alongside RetroArch.

          Empty by default rather than a guess at which systems matter to
          you — the full set is large and mostly unused on any given machine.
        '';
      };

      pcEmulation = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Install 86Box, which emulates period PC hardware rather than a
          console.

          For running software that expects a specific chipset or video card,
          where a modern VM's virtualised hardware is too new.
        '';
      };

      forceX11 = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run 86Box under XWayland instead of native Wayland.

          Its Qt interface has historically rendered blank or lost input on
          Wayland. Kept on by default because it is what currently works, not
          because the underlying problem is known to persist — test with
          `QT_QPA_PLATFORM=wayland 86Box` before turning it off.
        '';
      };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        example = lib.literalExpression "[ pkgs.dolphin-emu pkgs.pcsx2 ]";
        description = ''
          Additional emulators.

          Console emulators are specific enough that naming any as defaults
          would be guessing — this is where they go.
        '';
      };
    };

    gamemode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install the gamemode client library.

        The DAEMON is a system service (programs.gamemode.enable) and this
        does not enable it — without that, applications requesting gamemode
        get a no-op rather than an error, so the CPU governor and scheduling
        changes simply never happen.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression "[ pkgs.mangohud pkgs.protontricks ]";
      description = "Additional gaming-related packages.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (cfg.emulation.retroarch && cfg.emulation.retroarchCores == [ ]) ''
      nixSpace.programs.gaming.emulation.retroarch is enabled with no cores.
      RetroArch will start and be unable to load any content — set
      emulation.retroarchCores.
    '';

    home.packages =
      lib.optional cfg.launchers.heroic pkgs.heroic
      ++ lib.optional cfg.launchers.bottles pkgs.bottles
      ++ lib.optional cfg.gamemode pkgs.gamemode
      ++ lib.optionals cfg.emulation.enable (
        lib.optional cfg.emulation.retroarch pkgs.retroarch
        ++ cfg.emulation.retroarchCores
        ++ lib.optional cfg.emulation.pcEmulation box86
        ++ cfg.emulation.extraPackages
      )
      ++ cfg.extraPackages;

    # programs.lutris rather than the bare package: the module wires up the
    # Wine and DXVK runtime paths, which the package alone leaves to Lutris to
    # download at runtime into a mutable directory.
    programs.lutris.enable = cfg.launchers.lutris;
  };
}
