# shellcheck disable=SC2148
# khal has not run yet, or keeps its cache elsewhere: nothing to notify about.
[ -r "${KHAL_DB}" ] || exit 0

mkdir -p "${STATE_DIR}"

now_epoch="$(date +%s)"
lookahead_epoch=$((now_epoch + LOOKAHEAD_HOURS * 3600))

# Drop stale markers so the directory does not grow without bound. The age
# matches the lookahead window, so a marker cannot be removed while its event
# is still pending.
find "${STATE_DIR}" -maxdepth 1 -type f -mmin "+$((LOOKAHEAD_HOURS * 60))" -delete 2>/dev/null || true

# ISO 8601 duration to minutes: -PT10M, -PT1H, -P1D, -PT1H30M. Seconds are
# ignored and anything else parses as 0, which the caller skips.
parse_trigger_minutes() {
	_days=0
	_hours=0
	_mins=0
	if [[ "${1}" =~ ^[-+]?P(([0-9]+)D)?(T(([0-9]+)H)?(([0-9]+)M)?(([0-9]+)S)?)?$ ]]; then
		_days="${BASH_REMATCH[2]:-0}"
		_hours="${BASH_REMATCH[5]:-0}"
		_mins="${BASH_REMATCH[7]:-0}"
	fi
	printf '%s\n' "$((_days * 1440 + _hours * 60 + _mins))"
}

# Takes one VEVENT's lines as arguments.
process_event() {
	_uid=""
	_summary=""
	_dtstart=""
	_triggers=()
	_in_alarm=0

	# TRIGGER lives inside VALARM; UID and SUMMARY may appear there too, and
	# must not override the event's own.
	for _event_line in "$@"; do
		case "${_event_line}" in
			BEGIN:VALARM) _in_alarm=1 ;;
			END:VALARM) _in_alarm=0 ;;
			TRIGGER:*) _triggers+=("${_event_line#TRIGGER:}") ;;
		esac
		[ "${_in_alarm}" -eq 0 ] || continue
		case "${_event_line}" in
			UID:*) _uid="${_event_line#UID:}" ;;
			SUMMARY:*) _summary="${_event_line#SUMMARY:}" ;;
			DTSTART*) _dtstart="${_event_line##*:}" ;;
		esac
	done

	[ -n "${_uid}" ] || return 0
	[ -n "${_summary}" ] || return 0

	# A trailing Z is UTC. Anything else, TZID or floating, is read in TIMEZONE
	# or the system zone; mapping TZIDs onto zoneinfo names is not attempted.
	_start_tz="${TIMEZONE}"
	case "${_dtstart}" in
		*Z)
			_start_tz="UTC"
			_dtstart="${_dtstart%Z}"
			;;
	esac

	# 20260303T211500 -> 2026-03-03 21:15:00. All-day events (date only) are
	# skipped: "starting in N minutes" means nothing for them.
	[[ "${_dtstart}" =~ ^[0-9]{8}T[0-9]{6}$ ]] || return 0
	_start_fmt="${_dtstart:0:4}-${_dtstart:4:2}-${_dtstart:6:2} ${_dtstart:9:2}:${_dtstart:11:2}:${_dtstart:13:2}"

	if [ -n "${_start_tz}" ]; then
		_start_epoch="$(TZ="${_start_tz}" date -d "${_start_fmt}" +%s 2>/dev/null)" || return 0
	else
		_start_epoch="$(date -d "${_start_fmt}" +%s 2>/dev/null)" || return 0
	fi

	# Future events inside the lookahead window only.
	[ "${_start_epoch}" -gt "${now_epoch}" ] || return 0
	[ "${_start_epoch}" -le "${lookahead_epoch}" ] || return 0

	# An event's own VALARM wins over the global offsets: someone who set a
	# reminder on an event meant that reminder, not this list.
	_offsets=()
	if [ "${#_triggers[@]}" -gt 0 ]; then
		for _trigger in "${_triggers[@]}"; do
			_minutes="$(parse_trigger_minutes "${_trigger}")"
			if [ "${_minutes}" -gt 0 ]; then
				_offsets+=("${_minutes}")
			fi
		done
	else
		_offsets=("${REMINDER_OFFSETS[@]}")
	fi

	for _offset in "${_offsets[@]}"; do
		_delta=$((now_epoch - (_start_epoch - _offset * 60)))
		if [ "${_delta}" -lt 0 ]; then
			_delta=$((-_delta))
		fi
		[ "${_delta}" -le 60 ] || continue

		# One marker per event per offset. Without it, a timer interval shorter
		# than the 60s match window notifies repeatedly.
		_marker="${STATE_DIR}/${_uid}-${_offset}"
		if [ -f "${_marker}" ]; then
			continue
		fi

		notify-send -t "${DISPLAY_MS}" \
			--app-name="khal" \
			--urgency=normal \
			"${_summary}" \
			"Starting in ${_offset} minute(s) at ${_start_fmt}" \
			|| true

		printf '%s\n' "${_uid}" > "${_marker}"
	done
}

# The cache stores each VEVENT as text, which the CLI prints as lines. Reading
# through process substitution keeps the loop in this shell, and keeps sqlite's
# exit status from aborting it: a locked or half-written cache yields nothing
# this run rather than a failed unit.
event_lines=()
in_vevent=0
while IFS= read -r _line; do
	_line="${_line%$'\r'}"
	case "${_line}" in
		BEGIN:VEVENT)
			event_lines=()
			in_vevent=1
			;;
		END:VEVENT)
			in_vevent=0
			process_event "${event_lines[@]}"
			event_lines=()
			;;
		*)
			if [ "${in_vevent}" -eq 1 ]; then
				event_lines+=("${_line}")
			fi
			;;
	esac
done < <(sqlite3 -readonly "${KHAL_DB}" "SELECT item FROM events;")
