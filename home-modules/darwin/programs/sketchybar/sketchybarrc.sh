# shellcheck disable=SC2148
#
# sketchybar configuration. Runs once at bar start; item scripts run on their
# own schedule or on events after that.
sketchybar --bar \
  drawing=on \
  topmost=on \
  height="${HEIGHT}" \
  position="${POSITION}" \
  color="${BAR_COLOR}" \
  padding_left="${PADDING}" \
  padding_right="${PADDING}"

sketchybar --default \
  icon.font="${FONT}:Regular:${FONT_SIZE}" \
  label.font="${FONT}:Regular:${FONT_SIZE}" \
  icon.color="${ITEM_COLOR}" \
  label.color="${ITEM_COLOR}" \
  padding_left=5 \
  padding_right=5

if [ -n "${WORKSPACES:-}" ]; then
  sketchybar --add event aerospace_workspace_change

  for sid in ${WORKSPACES}; do
    sketchybar --add item "space.${sid}" left \
      --subscribe "space.${sid}" aerospace_workspace_change \
      --set "space.${sid}" \
        icon="${sid}" \
        click_script="aerospace workspace ${sid}" \
        script="${HIGHLIGHT_SCRIPT}"
  done
fi

if [ "${CLOCK}" = "1" ]; then
  sketchybar --add item clock center \
    --set clock \
      update_freq=1 \
      script="sketchybar --set clock label=\"\$(date '+%H:%M')\""
fi

if [ "${BATTERY}" = "1" ]; then
  sketchybar --add item battery right \
    --set battery \
      update_freq=60 \
      script="sketchybar --set battery label=\"\$(pmset -g batt | grep -o '[0-9]*%')\""
fi

sketchybar --update
