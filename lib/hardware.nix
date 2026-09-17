# Hardware registry.
#
# `chassis` is a set containing overarching hardware specific configuration for
# a system.
#
# This module defines chassis identity, family, and the module path to
# configure it.
{ lib, self }:
let
  # family      - platform family; dispatches family-specific validation
  # modulePath  - relative path to system-modules
  # isEmbedded  - special configuration required; implies a Linux target
  # baseModule  - nixos-raspberrypi nixosModules attrpath, Pi only
  chassis = {
    # Fallback for machines with no dedicated chassis module.
    generic-pc = {
      description = "Generic x86_64 PC - no chassis-specific configuration";
      family = "pc";
      modulePath = "hardware/generic-pc";
      isEmbedded = false;
      baseModule = null;
    };
    framework16 = {
      description = "Framework 16 laptop";
      family = "pc";
      modulePath = "hardware/framework16";
      isEmbedded = false;
      baseModule = null;
    };
    framework-dt = {
      description = "Framework Desktop";
      family = "pc";
      modulePath = "hardware/framework-dt";
      isEmbedded = false;
      baseModule = null;
    };

    mac-mini-m1 = {
      description = "Apple Mac Mini M1";
      family = "apple-silicon";
      modulePath = "hardware/mac-mini-m1";
      isEmbedded = false;
      baseModule = null;
    };

    mac-mini-m4 = {
      description = "Apple Mac Mini M4";
      family = "apple-silicon";
      modulePath = "hardware/mac-mini-m4";
      isEmbedded = false;
      baseModule = null;
    };

    rpi02 = {
      description = "Raspberry Pi Zero 2 W";
      family = "raspberry-pi";
      modulePath = "hardware/raspberry-pi";
      isEmbedded = true;
      baseModule = "raspberry-pi-02";
    };
    rpi3 = {
      description = "Raspberry Pi 3 / 3B / 3B+";
      family = "raspberry-pi";
      modulePath = "hardware/raspberry-pi";
      isEmbedded = true;
      baseModule = "raspberry-pi-3";
    };
    rpi4 = {
      description = "Raspberry Pi 4";
      family = "raspberry-pi";
      modulePath = "hardware/raspberry-pi";
      isEmbedded = true;
      baseModule = "raspberry-pi-4";
    };
    rpi5 = {
      description = "Raspberry Pi 5";
      family = "raspberry-pi";
      modulePath = "hardware/raspberry-pi";
      isEmbedded = true;
      baseModule = "raspberry-pi-5";
    };
  };
in
{
  inherit chassis;

  valid = builtins.attrNames chassis;

  # Look up an entry, naming the valid set rather than throwing a bare
  # `attribute missing`.
  lookup =
    name:
    chassis.${name}
      or (throw "hardware.get: unknown chassis '${toString name}'. Must be one of: ${lib.concatStringsSep ", " (builtins.attrNames chassis)}");

  family = name: (self.hardware.lookup name).family;
  isEmbedded = name: (self.hardware.lookup name).isEmbedded;

  # Module directory, relative to the system-modules root. Callers join it:
  #   "${inputs.systemModules}/${nixSpaceLib.hardware.modulePath attrs.chassis}"
  modulePath = name: (self.hardware.lookup name).modulePath;

  # nixos-raspberrypi base module attrpath.
  #   nixosModules.${nixSpaceLib.hardware.baseModule attrs.chassis}.base
  baseModule =
    name:
    let
      entry = self.hardware.lookup name;
    in
    if entry.baseModule == null then
      throw "hardware.baseModule: chassis '${name}' has no base module (family '${entry.family}')"
    else
      entry.baseModule;

  # All chassis in a family. Used by family-specific modules (pi.nix) so board
  # lists are derived here rather than restated.
  inFamily =
    wanted: builtins.attrNames (lib.filterAttrs (_: (chassis: chassis.family == wanted)) chassis);
}
