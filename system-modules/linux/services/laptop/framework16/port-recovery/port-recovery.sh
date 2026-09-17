# shellcheck disable=SC2148
log() {
	printf '%s\n' "$*"
}

warn() {
	printf '%s\n' "$*" >&2
}

# Slot identity that survives USB bus renumbering: "<xHCI PCI device ID>/<port path>",
# e.g. 151f/2.2. The root hub (usbN) still exists after the device is gone, so this
# works on remove events.
slot_key_of() {
	_bus="${1%%-*}"
	_path="${1#*-}"
	_xhci="$(cat "${USB_DEVICES_DIR}/usb${_bus}/../device" 2>/dev/null || true)"
	printf '%s/%s\n' "${_xhci#0x}" "${_path}"
}

# Firmware-provided mapping, if any: walk up the hub chain looking for a
# `connector` link from a hub/root port to a Type-C port.
resolve_by_connector() {
	_name="${1}"
	while [ -n "${_name}" ]; do
		case "${_name}" in
			*.*)
				_hub="${_name%.*}"
				_portdir="${USB_DEVICES_DIR}/${_hub}/${_hub}-port${_name##*.}"
				;;
			*)
				_bus="${_name%%-*}"
				_portdir="${USB_DEVICES_DIR}/usb${_bus}/${_bus}-0:1.0/usb${_bus}-port${_name#*-}"
				_hub=""
				;;
		esac
		if [ -L "${_portdir}/connector" ]; then
			_connector="$(readlink -f "${_portdir}/connector")"
			_connector="${_connector##*/}"
			printf '%s\n' "${_connector#port}"
			return 0
		fi
		_name="${_hub}"
	done
	return 1
}

# Slot table lookup. A slot key matches itself or anything below it (a hub
# plugged into the slot), never a sibling port.
resolve_by_slot_map() {
	for _key in "${!SLOT_TYPEC_PORT[@]}"; do
		case "${1}" in
			"${_key}"|"${_key}".*)
				printf '%s\n' "${SLOT_TYPEC_PORT[${_key}]}"
				return 0
				;;
		esac
	done
	return 1
}

present() {
	[ -e "${USB_DEVICES_DIR}/${dev}" ]
}

partner_attached() {
	[ -e "/sys/class/typec/port${typec_port}/port${typec_port}-partner" ]
}

cycle() {
	framework_tool --pd-disable "${controller}"
	sleep "${1}"
	# Never leave the controller disabled: retry the enable a few times.
	for _ in 1 2 3; do
		framework_tool --pd-enable "${controller}" && return 0
		sleep 0.5
	done
	warn "failed to re-enable PD controller ${controller}"
	return 1
}

wait_for_device() {
	for _ in $(seq 1 $((VERIFY_SECONDS * 2))); do
		present && return 0
		sleep 0.5
	done
	return 1
}

# Discovery helper for building a slot table: prints the slot key for every
# attached external USB device. Plug a device into each slot, run this, and
# copy the keys into `slots`.
print_slot_keys() {
	printf '%-10s %-12s %-10s %s\n' DEVICE SLOTKEY ID PRODUCT
	for _dir in "${USB_DEVICES_DIR}"/*-*; do
		[ -e "${_dir}/idVendor" ] || continue
		_name="${_dir##*/}"
		printf '%-10s %-12s %s:%s  %s\n' "${_name}" "$(slot_key_of "${_name}")" \
			"$(cat "${_dir}/idVendor")" "$(cat "${_dir}/idProduct")" "$(cat "${_dir}/product" 2>/dev/null || true)"
	done
}

case "${1:-}" in
	--slot-keys) print_slot_keys; exit 0 ;;
	""|-*)
		printf 'usage: fw16-pd-port-recovery <usb-device> | --slot-keys\n' >&2
		exit 2
		;;
	*) dev="${1}" ;; # kernel name of the removed usb_device, e.g. 3-2.2
esac

sleep "${GRACE_SECONDS}"
if present; then
	log "${dev} re-enumerated on its own; nothing to do"
	exit 0
fi

slot_key="$(slot_key_of "${dev}")"
typec_port="$(resolve_by_connector "${dev}" || resolve_by_slot_map "${slot_key}" || true)"
if [ -z "${typec_port}" ]; then
	log "${dev} (slot key ${slot_key}): no Type-C port mapping (internal device or unmapped slot); ignoring"
	exit 0
fi

controller="${CONTROLLER_FOR_TYPEC_PORT[${typec_port}]-}"
if [ -z "${controller}" ]; then
	log "${dev}: Type-C port ${typec_port} has no PD controller mapping; ignoring"
	exit 0
fi

if ! partner_attached; then
	log "${dev}: nothing attached to Type-C port ${typec_port} (card removed?); ignoring"
	exit 0
fi

# A PD-capable partner has an active CC controller that loses power with VBUS,
# so the CCG8 sees a detach and the card re-attaches by itself (display cards
# do this). Give it time to finish before cycling the controller under it.
if [ "$(cat "/sys/class/typec/port${typec_port}/port${typec_port}-partner/supports_usb_power_delivery" 2>/dev/null)" = "yes" ]; then
	sleep "${PD_PARTNER_GRACE_SECONDS}"
	if present; then
		log "${dev} re-enumerated on its own after its PD partner re-attached; nothing to do"
		exit 0
	fi
	if ! partner_attached; then
		log "${dev}: PD partner on Type-C port ${typec_port} detached (self-recovery in progress, or card removed); ignoring"
		exit 0
	fi
fi

# Serialize per controller: a hub full of devices produces one remove event
# each, and only the first should act.
mkdir -p "${STATE_DIR}"
exec 9> "${STATE_DIR}/controller-${controller}.lock"
flock 9
if present; then
	log "${dev} is back (another instance cycled controller ${controller}); nothing to do"
	exit 0
fi

now="$(date +%s)"
last_cycle="$(cat "${STATE_DIR}/controller-${controller}.last" 2>/dev/null || printf '0\n')"
if [ $((now - last_cycle)) -lt "${COOLDOWN_SECONDS}" ]; then
	log "${dev}: controller ${controller} cycled $((now - last_cycle))s ago; not cycling again"
	exit 0
fi

if [ "${DRY_RUN}" = "true" ]; then
	log "dry run: would cycle PD controller ${controller} for ${dev} (slot key ${slot_key}, Type-C port ${typec_port})"
	exit 0
fi

log "${dev} still absent on Type-C port ${typec_port}; cycling PD controller ${controller}"
printf '%s\n' "${now}" > "${STATE_DIR}/controller-${controller}.last"
cycle "${CYCLE_GAP_SECONDS}" || exit 1
if wait_for_device; then
	log "${dev} is back after cycling controller ${controller}"
	exit 0
fi

log "${dev} did not return within ${VERIFY_SECONDS}s; cycling controller ${controller} again with a longer gap"
cycle "${RETRY_GAP_SECONDS}" || exit 1
if wait_for_device; then
	log "${dev} is back after the second cycle of controller ${controller}"
	exit 0
fi

if [ "${RESET_ON_FAILURE}" = "true" ]; then
	log "${dev} still absent; resetting PD controller ${controller}"
	framework_tool --pd-reset "${controller}"
	if wait_for_device; then
		log "${dev} is back after resetting controller ${controller}"
		exit 0
	fi
fi

warn "${dev} did not return after cycling controller ${controller}; giving up"
exit 1
