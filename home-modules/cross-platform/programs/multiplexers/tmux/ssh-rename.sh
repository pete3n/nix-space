# shellcheck disable=SC2148
# Rename the tmux window to the ssh destination for the duration of a session.
#
# POSIX compatible sh function, so bash and zsh can both source it.
ssh() {
	_ns_ssh_original=""
	_ns_ssh_dest=""
	_ns_ssh_skip=0
	_ns_ssh_exit=0

	# Find the destination among the arguments. Flags in this set take a
	# value, so the following argument is theirs and not a hostname: 
	# the list is from ssh(1) and needs updating if ssh grows another.
	for _ns_ssh_arg in "$@"; do
		if [ "${_ns_ssh_skip}" = "1" ]; then
			_ns_ssh_skip=0
			continue
		fi
		case "${_ns_ssh_arg}" in
			-[bcDEeFIiJLlmopQRSWw]) _ns_ssh_skip=1 ;;
			-*) ;;
			*) _ns_ssh_dest="${_ns_ssh_arg}" ;;
		esac
	done

	if [ -z "${TMUX:-}" ]; then
		command ssh "$@"
		return $?
	fi

	_ns_ssh_original="$(tmux display-message -p '#W')"

	#shellcheck disable=SC2329
	_ns_ssh_restore() {
		tmux rename-window "${_ns_ssh_original}"
	}

	# Restore on interrupt as well as on exit, because Ctrl-C during a connection
	# would otherwise leave the window named after a host you are no longer
	# connected to.
	trap _ns_ssh_restore INT

	[ -n "${_ns_ssh_dest}" ] && tmux rename-window "${_ns_ssh_dest}"

	command ssh "$@"
	_ns_ssh_exit=$?

	trap - INT

	if [ "${_ns_ssh_exit}" -ne 0 ]; then
		# Failed connection: put the old name back, since nothing happened.
		tmux rename-window "${_ns_ssh_original}"
	else
		# Succeeded and exited normally: hand control back to automatic
		# renaming rather than restoring, so the next command names it.
		tmux set-window-option automatic-rename "on" >/dev/null
	fi

	return "${_ns_ssh_exit}"
}
