# shellcheck disable=SC2148
# Run sudo against a command's real path.
#
# This function is meant for a host where the OS is not managed by Nix, 
# sudo resets PATH to a secure_path that does not include the Nix profile
# so `sudo somenixtool` fails with "command not found" even though the tool is
# on the caller's PATH. Resolving to the store path first sidesteps that,
# since the absolute path needs no PATH lookup.
#
# This is not needed where Nix manages the OS: there the profile is in the system
# PATH and sudo finds it.
#
# WARNING: this defeats sudo's own PATH sanitisation which is a risk:
# a command resolved from a compromised PATH is then run as root by absolute 
# path. This is just a workaround for a broken environment and shouldn't be used
# unless necessary.
sudo() {
	if [ $# -eq 0 ]; then
		command sudo
		return
	fi

	_ns_sudo_cmd="$(command -v "${1}" 2>/dev/null)" || _ns_sudo_cmd=""

	if [ -z "${_ns_sudo_cmd}" ]; then
		# Not on PATH: let sudo report it rather than failing here with a
		# different message.
		command sudo "$@"
		return
	fi

	_ns_sudo_real="$(realpath "${_ns_sudo_cmd}")"
	shift
	command sudo "${_ns_sudo_real}" "$@"
}
