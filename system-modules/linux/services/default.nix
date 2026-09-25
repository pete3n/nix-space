# Directory hook for Linux system services modules.
{ ... }:
{
	imports = [
		./ai
		./crypto
		./hyprland
		./identity
		./laptop
		./networking
		./pki
		./printing
	];
}
