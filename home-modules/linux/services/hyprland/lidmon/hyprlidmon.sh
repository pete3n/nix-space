# shellcheck disable=SC2148
# Requires hyprlidmon-state.sh before it.
last_seen_file="${STATE_DIR}/last_seen"
open_cmds_file="${STATE_DIR}/open_cmds"
int_display_disabled_file="${STATE_DIR}/int_display_disabled"

# The resolved panel name, never the literal "auto": INTERNAL_DISPLAY is the
# configured value and int_display is what get_internal made of it, so the
# `[ -z "${int_display}" ]` guards below do catch an unresolved name.
int_display=""

# Fields of the event file being handled.
event=""
ext_power=""

# Set per lidClosed event, used by rule conditions.
ext_display=0

log() {
	[ "${LOG_TO_JOURNAL}" = "true" ] || return 0
	printf 'hyprlidmon: %s\n' "$*" >&2
}

# The event directory only exists while the lidmond system service runs. Fail
# after the timeout (0 waits forever) so the unit lands in `failed` under its
# start limit, rather than looking busy while doing nothing.
wait_for_event_dir() {
	_waited=0
	while [ ! -d "${EVENT_DIR}" ]; do
		if [ "${WAIT_TIMEOUT_SECONDS}" -gt 0 ] && [ "${_waited}" -ge "${WAIT_TIMEOUT_SECONDS}" ]; then
			printf 'hyprlidmon: %s never appeared after %ss.\n' "${EVENT_DIR}" "${WAIT_TIMEOUT_SECONDS}" >&2
			printf 'hyprlidmon: the lidmond SYSTEM service provides it. Enable it with:\n' >&2
			printf 'hyprlidmon:   nixSpace.services.lidmond.enable = true;\n' >&2
			printf 'hyprlidmon: if it is enabled, check that its runtime directory matches\n' >&2
			printf 'hyprlidmon: nixSpace.services.hyprlidmon.eventDir (currently %s).\n' "${EVENT_DIR}" >&2
			return 1
		fi

		if [ "${_waited}" -gt 0 ] && [ $((_waited % 30)) -eq 0 ]; then
			log "still waiting for ${EVENT_DIR} (${_waited}s elapsed)"
		fi

		sleep "${WAIT_INTERVAL_SECONDS}"
		_waited=$((_waited + WAIT_INTERVAL_SECONDS))
	done
}

# Wraps the shared check_external_disp, which prints connected|none|unknown,
# into a boolean. "unknown" counts as no external display: acting on a guess
# here would blank the only working panel.
have_external() {
	[ "$(check_external_disp)" = "connected" ]
}

# Apply a monitor change and report whether it was applied.
#
# `hyprctl keyword` is a hyprlang command. Under a Lua config it refuses
# outright with "keyword can't work with non-legacy parsers"; `hyprctl eval`
# takes a Lua expression instead.
apply_monitor() {
	_out="$(hyprctl eval "${1}" 2>&1)" || true

	# Only an explicit "ok" counts.
	case "${_out}" in
		ok*) return 0 ;;
		"")
			log "hyprctl eval returned nothing (compositor unreachable?)"
			return 1
			;;
		*)
			log "hyprctl eval failed: ${_out}"
			return 1
			;;
	esac
}

disable_internal() {
	if [ -z "${int_display}" ]; then
		log "cannot disable internal display: name unknown"
		return 0
	fi
	log "disabling internal display: ${int_display}"

	# The flag is written only on success. It records what the display state
	# actually is, and startup restore reads it to decide whether to re-apply
	# the disable; a flag written after a failed call would make that decision
	# on stale information.
	if apply_monitor "hl.monitor({ output = '${int_display}', disabled = true })"; then
		touch "${int_display_disabled_file}"
	else
		log "internal display remains enabled"
	fi
}

enable_internal() {
	if [ -z "${int_display}" ]; then
		log "cannot enable internal display: name unknown"
		return 0
	fi
	log "enabling internal display: ${int_display}"

	# The flag is cleared unconditionally, unlike the disable case. A stale flag
	# after a failed enable would make startup restore re-disable a panel the
	# user is trying to get back.
	apply_monitor "hl.monitor({ output = '${int_display}', disabled = false })" || true
	rm -f "${int_display_disabled_file}"
}

# Two internal switches are recognised alongside shell commands.
run_cmd_list() {
	for _cmd in "$@"; do
		[ -n "${_cmd}" ] || continue

		case "${_cmd}" in
			--int-display-disable) disable_internal ;;
			--int-display-enable) enable_internal ;;
			--*) log "unknown internal command: ${_cmd}" ;;
			*)
				log "exec: ${_cmd}"
				${RUNTIME_SHELL} -c "${_cmd}" || true
				;;
		esac
	done
}

