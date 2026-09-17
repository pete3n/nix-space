# Directory hook for Linux system services modules.
{ ... }:
{
	imports = [
		./ai
		./crypto
		./hyprland
		./laptop
		./networking
		./printing
	];
}
