# shellcheck disable=SC2148
# Look something up: tldr, then cheat.sh, then DuckDuckGo.
#
# Ordered cheapest-first. tldr is local, cheat.sh is one request, the DDG
# instant-answer API is another, and a full search opens a pager.
smart_help() {
	if [ -z "${1:-}" ]; then
		printf 'Usage: ? <command|topic|question>\n' >&2
		return 1
	fi

	tldr "$@" 2>/dev/null && return 0

	_sh_query_plus="$(printf '%s' "$*" | tr ' ' '+')"
	_sh_query_url="$(printf '%s' "$*" | sed 's/ /%20/g')"

	printf 'No tldr page for %s, trying cheat.sh...\n' "$*" >&2
	_sh_cheat="$(curl --silent --max-time 10 "https://cheat.sh/${_sh_query_plus}")" || _sh_cheat=""

	# cheat.sh answers 200 even for a miss, so the body is the only signal.
	# Its 404 is a CSS comment block containing this phrase.
	#
	# ANSI codes are stripped for the CHECK only — the output shown to the
	# user keeps its colour. Note the pattern uses a literal escape rather
	# than \x1b: that escape is a GNU sed extension and does nothing on
	# macOS, where the check would then never match and every miss would be
	# printed as a page of CSS.
	_sh_esc="$(printf '\033')"
	_sh_plain="$(printf '%s\n' "${_sh_cheat}" | sed "s/${_sh_esc}\\[[0-9;]*[a-zA-Z]//g")"

	if printf '%s\n' "${_sh_plain}" | grep -qF 'Unknown cheat sheet'; then
		_sh_cheat=""
	fi

	if [ -n "${_sh_cheat}" ]; then
		printf '%s\n' "${_sh_cheat}"
		return 0
	fi

	printf 'Checking DuckDuckGo instant answers...\n' >&2
	_sh_json="$(
		curl --silent --max-time 10 \
			--user-agent 'smart_help/1.0 (terminal helper)' \
			"https://api.duckduckgo.com/?q=${_sh_query_url}&format=json&no_html=1&skip_disambig=1"
	)" || _sh_json=""

	_sh_answer="$(printf '%s\n' "${_sh_json}" | jq -r '
		if .AbstractText and .AbstractText != "" then
			"[\(.AbstractSource)]\n\(.AbstractText)"
		elif .Answer and .Answer != "" then
			"[Instant Answer]\n\(.Answer)"
		elif (.RelatedTopics | length) > 0 then
			"[Related]\n" + (
				[ .RelatedTopics[] | select(.Text) | "- \(.Text)" ]
				| .[0:5] | join("\n")
			)
		else "" end
	' 2>/dev/null)"

	if [ -n "${_sh_answer}" ]; then
		printf '%s\n' "${_sh_answer}"
		return 0
	fi

	printf 'Searching DuckDuckGo...\n' >&2
	ddgr --noprompt "$@"
}
