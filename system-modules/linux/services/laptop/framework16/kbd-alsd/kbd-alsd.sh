# shellcheck disable=SC2148
log() {
	printf '%s\n' "$*"
}

qmk_backlight() {
	qmk_hid --vid "${VID}" via --backlight "$@"
}

# Prints the current backlight level, or nothing if the device is unreachable.
qmk_backlight_read() {
	qmk_backlight 2>/dev/null | tr -dc '0-9'
}

# Prints open, closed, or unknown.
check_lid() {
	for _state_file in /proc/acpi/button/lid/*/state; do
		[ -r "${_state_file}" ] || continue
		read -r _ _state < "${_state_file}" || continue
		case "${_state}" in
			open|closed) printf '%s\n' "${_state}"; return 0 ;;
		esac
	done
	printf 'unknown\n'
}

# Prints ac if any power supply is online, battery if a Battery device exists,
# otherwise unknown.
detect_power() {
	for _online_file in /sys/class/power_supply/*/online; do
		[ -r "${_online_file}" ] || continue
		read -r _online < "${_online_file}" || continue
		if [ "${_online}" = "1" ]; then
			printf 'ac\n'
			return 0
		fi
	done

	for _type_file in /sys/class/power_supply/*/type; do
		[ -r "${_type_file}" ] || continue
		read -r _type < "${_type_file}" || continue
		if [ "${_type}" = "Battery" ]; then
			printf 'battery\n'
			return 0
		fi
	done

	printf 'unknown\n'
}

cur="$(qmk_backlight_read || true)"
if [ -z "${cur}" ]; then
	# Device missing or qmk_hid could not talk to it. Say so once, not every poll.
	if [ ! -e "${MISSING_STAMP}" ]; then
		printf 'qmk_hid backlight device not available (vid=%s); will retry silently\n' "${VID}" >&2
		: > "${MISSING_STAMP}"
	fi
	exit 0
fi
rm -f "${MISSING_STAMP}" # Device is back

# Pick a target level. Only the ambient light policy keeps hysteresis state, so
# the bucket carries over unchanged across a closed lid or a spell on AC.
if [ "$(check_lid)" = "closed" ]; then
	# Lid closed: keyboard backlight off to save power.
	target=0
	reason="lid closed"
elif [ "${BATTERY_ONLY}" = "true" ] && [ "$(detect_power)" = "ac" ]; then
	target="${AC_DEFAULT}"
	reason="external power"
else
	als="$(cat "${ALS_PATH}" 2>/dev/null || true)"
	case "${als}" in
		""|*[!0-9]*) exit 0 ;; # Sensor unreadable, or not a plain integer
	esac

	# Buckets are 5 ALS units wide: 0-4 dark, 5-9 low, 10-14 dim, 15-19 bright, 20+ sunlight.
	bucket=$((als / 5))
	if [ "${bucket}" -gt 4 ]; then
		bucket=4
	fi

	last_bucket="$(cat "${STATE_FILE}" 2>/dev/null || true)"
	case "${last_bucket}" in
		0|1|2|3|4) : ;;
		*) last_bucket="" ;;
	esac

	# Hysteresis: a bucket change must clear the new bucket's boundary by HYSTERESIS
	# ALS units in the direction of travel, or the previous bucket is kept.
	if [ -n "${last_bucket}" ] && [ "${HYSTERESIS}" -gt 0 ] && [ "${bucket}" -ne "${last_bucket}" ]; then
		if [ "${bucket}" -gt "${last_bucket}" ]; then
			# Getting brighter: need als >= lower bound of the new bucket + HYSTERESIS
			need=$((5 * bucket + HYSTERESIS))
			if [ "${als}" -lt "${need}" ]; then
				bucket="${last_bucket}"
			fi
		else
			# Getting darker: need als <= upper bound of the new bucket - HYSTERESIS
			need=$((5 * bucket + 4 - HYSTERESIS))
			if [ "${need}" -lt 0 ]; then
				need=0
			fi
			if [ "${als}" -gt "${need}" ]; then
				bucket="${last_bucket}"
			fi
		fi
	fi

	printf '%s\n' "${bucket}" > "${STATE_FILE}"
	target="${BACKLIGHT_LEVELS[${bucket}]}"
	reason="als=${als} bucket=${bucket}"
fi

# Apply only on change, so a steady state costs one HID read per poll and no
# journal noise.
if [ "${cur}" != "${target}" ]; then
	log "${reason}: backlight ${cur} -> ${target}"
	qmk_backlight "${target}" >/dev/null 2>&1 || true
fi
