# Directory hook for PKI (certificate authority) system service modules.
{ ... }:
{
	imports = [
		./internal-acme
		./ssh-host-cert
		./step-ca
	];
}
