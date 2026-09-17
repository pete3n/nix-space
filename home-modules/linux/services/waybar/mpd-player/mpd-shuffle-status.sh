# shellcheck disable=SC2148
#
# Random state as a CSS class, so the icon is styled rather than swapped.
_state="$(mpc status 2>/dev/null \
  | grep -Eo 'random: (on|off)' \
  | awk '{print $2}' || true)"

# mpc prints no status line at all when stopped with an empty queue, so an
# absent value means off rather than unknown.
[ -n "${_state:-}" ] || _state="off"

jq -cn --arg text "${SHUFFLE_ICON}" --arg class "${_state}" \
  '{ text: $text, class: $class, tooltip: "Shuffle" }'
