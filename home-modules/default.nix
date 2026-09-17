# Directory hook for nixSpace home-manager modules.
#
# Three subtrees by platform. NOTE: importing does not enable.
#
{ ... }:
{
  imports = [
    ./cross-platform
    ./darwin
    ./linux
  ];
}
