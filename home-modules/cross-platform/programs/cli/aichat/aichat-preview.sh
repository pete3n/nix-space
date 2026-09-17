# shellcheck disable=SC2148
# Renders an aichat session YAML as Markdown: unescape the literal \n and \t
# sequences YAML stored, then hand it to glow.
#
#   aichat-preview <file> [line]    a window around LINE (default 1), no pager
#   aichat-preview --full <file>    the whole file, through glow's pager
render() {
	sed 's/\\n/\n/g; s/\\t/\t/g' | glow --style=dark "$@" -
}

if [ "${1:-}" = "--full" ]; then
	file="${2:-}"
	if [ -z "${file}" ]; then
		printf 'Usage: aichat-preview --full <file>\n' >&2
		exit 1
	fi
	bat --style=plain --color=never --paging=never "${file}" | render --pager
	exit 0
fi

file="${1:-}"
line="${2:-1}"

if [ -z "${file}" ]; then
	printf 'Usage: aichat-preview <file> [line] | --full <file>\n' >&2
	exit 1
fi

start=$((line > 10 ? line - 10 : 1))
end=$((line + 20))

bat --style=plain --color=never --line-range "${start}:${end}" "${file}" | render
