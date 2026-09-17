# shellcheck disable=SC2148
log() {
	printf '%s\n' "$*"
}

exclude_args=()
for _pattern in "${KEEP_ENABLED[@]}"; do
	exclude_args+=(! -path "${_pattern}")
done

# find's exit status is deliberately not checked: a device vanishing during
# the walk is no reason to skip the rest.
mapfile -t wakeup_files < <(find "${DEVICES_DIR}" -path '*/power/wakeup' "${exclude_args[@]}")

disabled=0
for _wakeup in "${wakeup_files[@]}"; do
	if { printf 'disabled\n' > "${_wakeup}"; } 2>/dev/null; then
		disabled=$((disabled + 1))
	fi
done

log "wakeup disabled on ${disabled}/${#wakeup_files[@]} devices"
