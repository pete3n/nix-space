# shellcheck disable=SC2148
# Rename the zellij tab to the ssh destination for the duration of a session.
#
# Separate from the tmux function, because zellij cannot report its current tab
# name. It cannot save-and-restore, so it renames on entry and sets a fallback 
# on exit.
#
# The fallback is the working directory rather than the previous name, since
# that is what the prompt hook would set anyway on the next prompt.
ssh() {
	_ns_ssh_dest=""
	_ns_ssh_skip=0
	_ns_ssh_exit=0

	if [ -z "${ZELLIJ:-}" ]; then
		command ssh "$@"
		return $?
	fi

	# Flags in this set take a value, so the following argument is theirs and
	# not a hostname. From ssh(1); needs updating if ssh grows another.
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

	_ns_ssh_restore() {
		# The best available approximation of "what it was". The prompt hook
		# sets the same thing on the next prompt anyway.
		zellij action rename-tab "${PWD##*/}" 2>/dev/null
	}

	trap _ns_ssh_restore INT

	[ -n "${_ns_ssh_dest}" ] && zellij action rename-tab "${_ns_ssh_dest}" 2>/dev/null

	command ssh "$@"
	_ns_ssh_exit=$?

	trap - INT
	_ns_ssh_restore

	return "${_ns_ssh_exit}"
}
