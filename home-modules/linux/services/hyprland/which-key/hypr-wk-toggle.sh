# shellcheck disable=SC2148
#
# Toggle wlr-which-key: start it if not running, kill it if it is. Bound to
# the leader key, so pressing the leader twice closes the menu.
#
# Failures are reported through hyprctl notify rather than a log nobody
# reads: the menu not appearing is the symptom, and the notification is the
# only place the user is looking when it happens.
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}"
wk_dir="${state_dir}/hypr-which-key"
mkdir -p "${wk_dir}"

pidfile="${wk_dir}/wlr-which-key.pid"
ts="$(date +%Y%m%d-%H%M%S)"
log="${wk_dir}/wlr-which-key-${ts}.log"
tmp_out="${wk_dir}/wlr-which-key-last.log"

is_alive() { [ -n "${1:-}" ] && kill -0 "${1}" >/dev/null 2>&1; }

if [ -f "${pidfile}" ]; then
  pid="$(cat "${pidfile}" 2>/dev/null || true)"
  if is_alive "${pid}"; then
    kill "${pid}" >/dev/null 2>&1 || true
    rm -f "${pidfile}"
    exit 0
  fi
  rm -f "${pidfile}" # stale
fi

# errexit is off across the launch and wait: wlr-which-key's exit status is
# the thing being inspected, not a failure to propagate.
set +e
if [ "${DEBUG_LOG}" = "true" ]; then
  "${WK}" "$@" >"${log}" 2>&1 &
else
  # Capture the last output for the notification without accumulating logs.
  "${WK}" "$@" >"${tmp_out}" 2>&1 &
fi
pid="$!"
set -e

printf '%s\n' "${pid}" >"${pidfile}"

set +e
wait "${pid}"
rc="$?"
set -e

rm -f "${pidfile}"

# 143 is SIGTERM — the toggle killed it, which is the normal close path.
if [ "${rc}" -ne 0 ] && [ "${rc}" -ne 143 ]; then
  if [ "${DEBUG_LOG}" = "true" ]; then
    _tail_out="$(tail -n 15 "${log}" 2>/dev/null || true)"
    _extra="Full log: ${log}"
  else
    _tail_out="$(tail -n 15 "${tmp_out}" 2>/dev/null || true)"
    _extra="(Set nixSpace.hyprland.hyprWhichKey.debugLog = true for timestamped logs.)"
  fi

  msg="$(printf 'wlr-which-key failed (exit %s).\n\nLast lines:\n%s%s' \
    "${rc}" "${_tail_out}" "${_extra}")"

  hyprctl notify 3 10000 0 "${msg}"
  exit "${rc}"
fi

exit 0
