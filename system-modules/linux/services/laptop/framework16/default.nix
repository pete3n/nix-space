# Directory hook for Framework16 service modules.
{ ... }:
{
	imports = [
		./kbd-alsd
		./port-recovery
		./ucsi-rebind
		./wake-triggers
	];
}
