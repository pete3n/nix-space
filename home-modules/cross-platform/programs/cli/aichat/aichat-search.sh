# shellcheck disable=SC2148
use_tmux=0
query=""

for _arg in "$@"; do
	case "${_arg}" in
		-t) use_tmux=1 ;;
		*) query="${query}${query:+ }${_arg}" ;;
	esac
done

if [ ! -d "${AICHAT_SESSIONS_DIR}" ]; then
	printf 'Sessions directory not found: %s\n' "${AICHAT_SESSIONS_DIR}" >&2
	exit 1
fi

# rg is given no path, so it must run from the sessions directory rather than
# wherever the user happened to be.
cd "${AICHAT_SESSIONS_DIR}" || exit 1

# Nothing found, or the selection cancelled: not an error.
result="$(
	rg \
		--glob '*.yaml' \
		--line-number \
		--no-heading \
		--color=never \
		--smart-case \
		"${query}" \
	| fzf \
		--delimiter ':' \
		--nth '3..' \
		--with-nth '1,3..' \
		--query "${query}" \
		--preview "${AICHAT_PREVIEW} {1} {2}" \
		--preview-window 'right:60%:wrap' \
		--bind 'ctrl-/:toggle-preview' \
		--prompt 'aichat> ' \
		--header 'ENTER: open  CTRL-/: toggle preview'
)" || exit 0
[ -n "${result}" ] || exit 0

# file:line:match
file="${result%%:*}"
rest="${result#*:}"
line="${rest%%:*}"

if [ -z "${file}" ] || [ -z "${line}" ]; then
	printf 'Could not parse selection: %s\n' "${result}" >&2
	exit 1
fi

# The pane's shell has the user's PATH, not this script's, which is why the
# viewer is referenced by absolute path. tmux itself is deliberately the
# user's: a client from a different package than the running server refuses
# to talk to it.
if [ "${use_tmux}" = "1" ] && [ -n "${TMUX:-}" ]; then
	tmux split-window -h "$(printf '%q --full %q' "${AICHAT_PREVIEW}" "${file}")"
else
	exec "${AICHAT_PREVIEW}" --full "${file}"
fi
