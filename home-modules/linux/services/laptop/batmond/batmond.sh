# shellcheck disable=SC2148
mkdir -p "${STATE_DIR}"

bat_path=""
bat_status=""
bat_cap="100" # Assume full until measured
bat_last_cap="101" # 101 means unmeasured

log() {
	[ "${LOG_EVENTS}" = "true" ] || return 0
	logger -t batmond -- "event=${1} cap=${2}% threshold=${3}% cmd=${4}"
}

notify_tty() {
	_title="${1}"
	_body="${2}"
	printf '%s - %s\n' "${_title}" "${_body}" \
	| ${RUNTIME_SHELL} -c "${TTY_NOTIFY_CMD}" >/dev/null 2>&1 || true
}

notify_gui() {
	${RUNTIME_SHELL} -c "${GUI_NOTIFY_CMD} \"\$@\"" batmond "${1}" "${2}" >/dev/null 2>&1 || true
}

notify() {
	_title="${1}"
	_gui_msg="${2}"
	_tty_msg="${3}"
	notify_gui "${_title}" "${_gui_msg}"
	notify_tty "${_title}" "${_tty_msg}"
}

update_bat_last_cap() {
	printf "%s\n" "${bat_cap}" > "${STATE_FILE}"
}

if [ -n "${BATTERY_DEVICE}" ]; then
	if [ -r "/sys/class/power_supply/${BATTERY_DEVICE}/capacity" ]; then
		bat_path="/sys/class/power_supply/${BATTERY_DEVICE}"
	else
		log "error" "0" "0" "device ${BATTERY_DEVICE} not found"
		exit 0
	fi
else
	for _dir in /sys/class/power_supply/*; do
		[ -r "${_dir}/type" ] && [ -r "${_dir}/capacity" ] || continue
		read -r _type < "${_dir}/type" || continue
		[ "${_type}" = "Battery" ] || continue
		[ "$(cat "${_dir}/scope" 2>/dev/null)" != "Device" ] || continue
		bat_path="${_dir}"
		break
	done
fi

# No battery is not an error — a desktop running this does nothing
# rather than complaining once every interval.
[ -n "${bat_path}" ] || exit 0

bat_status="$(cat "${bat_path}/status" 2>/dev/null || printf "Unknown")"
bat_cap="$(cat "${bat_path}/capacity" 2>/dev/null || printf "100")"
case "${bat_cap}" in
	""|*[!0-9]*) bat_cap=100 ;;
esac

# Load last seen percentage (101 = "not seen discharging")
if [ -f "${STATE_FILE}" ]; then
	read -r bat_last_cap < "${STATE_FILE}" || bat_last_cap="101"
fi

case "${bat_last_cap}" in
	""|*[!0-9]*) bat_last_cap=101 ;;
esac

# A capacity HIGHER than last seen means the battery gained charge
# without this daemon observing it, such as charging while powered off, or
# state left from a previous boot. The stored value is then
# meaningless AND actively harmful: after a shutdown at 1%, every
# threshold check compares against 1, so
# `bat_last_cap > SUSPEND_PERCENT` is false forever and the machine
# runs flat with no warning and no action.
#
# The Charging/Full reset below cannot catch this, because charging
# while the daemon is not running is invisible to it.
if [ "${bat_cap}" -gt "${bat_last_cap}" ]; then
	bat_last_cap=101
	printf "101\n" > "${STATE_FILE}"
fi

# If not discharging, reset state and exit
case "${bat_status}" in
	Discharging) : ;;
	Charging|Full) printf "101\n" > "${STATE_FILE}"; exit 0 ;;
	*) exit 0 ;; # Unknown / Not charging
esac

# Check in reverse order from shutdown to hibernate to suspend to warn
if [ "${SHUTDOWN_PERCENT}" -gt 0 ] && [ "${bat_cap}" -le "${SHUTDOWN_PERCENT}" ] \
&& [ "${bat_last_cap}" -gt "${SHUTDOWN_PERCENT}" ]; then
	update_bat_last_cap
	notify "Battery ${bat_cap}%" "${SHUTDOWN_GUI_MSG}" "${SHUTDOWN_TTY_MSG}"
	log "shutdown" "${bat_cap}" "${SHUTDOWN_PERCENT}" "systemctl ${SHUTDOWN_SUB_CMD}"

	systemctl "${SHUTDOWN_SUB_CMD}"
	exit 0
fi

if [ "${HIBERNATE_PERCENT}" -gt 0 ] && [ "${bat_cap}" -le "${HIBERNATE_PERCENT}" ] \
&& [ "${bat_last_cap}" -gt "${HIBERNATE_PERCENT}" ]; then
	update_bat_last_cap
	notify "Battery ${bat_cap}%" "${HIBERNATE_GUI_MSG}" "${HIBERNATE_TTY_MSG}"
	log "hibernate" "${bat_cap}" "${HIBERNATE_PERCENT}" "systemctl ${HIBERNATE_SUB_CMD}"
	systemctl "${HIBERNATE_SUB_CMD}"
	exit 0
fi

if [ "${SUSPEND_PERCENT}" -gt 0 ] && [ "${bat_cap}" -le "${SUSPEND_PERCENT}" ] \
&& [ "${bat_last_cap}" -gt "${SUSPEND_PERCENT}" ]; then
	update_bat_last_cap
	notify "Battery ${bat_cap}%" "${SUSPEND_GUI_MSG}" "${SUSPEND_TTY_MSG}"
	log "suspend" "$bat_cap" "${SUSPEND_PERCENT}" "systemctl ${SUSPEND_SUB_CMD}"
	systemctl "${SUSPEND_SUB_CMD}"
	exit 0
fi

if [ "${WARN_BELOW_PERCENT}" -gt 0 ] && [ "${bat_cap}" -lt "${WARN_BELOW_PERCENT}" ] \
&& [ "${bat_cap}" -lt "${bat_last_cap}" ]; then
	update_bat_last_cap
	notify "Battery ${bat_cap}%" "${WARN_BELOW_GUI_MSG}" "${WARN_BELOW_TTY_MSG}"
	log "warn" "${bat_cap}" "${WARN_BELOW_PERCENT}" "none"
	exit 0
fi
