# Directory hook for Linux system modules.
{ ... }:
{
  imports = [
    ./archetypes
    ./environment
    ./hardware
    ./networking
    ./programs
    ./security
    ./security
    ./services
    ./users
  ];
}
