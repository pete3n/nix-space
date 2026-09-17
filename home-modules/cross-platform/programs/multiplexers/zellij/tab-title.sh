# shellcheck disable=SC2148
# Rename the zellij tab to the current directory on every prompt.
#
# This is simpler and less capable than the tmux version, because tmux has an
# automatic-rename-format that resolves to the running command when something
# other than the shell is in the foreground, as long-running process names
# its own window. zellij has no such mechanism: a tab keeps whatever name it
# was last given until something renames it again.
#
# This shows the directory, always. A command running in the tab is not
# reflected in its name.
_ns_zellij_tab_title() {
	[ -n "${ZELLIJ:-}" ] || return 0

	# Basename only. zellij tabs are narrow and a full path pushes the other
	# tabs off the bar where tmux's window used a `~/...` path because it wraps.
	_ns_zt_name="${PWD##*/}"
	[ "${PWD}" = "${HOME}" ] && _ns_zt_name="~"
	[ "${PWD}" = "/" ] && _ns_zt_name="/"

	zellij action rename-tab "${_ns_zt_name}" 2>/dev/null
}
