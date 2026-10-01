# Ettus USRP (UHD) software-defined radio support.
#
# Gated on the hw-uhd-sdr tag: the tag says the USRP hardware is attached.
# rtl-sdr dongles and other SDR software do not need this; see the `sdr` tag.
{
  config,
  lib,
  pkgs,
  nixSpaceLib,
  nixSpaceAttrs,
  ...
}:
let
  cfg = config.nixSpace.programs.uhdSdr;
in
{
  options.nixSpace.programs.uhdSdr = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = nixSpaceLib.tags.hasTag "hw-uhd-sdr" nixSpaceAttrs.tags;
      defaultText = lib.literalExpression ''hasTag "hw-uhd-sdr" nixSpaceAttrs.tags'';
      description = "Install UHD and its udev rules for Ettus USRP devices.";
    };

    package = lib.mkPackageOption pkgs "uhd" { };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # udev picks the rules up from the package's lib/udev/rules.d. Reading the
    # rules file into a string instead would make evaluation build UHD.
    services.udev.packages = [ cfg.package ];
  };
}
