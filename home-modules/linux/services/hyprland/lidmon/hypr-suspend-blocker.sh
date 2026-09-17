# shellcheck disable=SC2148
# Requires hyprlidmon-state.sh before it.
state_power=""
state_lid=""
state_ext_display=""
int_display=""
do_print=0
dry_run=0

# Returns 0 when the named condition holds.
cond_met() {
	case "${1}" in
		lidOpen) [ "${state_lid}" = "open" ] ;;
		lidClosed) [ "${state_lid}" = "closed" ] ;;
		extPower) [ "${state_power}" = "extPower" ] ;;
		onBattery) [ "${state_power}" = "onBattery" ] ;;
		extDisplay) [ "${state_ext_display}" = "connected" ] ;;
		*)
			printf 'unknown condition: %s\n' "${1}" >&2
			return 1
			;;
	esac
}

# Returns 0 when every condition in one space-separated list holds. An empty
# list never matches.
list_met() {
	read -ra _conds <<< "${1}"
	[ "${#_conds[@]}" -gt 0 ] || return 1
	for _cond in "${_conds[@]}"; do
		cond_met "${_cond}" || return 1
	done
	return 0
}

# Returns 0 when any list holds.
any_list_met() {
	for _list in "${SUSPEND_BLOCKERS[@]}"; do
		if list_met "${_list}"; then
			return 0
		fi
	done
	return 1
}

print_state() {
	printf 'power=%s\n' "${state_power}"
	printf 'lid=%s\n' "${state_lid}"
	printf 'extDisplay=%s\n' "${state_ext_display}"
	printf 'internalDisplay=%s\n' "${int_display:-unknown}"
	if [ "${#SUSPEND_BLOCKERS[@]}" -eq 0 ]; then
		printf 'blockers=none\n'
	else
		printf 'blockers='
		printf '[%s] ' "${SUSPEND_BLOCKERS[@]}"
		printf '\n'
	fi
}

while [ "$#" -gt 0 ]; do
	case "${1}" in
		--print) do_print=1 ;;
		--dry-run) dry_run=1 ;;
		"") : ;;
		*)
			printf 'invalid argument: %s\n' "${1}" >&2
			exit 2
			;;
	esac
	shift
done

state_power="$(check_power)"
state_lid="$(check_lid)"
int_display="$(get_internal 2>/dev/null || true)"
state_ext_display="$(check_external_disp)"

if [ "${do_print}" -eq 1 ]; then
	print_state
	exit 0
fi

if any_list_met; then
	printf 'blocker matched, not suspending\n'
	print_state
	exit 0
fi

printf 'no blocker matched, suspending\n'
print_state

if [ "${dry_run}" -eq 1 ]; then
	exit 0
fi

exec systemctl suspend