store_open_cmds() {
	: > "${open_cmds_file}"
	for _cmd in "$@"; do
		printf '%s\n' "${_cmd}" >> "${open_cmds_file}"
	done
}

run_stored_open_cmds() {
	[ -r "${open_cmds_file}" ] || return 0
	mapfile -t _stored_cmds < "${open_cmds_file}"
	: > "${open_cmds_file}"
	run_cmd_list "${_stored_cmds[@]}"
}

# Fills event and ext_power from a lidmond event file. Parsed, not sourced:
# the file is an interface, not a script.
read_event_file() {
	event=""
	ext_power=""
	while IFS='=' read -r _key _value; do
		case "${_key}" in
			event) event="${_value}" ;;
			extPower) ext_power="${_value}" ;;
		esac
	done < "${1}"
	[ -n "${event}" ]
}

# All conditions must hold. An empty list always matches.
check_conds() {
	for _cond in "$@"; do
		case "${_cond}" in
			extPower) [ "${ext_power}" = "1" ] || return 1 ;;
			extDisplay) [ "${ext_display}" = "1" ] || return 1 ;;
			*) log "unknown cond ${_cond}; treating as unmet"; return 1 ;;
		esac
	done
	return 0
}

# Evaluate rules from RULES_FILE in order. First match wins; otherwise
# LID_CLOSED_DEFAULT_CMD runs. Same file format as lidmond's rules:
#   cond <name>    zero or more, ANDed
#   close <cmd>    zero or more, run now
#   open <cmd>     zero or more, stored for the next lidOpened
#   end            closes the rule
handle_lid_closed() {
	ext_display=0
	if have_external; then
		ext_display=1
	fi
	log "extDisplay=${ext_display}"

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

	if [ "${_matched}" -eq 0 ]; then
		log "lidClosed matched cond=[${_conds[*]}]"
		run_cmd_list "${_close_cmds[@]}"
		store_open_cmds "${_open_cmds[@]}"
		return 0
	fi

	# ":" means no default; skip it rather than logging an exec of nothing.
	if [ "${LID_CLOSED_DEFAULT_CMD}" != ":" ]; then
		log "lidClosed no rule matched; using default"
		run_cmd_list "${LID_CLOSED_DEFAULT_CMD}"
	fi
}

handle_lid_opened() {
	# Stored commands first: they encode the decision made at close time, when
	# the docked state was known.
	run_stored_open_cmds
	if [ "${LID_OPENED_DEFAULT_CMD}" != ":" ]; then
		run_cmd_list "${LID_OPENED_DEFAULT_CMD}"
	fi
}

wait_for_event_dir || exit 1

log "starting; eventDir=${EVENT_DIR} poll=${POLL_INTERVAL_SECONDS}"

[ -e "${open_cmds_file}" ] || : > "${open_cmds_file}"

int_display="$(get_internal 2>/dev/null || true)"
if [ -z "${int_display}" ]; then
	log "warning: internal display unknown; external detection unreliable."
fi

# Restore display state after an agent restart (home-manager rebuild, session
# restart).
#
# If the internal panel was disabled in a previous session, only re-apply that
# when an external display is still present. Undocking with the lid closed and
# then restarting would otherwise leave every display off. Running the deferred
# open commands instead re-enables the panel via --int-display-enable and
# clears the flag.
if [ -f "${int_display_disabled_file}" ]; then
	if have_external; then
		log "startup: external display present — restoring disabled internal display"
		disable_internal
	else
		log "startup: no external display — running deferred open commands"
		run_stored_open_cmds
	fi
fi

last_seen="$(cat "${last_seen_file}" 2>/dev/null || true)"

while true; do
	if [ ! -d "${EVENT_DIR}" ]; then
		sleep 1
		continue
	fi

	# Lexicographic order is chronological: event filenames are
	# timestamp-prefixed.
	for _file in "${EVENT_DIR}"/*.env; do
		[ -e "${_file}" ] || break
		_base="${_file##*/}"

		if [ -n "${last_seen}" ] && [[ ! "${_base}" > "${last_seen}" ]]; then
			continue
		fi

		# lidmond publishes a file before setting its group, so one caught in
		# between is readable on the next poll. Stop here rather than skip it,
		# so events are still handled in order.
		[ -r "${_file}" ] || break

		# An invalid file is skipped for good: leaving last_seen behind it
		# would log the same skip on every poll.
		if read_event_file "${_file}"; then
			log "parsed: event=${event} extPower=${ext_power}"
			case "${event}" in
				lidClosed) handle_lid_closed ;;
				lidOpened) handle_lid_opened ;;
			esac
		else
			log "skipped (invalid): ${_file}"
		fi

		last_seen="${_base}"
		printf '%s\n' "${last_seen}" > "${last_seen_file}"
	done

	sleep "${POLL_INTERVAL_SECONDS}"
done
