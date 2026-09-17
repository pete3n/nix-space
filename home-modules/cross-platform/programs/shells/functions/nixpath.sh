# shellcheck disable=SC2148
# Resolve a command on PATH to its real store path.
#
# `command -v` gives the profile symlink; realpath follows it into the store,
# which is what you want when checking which build of something is active.
nixpath() {
	if [ -z "${1:-}" ]; then
		printf 'Usage: nixpath <binary>\n' >&2
		return 1
	fi

	_np_target="$(command -v "${1}" 2>/dev/null)" || {
		printf 'nixpath: %s not found on PATH\n' "${1}" >&2
		return 1
	}

	realpath "${_np_target}"
}
