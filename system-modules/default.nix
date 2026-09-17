# Directory hook for nixSpace system-modules.
{ ... }:
{
  imports = [
    ./cross-platform
    ./linux
  ];
}
