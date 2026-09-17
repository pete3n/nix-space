# shellcheck disable=SC2148
# Pick a pinentry based on whether there is a graphical session.
#
# GRAPHICAL_ALWAYS is set at build time from the target platform. macOS has a
# graphical session whenever a user is logged in and sets neither
# WAYLAND_DISPLAY nor DISPLAY, so without this the checks below always fall
# through to the terminal pinentry which cannot prompt from a
# launchd-started agent with no controlling terminal.
exec_pinentry() {
	if [ "${GRAPHICAL_ALWAYS}" = "1" ]; then
		exec "${PINENTRY_GUI}" "$@"
	fi

	if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
		exec "${PINENTRY_GUI}" "$@"
	fi

	exec "${PINENTRY_TTY}" "$@"
}

exec_pinentry "$@"
