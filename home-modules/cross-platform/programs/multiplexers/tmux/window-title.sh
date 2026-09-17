# shellcheck disable=SC2148
# Rename the tmux window to the current directory on every prompt.
#
# tmux's own renaming fires when the foreground process changes, so a`cd`
# which doesnt start a process leaves the window named after the previous 
# directory until something else runs. Renaming from the prompt updates immediately.
#
# It then re-enables automatic-rename with a format, so the two cooperate:
# when the shell is in the foreground the format resolves to the path this
# function set, and when anything else is running it resolves to that
# program's name. Without the format, re-enabling would immediately overwrite
# the path with the shell process name.
#
# Shell-specific hooks. The function body is common; only the last line
# differs: bash appends to PROMPT_COMMAND, zsh to precmd_functions.
_ns_tmux_window_title() {
	[ -n "${TMUX:-}" ] || return 0

	_ns_wt_path="${PWD}"
	_ns_wt_stripped="${_ns_wt_path#"${HOME}"}"
	[ "${_ns_wt_stripped}" != "${_ns_wt_path}" ] && _ns_wt_path="~${_ns_wt_stripped}"

	# Single-quoted, so the shell leaves the $(...) alone and tmux evaluates
	# it at rename time. Double quotes here would expand it once, now, and
	# bake in whatever the answer was.
	#
	# It walks from the pane's process down through sudo's children to name
	# what sudo is actually running, e.g. "sudo openvpn" rather than "sudo".
	# shellcheck disable=SC2016
	_ns_wt_sudo='#(p=#{pane_pid}; n=; while c=$(pgrep -P $p 2>/dev/null | head -1) && [ -n "$c" ] && n=$(ps -o comm= -p $c 2>/dev/null | tr -d " \n") && [ -n "$n" ]; do p=$c; [ "$n" != "sudo" ] && break; done; [ -n "$n" ] && [ "$n" != "sudo" ] && printf "sudo %s" "$n" || printf "sudo")'

	# shellcheck disable=SC2016
	_ns_wt_cmd="#{?#{==:#{pane_current_command},sudo},${_ns_wt_sudo},#{pane_current_command}}"

	# ${SHELL##*/} rather than a hardcoded name, so one file serves bash and
	# zsh: the format shows the path when the shell itself is in the
	# foreground, and the command name otherwise.
	_ns_wt_fmt="#{?#{m/r:^${SHELL##*/}$,#{pane_current_command}},${_ns_wt_path},${_ns_wt_cmd}}"

	tmux rename-window "${_ns_wt_path}" \; \
		set-window-option automatic-rename on \; \
		set-window-option automatic-rename-format "${_ns_wt_fmt}"
}
