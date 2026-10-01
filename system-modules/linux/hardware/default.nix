# Directory hook for Linux hardware system modules.
{ ... }:
{
  imports = [
    ./framework16
    ./generic-pc
    ./gpu
    ./libvirt-vm
  ];
}
