# shellcheck disable=SC2148
if [ ! -f "${PIPER_MODEL}" ]; then
	printf 'ai-speak: model not found at %s\n' "${PIPER_MODEL}" >&2
	printf 'ai-speak: run ai-models-fetch\n' >&2
	exit 1
fi

# AUDIO_PLAYER is a complete command line, so eval re-splits it into words.
if [ "$#" -gt 0 ]; then
	printf '%s' "$*"
else
	cat
fi \
	| piper --model "${PIPER_MODEL}" --output-raw \
	| eval "${AUDIO_PLAYER}"
