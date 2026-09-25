# Directory hook for Linux system modules.
{ ... }:
{
  imports = [
    ./archetypes
    ./environment
    ./hardware
    ./identity-login
    ./networking
    ./programs
    ./security
    ./security
    ./services
    ./users
  ];
}
