# Directory hook for nixSpace packages.
{
  pkgs,
  nixSpaceLib,
  nixSpaceAttrs ? null,
}:
let
  system = if nixSpaceAttrs == null then pkgs.stdenv.hostPlatform.system else nixSpaceAttrs.system;

  importIf = path: if builtins.pathExists path then import path { inherit pkgs; } else { };
in
importIf ./cross-platform
// (if nixSpaceLib.platform.isLinux system then importIf ./linux else { })
// (if nixSpaceLib.platform.isDarwin system then importIf ./darwin else { })
