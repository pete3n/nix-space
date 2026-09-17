# shellcheck disable=SC2148
bat_path=""
bat_state=""
ac_path=""

ppd_is_active() {
	# No --user: power-profiles-daemon is a SYSTEM service, and
	# is-active against the system manager works from a user session.
	systemctl is-active --quiet power-profiles-daemon.service >/dev/null 2>&1
}

log() {
	[ "${LOG_EVENTS}" = "true" ] || return 0
	logger -t powerproud -- "bat_state=${1} cmd=${2}"
}

find_battery_path() {
	if [ -n "${BATTERY_DEVICE}" ]; then
		if [ -r "/sys/class/power_supply/${BATTERY_DEVICE}/capacity" ]; then
			bat_path="/sys/class/power_supply/${BATTERY_DEVICE}"
		else
			log "error" "device ${BATTERY_DEVICE} not found"
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
}

find_ac_path() {
	for _dir in /sys/class/power_supply/*; do
		[ -r "${_dir}/type" ] && [ -r "${_dir}/online" ] || continue
		read -r _type < "${_dir}/type" || continue
		[ "${_type}" = "Mains" ] || continue
		ac_path="${_dir}"
		return 0
	done
	return 1
}

get_bat_state() {
	[ -n "${bat_path}" ] || { printf "unknown\n"; return 0; }

	_state="$(cat "${bat_path}/status" 2>/dev/null || true)"
	case "${_state}" in
		Discharging) printf "discharging\n" ;;
		Charging|Full) printf "charging\n" ;;
		*) printf "unknown\n" ;;
	esac
}

# Prints ac, battery, or unknown.
#
# Prefers the adapter's online flag, which answers "is external power
# present" directly. Battery status is only a proxy for that, and an
# ambiguous one under a charge limit: "Not charging" means a charger
# is present but the cell is not accepting, and some firmware goes
# straight there on plug-in with no Charging phase in between.
get_power_state() {
	if [ -n "${ac_path}" ]; then
		_online=""
		read -r _online < "${ac_path}/online" 2>/dev/null || true
		case "${_online}" in
			1) printf "ac\n" ;;
			0) printf "battery\n" ;;
			*) printf "unknown\n" ;;
		esac
		return 0
	fi

	_status=""
	read -r _status < "${bat_path}/status" 2>/dev/null || true
	case "${_status}" in
		Discharging) printf "battery\n" ;;
		Charging|Full|"Not charging") printf "ac\n" ;;
		*) printf "unknown\n" ;;
	esac
}

bctl() {
	if [ -n "${BACKLIGHT_DEVICE}" ]; then
		brightnessctl -d "${BACKLIGHT_DEVICE}" "$@"
	else
		brightnessctl "$@"
	fi
}

# Prints the current percentage, or returns 1 having printed nothing.
get_brightness_percent() {
	_line="$(bctl -m g 2>/dev/null)" || return 1
	_pct="${_line#*,*,*,}"   # drop device,class,current,  -> "50%,255"
	_pct="${_pct%%%*}"       # drop from the first % on    -> "50"
	case "${_pct}" in
		""|*[!0-9]*) return 1 ;;
	esac
	printf "%s\n" "${_pct}"
}

# dim only ever lowers, raise only ever raises. Someone who manually set the 
# screen brightness is assumed to want that value.
set_brightness() {
	[ "${MANAGE_BRIGHTNESS}" = "true" ] || return 0
	_target="${1}"
	_direction="${2}"

	if ! _cur="$(get_brightness_percent)"; then
		log "${power_state}" "cannot read brightness; no backlight device found, or BACKLIGHT_DEVICE is wrong"
		return 0
	fi

	case "${_direction}" in
		dim)   [ "${_cur}" -gt "${_target}" ] || return 0 ;;
		raise) [ "${_cur}" -lt "${_target}" ] || return 0 ;;
	esac

	if bctl s "${_target}%" >/dev/null 2>&1; then
		log "${power_state}" "brightnessctl s ${_target}% (was ${_cur}%)"
	else
		log "${power_state}" "brightnessctl s ${_target}% (was ${_cur}%) failed; check write access to the backlight"
	fi
}

get_ppd_profile() {
	powerprofilesctl get 2>/dev/null || printf "unknown\n"
}

set_ppd_profile() {
	_desired="${1}"

	if ! ppd_is_active; then
		log "${bat_state}" "power-profiles-daemon inactive; skip profile=${_desired}"
		return 0
	fi

	_current="$(get_ppd_profile)"

	[ "${_current}" = "${_desired}" ] && return 0

	if powerprofilesctl set "${_desired}" >/dev/null 2>&1; then
		log "${bat_state}" "powerprofilesctl set ${_desired} (was ${_current})"
	else
		log "${bat_state}" "powerprofilesctl set ${_desired} (was ${_current}) (failed)"
	fi
}

apply_state() {
	case "${1}" in
		battery)
			set_brightness "${ON_BATTERY_BRIGHTNESS}" dim
			set_ppd_profile "${ON_BATTERY_PROFILE}"
			;;
		ac)
			set_brightness "${ON_AC_BRIGHTNESS}" raise
			set_ppd_profile "${ON_AC_PROFILE}"
			;;
		*)
			log "${1}" "apply_state: unhandled state"
			;;
	esac
}

find_battery_path
if [ -z "${bat_path}" ]; then
	log "unknown" "no battery found; nothing to switch on"
	exit 0
fi

if ! find_ac_path; then
	log "unknown" "no Mains device; inferring power source from battery status"
fi

if ! ppd_is_active; then
	log "unknown" "power-profiles-daemon inactive; managing brightness only"
fi

power_state="$(get_power_state)"
log "${power_state}" "started; bat=${bat_path##*/} ac=${ac_path##*/} manage_brightness=${MANAGE_BRIGHTNESS}"
apply_state "${power_state}"
while sleep "${BAT_POLL_INTERVAL}"; do
	_new_state="$(get_power_state)"
	case "${_new_state}" in
		ac|battery) : ;;
		*) continue ;;
	esac
	[ "${_new_state}" = "${power_state}" ] && continue
	power_state="${_new_state}"
	apply_state "${power_state}"
done
