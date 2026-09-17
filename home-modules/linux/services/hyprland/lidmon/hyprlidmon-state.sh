# shellcheck disable=SC2148
# Shared machine-state detection. Concatenated after the header into both
# hyprlidmon and hypr-suspend-blocker; expects INTERNAL_DISPLAY and STATE_DIR from
# the header, and hyprctl and jq on PATH. Sets int_display_file, which the
# daemon writes and the suspend blocker reads.
int_display_file="${STATE_DIR}/int_display"

mkdir -p "${STATE_DIR}"

# Hyprland moved its runtime directory to $XDG_RUNTIME_DIR/hypr; the old
# /tmp/hypr path finds nothing on current versions. The newest entry is the
# current instance.
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
	_hyprdir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
	_sig=""
	for _entry in "${_hyprdir}"/*; do
		[ -e "${_entry}" ] || continue
		if [ -z "${_sig}" ] || [ "${_entry}" -nt "${_hyprdir}/${_sig}" ]; then
			_sig="${_entry##*/}"
		fi
	done
	if [ -n "${_sig}" ]; then
		export HYPRLAND_INSTANCE_SIGNATURE="${_sig}"
	fi
fi

# Best-effort internal panel detection, first match wins.
detect_internal() {
	_mons="$(hyprctl monitors all -j 2>/dev/null)" || return 1

	# eDP or LVDS prefix covers virtually all internal laptop panels.
	_int="$(printf '%s' "${_mons}" | jq -r '
		[ .[] | .name ] | map(select(test("^(eDP|LVDS)-"))) | .[0] // empty
	' 2>/dev/null)" || true
	if [ -n "${_int}" ]; then
		printf '%s\n' "${_int}"
		return 0
	fi

	# Exactly one DISABLED monitor is probably the internal panel: that is the
	# state this agent leaves it in while docked.
	_int="$(printf '%s' "${_mons}" | jq -r '
		[ .[] | select(.disabled == true) | .name ] as $n
		| if ($n | length) == 1 then $n[0] else empty end
	' 2>/dev/null)" || true
	if [ -n "${_int}" ]; then
		printf '%s\n' "${_int}"
		return 0
	fi

	# Exactly one ENABLED monitor and nothing disabled: a laptop with no
	# external display attached.
	_int="$(printf '%s' "${_mons}" | jq -r '
		[ .[] | select(.disabled == false) | .name ] as $n
		| if ($n | length) == 1 then $n[0] else empty end
	' 2>/dev/null)" || true
	if [ -n "${_int}" ]; then
		printf '%s\n' "${_int}"
		return 0
	fi

	return 1
}

# Prints the internal panel's name, or fails if it cannot be determined.
get_internal() {
	if [ "${INTERNAL_DISPLAY}" != "auto" ]; then
		printf '%s\n' "${INTERNAL_DISPLAY}"
		return 0
	fi

	# Trust the cache unconditionally: a disabled panel does not appear in
	# hyprctl output, so re-detecting while docked would fail and lose the name
	# needed to re-enable it. The daemon writes this file; the suspend blocker
	# reads it, which is the main practical gain from sharing this code.
	_cached="$(cat "${int_display_file}" 2>/dev/null || true)"
	if [ -n "${_cached}" ]; then
		printf '%s\n' "${_cached}"
		return 0
	fi

	_detected="$(detect_internal 2>/dev/null || true)"
	if [ -n "${_detected}" ]; then
		printf '%s\n' "${_detected}" > "${int_display_file}"
		printf '%s\n' "${_detected}"
		return 0
	fi

	return 1
}

# Prints connected|none|unknown, given the resolved panel name in int_display.
# "unknown" is distinct from "none": it means the question could not be
# answered, which a caller may want to treat differently from a confident
# negative.
check_external_disp() {
	if [ -z "${int_display}" ]; then
		printf 'unknown\n'
		return 0
	fi

	_mons="$(hyprctl monitors -j 2>/dev/null)" || {
		printf 'unknown\n'
		return 0
	}

	if printf '%s' "${_mons}" | jq -e --arg i "${int_display}" \
		'[ .[] | select(.disabled == false and .name != $i) ] | length > 0' \
		>/dev/null 2>&1
	then
		printf 'connected\n'
	else
		printf 'none\n'
	fi
}

# Prints extPower|onBattery|unknown.
check_power() {
	for _online_file in /sys/class/power_supply/*/online; do
		[ -r "${_online_file}" ] || continue
		read -r _online < "${_online_file}" || continue
		if [ "${_online}" = "1" ]; then
			printf 'extPower\n'
			return 0
		fi
	done

	# A Battery device with no AC online means running on battery. Without
	# this check a desktop would report onBattery simply for having no online
	# AC entry.
	for _type_file in /sys/class/power_supply/*/type; do
		[ -r "${_type_file}" ] || continue
		read -r _type < "${_type_file}" || continue
		if [ "${_type}" = "Battery" ]; then
			printf 'onBattery\n'
			return 0
		fi
	done

	printf 'unknown\n'
}

# Prints open|closed|unknown.
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
