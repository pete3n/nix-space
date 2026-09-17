# shellcheck disable=SC2148
#
# Scrolling now-playing indicator.
#
# Waybar has no marquee, so the scroll happens here: each invocation advances
# a saved offset and emits the next window of text. That makes the widget's
# `interval` the scroll rate, a slower interval scrolls slower, it does not
# merely update less often.
#
# Byte-oriented (wc -c, cut -c), so a multi-byte character in a title can be
# split mid-sequence and show a replacement glyph for one tick. Counting
# characters portably is not something POSIX tools do, and the artefact lasts
# one frame.
mkdir -p "${STATE_DIR}"
state_file="${STATE_DIR}/ticker.state"

status_out="$(mpc status 2>/dev/null || true)"
st_line="$(printf '%s\n' "${status_out}" | sed -n '2p' 2>/dev/null || true)"

case "${st_line}" in
  "[playing]"*) status="playing" ;;
  "[paused]"*)  status="paused" ;;
  *)            status="stopped" ;;
esac

artist="$(mpc -f '%artist%' current 2>/dev/null || true)"
title="$(mpc -f '%title%' current 2>/dev/null || true)"
file="$(mpc -f '%file%' current 2>/dev/null || true)"

# Filename without directory or extension, for tracks with no tags.
base="${file##*/}"
base="${base%.*}"

if [ -n "${artist:-}" ] && [ -n "${title:-}" ]; then
  full="${artist} ~ ${title}"
elif [ -n "${title:-}" ]; then
  full="${title}"
elif [ -n "${artist:-}" ]; then
  full="${artist}"
elif [ -n "${base:-}" ]; then
  full="${base}"
else
  full="MPD"
fi

prev_full=""
pos=0
if [ -r "${state_file}" ]; then
  pos="$(sed -n '1p' "${state_file}" 2>/dev/null || printf 0)"
  prev_full="$(sed -n '2p' "${state_file}" 2>/dev/null || true)"
fi

# Restart the scroll on a track change, so a new title is read from its start
# rather than from wherever the last one had reached.
[ "${full}" != "${prev_full}" ] && pos=0

full_len="$(printf '%s' "${full}" | wc -c | tr -d ' ')"

if [ "${full_len}" -le "${MAX_CHARS}" ]; then
  text="${full}"
else
  scroll="${full}${GAP}"
  scroll_len="$(printf '%s' "${scroll}" | wc -c | tr -d ' ')"
  pos_mod=$(( pos % scroll_len ))

  # Doubled so a window straddling the end wraps without separate handling
  # for that case.
  doubled="${scroll}${scroll}"
  text="$(printf '%s' "${doubled}" | cut -c $((pos_mod + 1))-$((pos_mod + MAX_CHARS)))"

  pos=$(( pos + STEP ))
fi

{
  printf '%s\n' "${pos}"
  printf '%s\n' "${full}"
} > "${state_file}" 2>/dev/null || true

jq -cn \
  --arg text "${text}" \
  --arg tooltip "${full}" \
  --arg alt "${status}" \
  --arg class "${status}" \
  '{ text: $text, tooltip: $tooltip, alt: $alt, class: $class }'
