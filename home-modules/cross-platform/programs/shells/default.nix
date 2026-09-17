# Directory hook for shell modules.
{ ... }:
{
  imports = [
		./shell.nix
    ./bash
    ./zsh
  ];
}
