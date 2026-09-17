# shellcheck disable=SC2148
fetch() {
	_dest="${1}"
	_url="${2}"
	_label="${3}"

	if [ -f "${_dest}" ]; then
		printf 'ai-models-fetch: %s already present\n' "${_label}"
		return 0
	fi

	printf 'ai-models-fetch: downloading %s\n' "${_label}"
	mkdir -p "${_dest%/*}"

	# Download to a temp name and move on success, so an interrupted transfer
	# does not leave a truncated file that looks complete to the next run.
	if curl -fL --progress-bar -o "${_dest}.partial" "${_url}"; then
		mv "${_dest}.partial" "${_dest}"
		printf 'ai-models-fetch: %s done\n' "${_label}"
	else
		rm -f "${_dest}.partial"
		printf 'ai-models-fetch: failed to download %s\n' "${_label}" >&2
		return 1
	fi
}

# Piper voices are named <lang>_<REGION>-<name>-<quality> and live at
# <lang>/<lang>_<REGION>/<name>/<quality>/ in the piper-voices tree. The voice
# ships as a model plus a JSON config; the model alone is not usable.
piper_lang="${PIPER_VOICE%%_*}"
piper_locale="${PIPER_VOICE%%-*}"
_voice_rest="${PIPER_VOICE#*-}"
piper_name="${_voice_rest%%-*}"
piper_quality="${_voice_rest#*-}"
piper_path="${piper_lang}/${piper_locale}/${piper_name}/${piper_quality}/${PIPER_VOICE}"

fetch "${PIPER_DIR}/${PIPER_VOICE}.onnx" \
	"${PIPER_BASE_URL}/${piper_path}.onnx" \
	"piper voice ${PIPER_VOICE}" || exit 1

fetch "${PIPER_DIR}/${PIPER_VOICE}.onnx.json" \
	"${PIPER_BASE_URL}/${piper_path}.onnx.json" \
	"piper voice config" || exit 1

fetch "${WHISPER_DIR}/${WHISPER_MODEL}.bin" \
	"${WHISPER_BASE_URL}/${WHISPER_MODEL}.bin" \
	"whisper model ${WHISPER_MODEL}" || exit 1

printf 'ai-models-fetch: all models present\n'
