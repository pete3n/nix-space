# Directory hook for PKI (certificate authority) system service modules.
{ ... }:
{
	imports = [
		./ssh-host-cert
		./step-ca
	];
}
