# shellcheck disable=SC2148
usage() {
	printf 'Usage: clip58 [string]\n' >&2
	printf '       ... | clip58\n' >&2
	exit 1
}

# An argument OR stdin, so this composes: `clip58 hello` and
# `printf %s hello | clip58` both work, and the second is what you want when
# the input came from somewhere else.
#
# ENCODER_CMD and CLIPBOARD_CMD are complete command lines, so eval re-splits
# them into words.
if [ "$#" -gt 1 ]; then
	usage
fi

if [ "$#" -eq 1 ]; then
	encoded="$(printf '%s' "${1}" | eval "${ENCODER_CMD}")"
elif [ ! -t 0 ]; then
	encoded="$(eval "${ENCODER_CMD}")"
else
	usage
fi

printf '%s' "${encoded}" | eval "${CLIPBOARD_CMD}"

# Also to stdout, so the result is visible and pipeable.
printf '%s\n' "${encoded}"
