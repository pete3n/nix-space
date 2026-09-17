# Directory hook for laptop user service modules.
#
# These modules handle laptop specific service tasks such as lid-closing events
# and battery status monitoring. 
#
# These are userland services that generally require pairing with system-level
# service modules. 
{
  ...
}:
{
  imports = [
    ./batmond
    ./powerproud
  ];
}
