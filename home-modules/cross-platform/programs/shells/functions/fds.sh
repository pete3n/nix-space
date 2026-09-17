# shellcheck disable=SC2148
# fd, optionally piped through ripgrep and/or fzf.
#
#   fds '\.nix$'              list matches
#   fds -r mkOption '\.nix$'  grep within matches
#   fds -f '\.nix$'           browse matches with a preview
#   fds -f -r mkOption '.'    browse, then grep the selection
#
# POSIX compliant shell function.
fds() {
	_fds_rg_pattern=""
	_fds_use_fzf=0
	_fds_ext=""
	_fds_type="f"
	_fds_pattern=""
	_fds_dir="."

	if [ -z "${1:-}" ]; then
		printf 'Usage: fds [OPTIONS] <pattern> [dir]\n' >&2
		printf '  -r <pattern>   ripgrep through matched files\n' >&2
		printf '  -f             browse with fzf\n' >&2
		printf '  -e <ext>       filter by extension\n' >&2
		printf '  -t <type>      fd type filter (default: f)\n' >&2
		return 1
	fi

	while [ $# -gt 0 ]; do
		case "${1}" in
			-r) _fds_rg_pattern="${2}"; shift 2 ;;
			-f) _fds_use_fzf=1; shift ;;
			-e) _fds_ext="${2}"; shift 2 ;;
			-t) _fds_type="${2}"; shift 2 ;;
			-*)
				printf 'fds: unknown option: %s\n' "${1}" >&2
				return 1
				;;
			*)
				if [ -z "${_fds_pattern}" ]; then
					_fds_pattern="${1}"
				else
					_fds_dir="${1}"
				fi
				shift
				;;
		esac
	done

	if [ -z "${_fds_pattern}" ]; then
		printf 'fds: pattern required\n' >&2
		return 1
	fi

	_fds_run() {
		if [ -n "${_fds_ext}" ]; then
			fd --type "${_fds_type}" --hidden --no-ignore \
				--extension "${_fds_ext}" "$@" \
				"${_fds_pattern}" "${_fds_dir}"
		else
			fd --type "${_fds_type}" --hidden --no-ignore "$@" \
				"${_fds_pattern}" "${_fds_dir}"
		fi
	}

	if [ "${_fds_use_fzf}" -eq 1 ] && [ -n "${_fds_rg_pattern}" ]; then
		_fds_selected="$(_fds_run | fzf --multi)"
		[ -n "${_fds_selected}" ] || {
			printf 'fds: nothing selected\n' >&2
			return 1
		}
		# printf into xargs -0 rather than xargs -d '\n'. The -d flag is a GNU
		# extension and absent on macOS, where this file is also sourced.
		printf '%s\n' "${_fds_selected}" | tr '\n' '\0' | xargs -0 rg "${_fds_rg_pattern}"

	elif [ "${_fds_use_fzf}" -eq 1 ]; then
		_fds_run | fzf --multi \
			--preview 'bat --color=always --line-range=:200 {} 2>/dev/null || head -200 {}' \
			--preview-window 'right:60%'

	elif [ -n "${_fds_rg_pattern}" ]; then
		_fds_run -0 | xargs -0 rg "${_fds_rg_pattern}"

	else
		_fds_run
	fi
}
