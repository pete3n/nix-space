# Directory hook for Linux system modules.
{ ... }:
{
  imports = [
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
