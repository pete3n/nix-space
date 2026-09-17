# Directory hook for Linux environment configuration modules.
{ ... }:
{
  imports = [
    ./kde
		./hyprdesktop
    ./plasmadesktop
    ./theme
  ];
}
