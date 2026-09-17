# shellcheck disable=SC2148
#
# Item script for each workspace indicator. sketchybar runs it with NAME set
# to the item ("space.3") and, on the aerospace_workspace_change event,
# AEROSPACE_FOCUSED_WORKSPACE set by the trigger.
#
# The workspace this item represents is derived from NAME rather than passed
# per item, so one script serves every indicator.
workspace="${NAME#space.}"

if [ "${AEROSPACE_FOCUSED_WORKSPACE:-}" = "${workspace}" ]; then
  sketchybar --set "${NAME}" icon.color="${ACTIVE_COLOR}"
else
  sketchybar --set "${NAME}" icon.color="${ITEM_COLOR}"
fi
