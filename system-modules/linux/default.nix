# Directory hook for Linux system modules.
{ ... }:
{
  imports = [
    ./archetypes
    ./environment
    ./hardware
    ./identity-login
    ./identity-breakglass
    ./networking
    ./programs
    ./security
    ./security
    ./services
    ./users
  ];
}
