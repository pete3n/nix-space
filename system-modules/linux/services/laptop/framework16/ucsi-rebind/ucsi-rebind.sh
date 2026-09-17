# shellcheck disable=SC2148
log() {
	printf '%s: %s\n' "${DEVICE}" "$*"
}

# True if the Type-C class has enumerated at least one port for the device.
have_ports() {
	for _port in "${DEVICE_PATH}"/typec/*; do
		if [ -e "${_port}" ]; then
			return 0
		fi
	done
	return 1
}

rebind() {
	if [ -e "${DRIVER_PATH}/${DEVICE}" ]; then
		printf '%s\n' "${DEVICE}" > "${DRIVER_PATH}/unbind"
	fi
	printf '%s\n' "${DEVICE}" > "${DRIVER_PATH}/bind"
}

if [ ! -e "${DEVICE_PATH}" ]; then
	log "no such platform device; nothing to do"
	exit 0
fi

# Let the boot-time init attempt finish, succeeded or timed out, before
# judging it.
sleep "${INITIAL_DELAY_SECONDS}"

if have_ports; then
	log "Type-C ports present; nothing to do"
	exit 0
fi

for _attempt in $(seq 1 "${ATTEMPTS}"); do
	log "no Type-C ports (PPM init timed out at boot?); rebind attempt ${_attempt}"
	rebind
	# The probe returns immediately; PPM reset and connector enumeration
	# happen asynchronously.
	sleep "${SETTLE_SECONDS}"
	if have_ports; then
		log "Type-C ports present after rebind"
		exit 0
	fi
done

log "still no Type-C ports after ${ATTEMPTS} rebinds" >&2
exit 1
