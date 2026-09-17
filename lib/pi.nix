# Raspberry Pi deployment constraints.
#
# Board identity, module paths, and the nixos-raspberrypi base module attrpath.
{ lib, self }:
{
  validBoards = self.hardware.inFamily "raspberry-pi";

  # Which deploy modes each board can actually boot from.
  boardModes = {
    sd-image = self.pi.validBoards;
    pxe = [ "rpi5" ];
    remote = self.pi.validBoards;
    local = [ ]; # Pis are not built on themselves
    iso = [ ];
  };

  # Deploy-mode errors for a Pi chassis.
  deployErrors =
    { chassis, deployMode }:
    let
      allowed = self.pi.boardModes.${deployMode} or [ ];
    in
    lib.optional (!builtins.elem chassis allowed) (
      if allowed == [ ] then
        "deployMode '${deployMode}' is not supported on any Pi board"
      else
        "deployMode '${deployMode}' requires one of: ${lib.concatStringsSep ", " allowed} (got '${toString chassis}')"
    );
}
