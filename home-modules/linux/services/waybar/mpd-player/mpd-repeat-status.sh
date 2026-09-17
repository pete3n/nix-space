# shellcheck disable=SC2148
#
# Repeat is two mpd flags: `repeat` loops the queue, `single` stops after one
# track. The three states are combinations of both.
_status="$(mpc status 2>/dev/null || true)"

_repeat="$(printf '%s\n' "${_status}" \
  | grep -Eo 'repeat: (on|off)' \
  | awk '{print $2}' || true)"
_single="$(printf '%s\n' "${_status}" \
  | grep -Eo 'single: (on|off)' \
  | awk '{print $2}' || true)"

[ -n "${_repeat:-}" ] || _repeat="off"
[ -n "${_single:-}" ] || _single="off"

if [ "${_repeat}" = "off" ]; then
  _state="off"; _icon="${REPEAT_OFF_ICON}"; _tip="Repeat: off"
elif [ "${_single}" = "on" ]; then
  _state="track"; _icon="${REPEAT_TRACK_ICON}"; _tip="Repeat: track"
else
  _state="playlist"; _icon="${REPEAT_PLAYLIST_ICON}"; _tip="Repeat: playlist"
fi

jq -cn --arg text "${_icon}" --arg class "${_state}" --arg tooltip "${_tip}" \
  '{ text: $text, class: $class, tooltip: $tooltip }'
