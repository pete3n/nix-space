# shellcheck disable=SC2148
usage() {
	cat >&2 <<-'EOF'
	usage: ollama-import [-n NAME] [-s SYSTEM] [-p KEY=VALUE]... [-f] [-r] <model.gguf>

	Imports a GGUF file into the ollama server, whose own downloads are blocked
	by the egress restriction. Fetch the file another way (a browser, or curl on
	a machine with access) and hand it here. The import goes through the primary
	instance; every instance shares the model store, so all of them see it.

	  -n NAME       model name; defaults to the file name without .gguf, lowercased
	  -s SYSTEM     system prompt baked into the model
	  -p KEY=VALUE  a PARAMETER line, e.g. -p num_ctx=8192 (repeatable)
	  -f            replace an existing model of the same name
	  -r            remove the GGUF after a successful import; ollama keeps its own copy
	  -h            this help

	OLLAMA_HOST defaults to the primary instance and may be overridden.
	EOF
}

name=""
system=""
params=()
force=0
remove_source=0

while getopts 'n:s:p:frh' _opt; do
	case "${_opt}" in
		n) name="${OPTARG}" ;;
		s) system="${OPTARG}" ;;
		p) params+=("${OPTARG}") ;;
		f) force=1 ;;
		r) remove_source=1 ;;
		h)
			usage
			exit 0
			;;
		*)
			usage
			exit 2
			;;
	esac
done
shift $((OPTIND - 1))

if [ "$#" -ne 1 ]; then
	usage
	exit 2
fi
gguf="${1}"

for _param in "${params[@]}"; do
	case "${_param}" in
		?*=?*) : ;;
		*)
			printf 'ollama-import: -p expects KEY=VALUE, got: %s\n' "${_param}" >&2
			exit 2
			;;
	esac
done

if [ ! -f "${gguf}" ]; then
	printf 'ollama-import: file not found: %s\n' "${gguf}" >&2
	exit 1
fi

# GGUF files start with the magic bytes "GGUF". A blocked or failed download
# saved under the right name is usually an HTML page, which this catches before
# ollama produces a less helpful error.
if [ "$(head -c 4 "${gguf}")" != "GGUF" ]; then
	printf 'ollama-import: not a GGUF file (bad magic): %s\n' "${gguf}" >&2
	exit 1
fi
gguf="$(realpath "${gguf}")"

# Ollama model names are lowercase [a-z0-9._-]; derive one from the file name.
if [ -z "${name}" ]; then
	name="${gguf##*/}"
	name="${name%.gguf}"
	name="${name,,}"
	name="${name//[^a-z0-9._-]/-}"
fi

if ! ollama list >/dev/null 2>&1; then
	printf 'ollama-import: cannot reach the ollama server (is it running? OLLAMA_HOST=%s)\n' "${OLLAMA_HOST:-default}" >&2
	exit 1
fi

if [ "${force}" -eq 0 ] && ollama show "${name}" >/dev/null 2>&1; then
	printf 'ollama-import: model %s already exists; use -f to replace it\n' "${name}" >&2
	exit 1
fi

# The Modelfile is generated rather than written by hand: FROM with a local path
# makes the client hash and upload the blob itself, so the server never needs
# to read this file or the GGUF.
modelfile="$(mktemp)"
trap 'rm -f "${modelfile}"' EXIT INT TERM

{
	printf 'FROM %s\n' "${gguf}"
	for _param in "${params[@]}"; do
		printf 'PARAMETER %s %s\n' "${_param%%=*}" "${_param#*=}"
	done
	if [ -n "${system}" ]; then
		printf 'SYSTEM """%s"""\n' "${system}"
	fi
} > "${modelfile}"

printf 'ollama-import: creating %s from %s\n' "${name}" "${gguf}"
ollama create "${name}" -f "${modelfile}"

if [ "${remove_source}" -eq 1 ]; then
	rm -f "${gguf}"
	printf 'ollama-import: removed %s\n' "${gguf}"
fi

printf 'ollama-import: done; try: ollama run %s\n' "${name}"
