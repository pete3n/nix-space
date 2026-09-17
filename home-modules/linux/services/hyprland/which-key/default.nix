# Directory hook for the wlr-which-key integration module.
#
#   which-key.nix   the module: options and config
#   types.nix       submodule types for menu entries, binds, groups, style
#   generate.nix    pure functions from config to YAML and Hyprland binds
#   menu.nix        the base preset every Hyprland host gets
{ ... }:
{
  imports = [
    ./which-key.nix
    ./menu.nix
  ];
}
