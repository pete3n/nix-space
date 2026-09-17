# System-level user configuration (nix-darwin).
#
# Reads the same role registry as linux-user.nix. `groups` is ignored here because
# Darwin has no equivalent supplementary-group model.
#
{
  lib,
  nixSpaceAttrs,
  nixSpaceLib,
  pkgs,
  ...
}:
let
  inherit (nixSpaceLib) users hasTag;
  attrs = nixSpaceAttrs;
  isTagged = tag: hasTag tag attrs.tags;

  secrets = ./. + "/${attrs.user}/secrets";
in
{
  imports =
    lib.optionals (isTagged "yubi-age-user") [ (secrets + "/yubi-age.nix") ]
    ++ lib.optionals (isTagged "vpn-user") [ (secrets + "/p22-vpn.nix") ];

  users.users.${attrs.user} = {
    home = "/Users/${attrs.user}";
    shell = pkgs.zsh;
    description = users.description attrs;
  };

  nix.settings.trusted-users = [ "@admin" ] ++ lib.optional (users.isTrusted attrs) attrs.user;
}
