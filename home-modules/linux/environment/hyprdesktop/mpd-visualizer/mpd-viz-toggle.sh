# shellcheck disable=SC2148
art_pid_file="${STATE_DIR}/art.pid"
viz_pid_file="${STATE_DIR}/viz.pid"

mkdir -p "${STATE_DIR}"

kill_from() {
	_pid_file="${1}"
	[ -r "${_pid_file}" ] || return 0
	_pid="$(cat "${_pid_file}" 2>/dev/null || true)"

	if [ -n "${_pid}" ]; then
		# Negative PID targets the process group.
		#
		# Both windows are terminals running a foreground child, and bash
		# Defers signals while waiting on one, and a plain SIGTERM sits pending
		# until that child returns, which for `mpc idle` means the next
		# playback event. Killing the group reaches the child directly.
		kill -- "-${_pid}" 2>/dev/null || kill "${_pid}" 2>/dev/null || true
	fi

	rm -f "${_pid_file}" 2>/dev/null || true
}

# Start a terminal command in its own session, so the whole process group can
# be killed later, and record the session leader's PID.
launch() {
	_pid_file="${1}"
	_command="${2}"
	eval "setsid ${_command} >/dev/null 2>&1 &"
	printf '%s\n' "$!" > "${_pid_file}"
}

if hypr-popup is-open "${VIZ_CLASS}" "${ART_CLASS}"; then
	# Killing processes, not closing windows.
	#
	# hl.dsp.window.close() IGNORES any argument and acts on the ACTIVE
	# window, so closing a specific one means focusing it first, and
	# focusing a pinned window on another workspace drags you to that
	# workspace. exec_raw("closewindow address:...") reports ok and does
	# nothing.
	kill_from "${viz_pid_file}"
	kill_from "${art_pid_file}"
	exit 0
fi

launch "${viz_pid_file}" "${VIZ_TERMINAL_CMD}"
launch "${art_pid_file}" "${ART_TERMINAL_CMD}"
