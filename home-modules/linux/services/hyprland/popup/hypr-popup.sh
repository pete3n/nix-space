# shellcheck disable=SC2148
usage() {
	cat >&2 <<-'EOF'
	usage: hypr-popup <command> CLASS...

	  is-open CLASS...   exit 0 if ANY named class has a window
	  count CLASS...     print the total number of matching windows
	  close CLASS...     close every window matching the named classes

	Geometry is NOT handled here — a window rule matching the class does
	that, before the window is mapped.

	Toggling is left to the caller so a popup made of several windows (a
	visualiser plus its album art) opens and closes as a unit:

	  if hypr-popup is-open mpd-vis mpd-art; then
	    hypr-popup close mpd-vis mpd-art
	  else
	    launch both
	  fi
	EOF
}

# A Lua list literal of the requested classes, so one round trip covers every
# class instead of one per class.
#
# Single-quoted Lua strings: the shell string is already double-quoted, and a
# class name is chosen by whoever launches the window, so no escaping beyond
# that is warranted.
class_list() {
	_items="$(printf "'%s', " "$@")"
	printf '{ %s }\n' "${_items%, }"
}

#   repl — RETURNS a value. `hyprctl eval` executes Lua but prints only "ok",
#          so a count computed under eval is unreachable. Queries use repl.
#   eval — executes for side effect. Used for the close.
#
# Verified rather than assumed: `hyprctl eval "print(...)"` returns ok and
# prints nothing, while `hyprctl repl "#hl.get_windows(...)"` prints the count.

# Exact class match, not a regex: a class is chosen by its launcher, so pattern
# matching would only invite a popup to close something it does not own.
count_windows() {
	if [ "$#" -eq 0 ]; then
		printf '0\n'
		return 0
	fi

	_classes="$(class_list "$@")"
	_out="$(hyprctl repl "
		local n = 0
		for _, c in ipairs(${_classes}) do
			n = n + #hl.get_windows({ class = c })
		end
		return n
	" 2>/dev/null)" || _out=""

	case "${_out}" in
		""|*[!0-9]*) printf '0\n' ;;
		*) printf '%s\n' "${_out}" ;;
	esac
}

# HL.Window is a plain field record: address, class, title, workspace, and has
# no methods, so there is no w:close(). Closing needs a dispatcher, and
# `hyprctl dispatch closewindow address:...` is legacy-parser only: under a Lua
# config `dispatch` is shorthand for hl.dispatch(...), making a bare dispatcher
# name a Lua syntax error.
#
# exec_raw takes a legacy hyprlang string, which is the supported escape hatch.
# The scripts this replaced used the bare form, so their close path had been
# silently broken since the Lua migration.
close_windows() {
	[ "$#" -gt 0 ] || return 0

	_classes="$(class_list "$@")"

	# One eval closes every match. The previous shell loop issued a round trip
	# per address AND used the legacy dispatcher form.
	_out="$(hyprctl eval "
		for _, c in ipairs(${_classes}) do
			for _, w in ipairs(hl.get_windows({ class = c })) do
				hl.dispatch(hl.dsp.exec_raw('closewindow address:' .. w.address))
			end
		end
	" 2>&1)" || true

	case "${_out}" in
		ok*) ;;
		*)
			printf 'hypr-popup: close failed: %s\n' "${_out}" >&2
			return 1
			;;
	esac
}

cmd="${1:-}"
[ "$#" -eq 0 ] || shift

case "${cmd}" in
	is-open) [ "$(count_windows "$@")" -gt 0 ] || exit 1 ;;
	count) count_windows "$@" ;;
	close) close_windows "$@" ;;
	""|-h|--help)
		usage
		exit 0
		;;
	*)
		printf 'hypr-popup: unknown command: %s\n' "${cmd}" >&2
		usage
		exit 2
		;;
esac
