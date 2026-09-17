# shellcheck disable=SC2148
# cd to the directory containing the first file matching a pattern.
#
# Depends on zoxide's `z` rather than plain cd, so the jump is recorded and
# the directory becomes reachable by frecency afterwards.
zfile() {
	if [ -z "${1:-}" ]; then
		printf 'Usage: zfile <filename>\n' >&2
		return 1
	fi

	_zf_match="$(fd --type f "${1}" 2>/dev/null | head -n 1)"

	if [ -z "${_zf_match}" ]; then
		printf 'zfile: no file matching %s\n' "${1}" >&2
		return 1
	fi

	z "$(dirname "${_zf_match}")"
}
