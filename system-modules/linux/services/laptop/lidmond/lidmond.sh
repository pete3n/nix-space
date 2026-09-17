# shellcheck disable=SC2148
umask 027

bl_dev="${BACKLIGHT_DEVICE}" # Empty until auto-detected on first use

log() {
	[ "${LOG_TO_JOURNAL}" = "true" ] || return 0
	printf 'lidmond: %s\n' "$*"
}

# brightnessctl, scoped to bl_dev when one is known.
brightnessctl_dev() {
	if [ -n "${bl_dev}" ]; then
		brightnessctl -d "${bl_dev}" "$@"
	else
		brightnessctl "$@"
	fi
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

# True if any /sys/class/power_supply/*/online reads 1.
check_ext_power() {
	for _online_file in /sys/class/power_supply/*/online; do
		[ -r "${_online_file}" ] || continue
		read -r _online < "${_online_file}" || continue
		if [ "${_online}" = "1" ]; then
			return 0
		fi
	done
	return 1
}

# All conditions must hold. An empty list always matches.
check_conds() {
	for _cond in "$@"; do
		case "${_cond}" in
			extPower) check_ext_power || return 1 ;;
			*) log "unknown cond ${_cond}; treating as unmet"; return 1 ;;
		esac
	done
	return 0
}

write_event() {
	_event="${1}"

	if check_ext_power; then
		_ext_power=1
	else
		_ext_power=0
	fi

	_ts="$(date +%Y%m%dT%H%M%S%N)"
	_file="${EVENT_DIR}/${_ts}-${_event}.env"
	_tmp="${EVENT_DIR}/.${_ts}-${_event}.env.$$"

	{
		printf 'event=%s\n' "${_event}"
		printf 'extPower=%s\n' "${_ext_power}"
		printf 'ts=%s\n' "${_ts}"
	} > "${_tmp}"

	# Ownership and mode go on the temp file, so the rename publishes it in its
	# final state. Doing them after the rename left a window where the reader
	# saw a root-only file.
	chown root:"${ACCESS_GROUP}" "${_tmp}"
	chmod 0640 "${_tmp}"
	mv -f "${_tmp}" "${_file}"

	log "wrote event: ${_file} (extPower=${_ext_power})"
}

run_cmd_list() {
	for _cmd in "$@"; do
		[ -n "${_cmd}" ] || continue

		HYPR_LMD_CLOSE_BRIGHTNESS=""
		if [ -r "${CLOSE_BRIGHTNESS_FILE}" ]; then
			HYPR_LMD_CLOSE_BRIGHTNESS="$(cat "${CLOSE_BRIGHTNESS_FILE}" 2>/dev/null || true)"
		fi
		export HYPR_LMD_CLOSE_BRIGHTNESS
		log "HYPR_LMD_CLOSE_BRIGHTNESS=${HYPR_LMD_CLOSE_BRIGHTNESS}"

		log "exec: ${_cmd}"
		${RUNTIME_SHELL} -c "${_cmd}" || true
	done
}

store_open_cmds() {
	: > "${OPEN_CMDS_FILE}"
	for _cmd in "$@"; do
		printf '%s\n' "${_cmd}" >> "${OPEN_CMDS_FILE}"
	done
}

# Returns 0 if at least one stored command ran, 1 otherwise, so the
# caller can treat LID_OPENED_DEFAULT_CMD as a fallback.
run_stored_open_cmds() {
	[ -r "${OPEN_CMDS_FILE}" ] || return 1
	mapfile -t _stored_cmds < "${OPEN_CMDS_FILE}"
	: > "${OPEN_CMDS_FILE}"

	_ran=1
	for _stored_cmd in "${_stored_cmds[@]}"; do
		[ -n "${_stored_cmd}" ] || continue
		run_cmd_list "${_stored_cmd}"
		_ran=0
	done
	return "${_ran}"
}

pick_brightnessctl_device() {
	# Prefer likely internal panel backlights, then fall back to the first
	# backlight class device that responds.
	mapfile -t _found < <(brightnessctl -c backlight -l 2>/dev/null | awk -F"'" '/^Device / { print $2 }')
	for _candidate in amdgpu_bl0 intel_backlight "${_found[@]}"; do
		if brightnessctl -d "${_candidate}" g >/dev/null 2>&1; then
			printf '%s\n' "${_candidate}"
			return 0
		fi
	done
	return 1
}

ensure_bl_dev() {
	if [ -z "${bl_dev}" ]; then
		bl_dev="$(pick_brightnessctl_device 2>/dev/null || true)"
	fi
}

record_close_brightness() {
	ensure_bl_dev
	_cur="$(brightnessctl_dev g 2>/dev/null || true)"
	case "${_cur}" in
		""|*[!0-9]*) return 1 ;;
		*) printf '%s\n' "${_cur}" > "${CLOSE_BRIGHTNESS_FILE}"; return 0 ;;
	esac
}

backlight_off() {
	if record_close_brightness; then
		log "recorded close brightness: $(cat "${CLOSE_BRIGHTNESS_FILE}" 2>/dev/null || printf '?\n')"
	else
		log "could not record close brightness; will restore default ${DEFAULT_RESTORE_BRIGHTNESS}"
		: > "${CLOSE_BRIGHTNESS_FILE}" 2>/dev/null || true
	fi

	brightnessctl_dev set 0 2>/dev/null \
	|| brightnessctl_dev set 1 2>/dev/null \
	|| true
}

backlight_on() {
	ensure_bl_dev

	_restore=""
	if [ -r "${CLOSE_BRIGHTNESS_FILE}" ]; then
		_restore="$(cat "${CLOSE_BRIGHTNESS_FILE}" 2>/dev/null || true)"
	fi

	case "${_restore}" in
		""|*[!0-9]*)
			_restore="${DEFAULT_RESTORE_BRIGHTNESS}"
			log "restore brightness missing/invalid; using default ${DEFAULT_RESTORE_BRIGHTNESS}"
			;;
		*) log "restoring brightness to ${_restore}" ;;
	esac

	brightnessctl_dev set "${_restore}" 2>/dev/null \
	|| brightnessctl_dev set "${DEFAULT_RESTORE_BRIGHTNESS}" 2>/dev/null \
	|| true

	: > "${CLOSE_BRIGHTNESS_FILE}" 2>/dev/null || true
}

# Evaluate rules from RULES_FILE in order. First match wins; otherwise
# LID_CLOSED_DEFAULT_CMD runs. The file holds one field per line, with
# the value being everything after the first space:
#   cond <name>    zero or more, ANDed
#   close <cmd>    zero or more, run now
#   open <cmd>     zero or more, stored for the next lidOpened
#   end            closes the rule
handle_lid_closed() {
	_conds=()
	_close_cmds=()
	_open_cmds=()
	_matched=1

	while IFS= read -r _line; do
		_key="${_line%% *}"
		_val="${_line#* }"
		case "${_key}" in
			cond) _conds+=("${_val}") ;;
			close) _close_cmds+=("${_val}") ;;
			open) _open_cmds+=("${_val}") ;;
			end)
				if check_conds "${_conds[@]}"; then
					_matched=0
					break
				fi
				_conds=()
				_close_cmds=()
				_open_cmds=()
				;;
		esac
	done < "${RULES_FILE}"

	if [ "${_matched}" -ne 0 ]; then
		log "lidClosed no rule matched; using default"
		run_cmd_list "${LID_CLOSED_DEFAULT_CMD}"
		return 0
	fi

	log "lidClosed matched cond=[${_conds[*]}]"
	run_cmd_list "${_close_cmds[@]}"
	store_open_cmds "${_open_cmds[@]}"
}

handle_lid_opened() {
	if run_stored_open_cmds; then
		return 0
	fi
	log "lidOpened no stored commands; using default"
	run_cmd_list "${LID_OPENED_DEFAULT_CMD}"
}

# Subcommands exit here, before any daemon startup work. They are what
# closeCmd/openCmd rules invoke.
case "${1:-}" in
	--backlight-off) backlight_off; exit 0 ;;
	--backlight-on) backlight_on; exit 0 ;;
	""|daemon) : ;;
	*)
		printf 'usage: lidmond [daemon|--backlight-off|--backlight-on]\n' >&2
		exit 2
		;;
esac

log "starting; eventDir=${EVENT_DIR} pollInterval=${POLL_INTERVAL_SECONDS}s"

# If the service starts with the lid already closed, no transition will
# ever be observed. Emit a synthetic event so the current state is
# reflected. This handles a closed lid on boot.
lid_last="$(check_lid)"

if [ "${lid_last}" = "closed" ]; then
	log "startup: lid is closed, emitting synthetic lidClosed event"
	write_event lidClosed
fi

while true; do
	lid_now="$(check_lid)"
	if [ "${lid_now}" = "unknown" ]; then
		sleep 0.1
		continue
	fi

	if [ "${lid_now}" != "${lid_last}" ]; then
		log "lid state changed: ${lid_last} -> ${lid_now}"
		case "${lid_now}" in
			closed)
				write_event lidClosed
				handle_lid_closed
				;;
			open)
				write_event lidOpened
				handle_lid_opened
				;;
		esac
		lid_last="${lid_now}"
	fi

	sleep "${POLL_INTERVAL_SECONDS}"
done
