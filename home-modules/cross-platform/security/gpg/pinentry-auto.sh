# shellcheck disable=SC2148
# Pick a pinentry based on whether there is a graphical session.
#
exec_pinentry() {
	if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
		exec "${PINENTRY_GUI}" "$@"
	fi
	exec "${PINENTRY_TTY}" "$@"
}

exec_pinentry "$@"
