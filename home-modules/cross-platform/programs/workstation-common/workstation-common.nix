# Common workstation configuration.
#
# Shells, editors, version control, CLI tooling, and document handling —
# whatever a workstation wants regardless of desktop environment, compositor,
# or window manager.
#
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixSpace.programs.workstationCommon;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
{
  options.nixSpace.programs.workstationCommon = {
    enable = lib.mkEnableOption "the desktop-agnostic workstation defaults";
  };

  config = lib.mkIf cfg.enable {
    nixSpace = lib.mkMerge [
      {
        fonts.enable = lib.mkDefault true;
        xdg.enable = lib.mkDefault true;

        programs = lib.mkMerge [
          {
            aichat.enable = lib.mkDefault true;
            btop.enable = lib.mkDefault true;
            clip58.enable = lib.mkDefault true;
            core.enable = lib.mkDefault true;
            firefox.enable = lib.mkDefault true;
            lazydocker.enable = lib.mkDefault true;
            mediaPlayers.enable = lib.mkDefault true;
            net.enable = lib.mkDefault true;
            netsec.enable = lib.mkDefault true;
            nixTools.enable = lib.mkDefault true;
            remote.enable = lib.mkDefault true;
            starship.enable = lib.mkDefault true;
            yazi.enable = lib.mkDefault true;

            shells = {
              functions.tmuxPath = lib.mkDefault false; # true on home-alone hosts

              # TODO: coordinate bash/zsh through a tag. macOS defaults to zsh and
              # nix-darwin configures it at the system level, so enabling bash
              # here gives a darwin host two configured shells and neither is
              # obviously the login one.
              bash.enable = lib.mkDefault true;
            };

            terminals = {
              ghostty.enable = lib.mkDefault true;
              primary = lib.mkDefault "ghostty";
            };

            multiplexers.tmux.enable = lib.mkDefault true;

            git = {
              enable = lib.mkDefault true;
              keychain.enable = lib.mkDefault true;
            };

            # The suites are Linux-only; the viewers and document search are not,
            # so the module is enabled either way and only libreoffice is gated.
            office.enable = lib.mkDefault true;
          }
          (lib.optionalAttrs isLinux {
            mediaCreation.enable = lib.mkDefault true;
            office = {
							zathura.enable = lib.mkDefault true;
              libreoffice.enable = lib.mkDefault true;
            };
          })
        ];
      }
      (lib.optionalAttrs isLinux {
        # Toolkit theming: GTK settings, Qt platform themes, Kvantum, XCursor.
        # macOS applications use none of it. The appearance there is a system
        # setting rather than something a per-toolkit config file drives.
        theme.enable = lib.mkDefault true;

        services.mpd.enable = lib.mkDefault true;

        # cryptomator's GUI is x86_64-linux only and its CLI is Linux-only.
        security.filevaults.enable = lib.mkDefault true;
      })
    ];
  };
}
