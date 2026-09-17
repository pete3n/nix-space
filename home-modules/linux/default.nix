# Desktop environment settings shared by any compositor.
#
# GROUPED BY DIRECTORY, FLAT IN THE NAMESPACE. These three are one concern —
# how applications look and where they put things — so they live together.
# Their options stay at nixSpace.theme, nixSpace.xdg, and nixSpace.kde rather
# than under a nixSpace.desktopEnv prefix: there is only one of each, so the
# prefix would add a level without disambiguating anything.
#
# Same arrangement as linux/laptop/, which holds batmond and powerproud while
# their options are nixSpace.services.*.
#
# NOT ENABLED HERE. Importing a module and turning it on are separate acts.
# kde in particular is off by default — it pulls a slice of the KDE framework
# that a machine with no KDE applications gains nothing from.
{
  ...
}:
{
  imports = [
		./environment
		./programs
		./security
		./services
  ];
}
