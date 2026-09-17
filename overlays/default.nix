# nixSpace package overlays.
#
# Provides a shared overlay to provide easy access to unstable packages and
# library specific packages.
#
# Every overlay here takes its inputs from `final` rather than
# `prev`, so the fixpoint resolves them regardless of position in the list.
{
  nixpkgs-unstable,
  nixSpaceLib,
  nixSpaceAttrs ? null,
  ...
}:
let
  # The target system, when the caller supplied attrs, else the system of the
  # package set being built.
  #
  # These differ under cross-compilation: `final.stdenv.hostPlatform.system`
  # is what pkgs is actually producing, while nixSpaceAttrs.system is what the
  # configuration declares. Preferring the attrs keeps a cross build importing
  # the same package sets the target would, which is usually what is intended.
  systemFor =
    final: if nixSpaceAttrs == null then final.stdenv.hostPlatform.system else nixSpaceAttrs.system;

  # The unstable nixpkgs set, reachable as pkgs.unstable.
  unstable-packages = final: _prev: {
    unstable = import nixpkgs-unstable {
      system = systemFor final;
      config.allowUnfree = true;
    };
  };

  # Shared nixSpace packages: reachable as pkgs.ns.
  nix-space-packages = final: _prev: {
    nsPkgs = import ../packages {
      pkgs = final;
      inherit nixSpaceLib nixSpaceAttrs;
    };
  };
in
{
  inherit unstable-packages nix-space-packages;

  # Functions to pin packages to specfic versions.
  #
  # They replace the packages at top level so every configuration resolves to the
  # same build. The portal is pinned because mismatched versions will produce
  # bugs that are difficult to diagnose.
  #
  pins = {
    # Called as:
    #
    #   (nsOverlays.pins.hyprland inputs.Hyprland)
    # NOTE on flakehub ranges: a bare "0.56.1" is a RANGE and resolves forward.
    # Use "=0.56.1" or a bare rev to pin.
    # Pinned at v0.56.1. because 0.56.2 currently fails to build as of 15-SEP-26
    hyprland =
      hyprlandInput: final: _prev:
      let
        system = systemFor final;
      in
      {
        hyprland = hyprlandInput.packages.${system}.hyprland;
        xdg-desktop-portal-hyprland = hyprlandInput.packages.${system}.xdg-desktop-portal-hyprland;
      };
  };

  # Final overlay list
  shared = [
    unstable-packages
    nix-space-packages
  ];
}
