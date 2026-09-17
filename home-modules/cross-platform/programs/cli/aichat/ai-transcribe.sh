# shellcheck disable=SC2148
file=""
output=""
language="${TRANSCRIBE_LANGUAGE}"
translate=0
passthrough_args=()

while [ "$#" -gt 0 ]; do
	case "${1}" in
		-o)
			shift
			output="${1:-}"
			;;
		-o*) output="${1#-o}" ;;
		-l)
			shift
			language="${1:-en}"
			;;
		-l*) language="${1#-l}" ;;
		-t) translate=1 ;;
		-*) passthrough_args+=("${1}") ;;
		*)
			if [ -n "${file}" ]; then
				printf 'ai-transcribe: unexpected argument: %s\n' "${1}" >&2
				exit 1
			fi
			file="${1}"
			;;
	esac
	[ "$#" -eq 0 ] || shift
done

if [ -z "${file}" ]; then
	printf 'Usage: ai-transcribe [-o out] [-l lang] [-t] <audio-file>\n' >&2
	exit 1
fi

if [ ! -f "${file}" ]; then
	printf 'ai-transcribe: file not found: %s\n' "${file}" >&2
	exit 1
fi

if [ ! -f "${WHISPER_MODEL}" ]; then
	printf 'ai-transcribe: model not found at %s — run ai-models-fetch\n' "${WHISPER_MODEL}" >&2
	exit 1
fi

cmd=(whisper-cli -m "${WHISPER_MODEL}" -f "${file}" -l "${language}")

if [ "${translate}" -eq 1 ]; then
	cmd+=(--translate)
fi
if [ -n "${output}" ]; then
	cmd+=(-of "${output}" -otxt)
fi

exec "${cmd[@]}" "${passthrough_args[@]}"
