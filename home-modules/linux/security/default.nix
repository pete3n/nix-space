# Directory hook for linux security modules.
{ ... }:
{
  imports = [
    ./filevaults
		./yubikey
  ];
}
