# shellcheck disable=SC2148
#
# Cycles off -> playlist -> track -> off, setting BOTH flags each time to stay
# in sync.
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
  mpc repeat on >/dev/null 2>&1 || true
  mpc single off >/dev/null 2>&1 || true
elif [ "${_single}" = "off" ]; then
  mpc repeat on >/dev/null 2>&1 || true
  mpc single on >/dev/null 2>&1 || true
else
  mpc repeat off >/dev/null 2>&1 || true
  mpc single off >/dev/null 2>&1 || true
fi
