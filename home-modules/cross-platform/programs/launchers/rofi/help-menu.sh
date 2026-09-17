# shellcheck disable=SC2148
# Extensible keybinding cheatsheet in rofi.
#
# Currently only loads the rofi-help-menu.
set -eu

CMD_COLOR="#dddddd"

rows="$(rofi-help-tmux)"

[ -n "${rows}" ] || exit 0

choice="$(printf '%s\n' "${rows}" | rofi -dmenu -i -markup-rows -p 'tmux:')" || exit 0
[ -n "${choice}" ] || exit 0

# The command is carried in a coloured span at the end of each row, so the
# visible text can be formatted independently of what runs.
cmd="$(
	printf '%s\n' "${choice}" \
		| sed -n "s|.*<span color='${CMD_COLOR}'> *\(.*\)</span>.*|\1|p"
)"

[ -n "${cmd}" ] || exit 0

# The commands here come from tmux's own binding list and are self-contained.
sh -c "${cmd}"
