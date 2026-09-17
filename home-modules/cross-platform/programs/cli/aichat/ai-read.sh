# shellcheck disable=SC2148
file="${1:-}"
offset="${2:-0}"
text_tmp=""

cleanup() {
	[ -z "${text_tmp}" ] || rm -f "${text_tmp}"
}
trap cleanup EXIT INT TERM

if [ -z "${file}" ]; then
	printf 'Usage: ai-read <file> [offset%%]\n' >&2
	exit 1
fi

if [ ! -f "${file}" ]; then
	printf 'ai-read: file not found: %s\n' "${file}" >&2
	exit 1
fi

if [ ! -f "${PIPER_MODEL}" ]; then
	printf 'ai-read: model not found at %s — run ai-models-fetch\n' "${PIPER_MODEL}" >&2
	exit 1
fi

case "${offset}" in
	""|*[!0-9]*) offset=-1 ;;
esac
if [ "${offset}" -lt 0 ] || [ "${offset}" -gt 99 ]; then
	printf 'ai-read: offset must be a whole number between 0 and 99\n' >&2
	exit 1
fi

# Assigned AFTER the trap is installed, so an early exit above cannot leave a
# temp file behind.
text_tmp="$(mktemp)"

mime="$(file --mime-type -b "${file}")"

case "${mime}" in
	application/pdf)
		pdftotext "${file}" - > "${text_tmp}"
		;;
	application/vnd.openxmlformats-officedocument.wordprocessingml.document|application/msword)
		pandoc --to plain "${file}" > "${text_tmp}"
		;;
	text/*)
		cat "${file}" > "${text_tmp}"
		;;
	*)
		printf 'ai-read: unsupported mime type: %s\n' "${mime}" >&2
		exit 1
		;;
esac

total="$(wc -c < "${text_tmp}")"
skip_bytes=$((total * offset / 100))

# Advance to the next word boundary so playback does not start mid-word. A
# zero offset reads from the very start rather than skipping the first word.
start="$(
	awk -v skip="${skip_bytes}" '
		BEGIN { bytes = 0; found = (skip <= 0) }
		{
			if (found) { print; next }
			line_len = length($0) + 1
			if (bytes + line_len > skip) {
				char_pos = skip - bytes
				if (char_pos < 1) char_pos = 1
				space_pos = index(substr($0, char_pos), " ")
				if (space_pos > 0) {
					print substr($0, char_pos + space_pos)
				} else {
					print $0
				}
				found = 1
			} else {
				bytes += line_len
			}
		}' "${text_tmp}"
)"

# AUDIO_PLAYER is a complete command line, so eval re-splits it into words.
printf '%s' "${start}" \
	| piper --model "${PIPER_MODEL}" --output-raw \
	| eval "${AUDIO_PLAYER}"
