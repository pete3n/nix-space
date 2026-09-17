# shellcheck disable=SC2148
mkdir -p "${AICHAT_SESSIONS_DIR}"

# The API key is read here rather than exported by a shell function, so it
# works from scripts and keybinds, not only interactive bash.
if [ -n "${API_KEY_FILE}" ]; then
	if [ -r "${API_KEY_FILE}" ]; then
		_key="$(cat "${API_KEY_FILE}")"
		export "${API_KEY_VAR?}=${_key}"
	else
		printf 'aichat-ctx: cannot read API key at %s\n' "${API_KEY_FILE}" >&2
		printf 'aichat-ctx: is the secret decrypted and owned by this user?\n' >&2
	fi
fi

session_prefix="${1:-nix_env}"
[ "$#" -eq 0 ] || shift

session_name="${session_prefix}-$(date +%Y-%m-%d)"
session_file="${AICHAT_SESSIONS_DIR}/${session_name}.yaml"

# --session-ctx <file> becomes an aichat --file only when the session is new.
# Every other argument passes through untouched.
ctx_files=()
pass_args=()
_next_is_ctx=0

for _arg in "$@"; do
	if [ "${_next_is_ctx}" -eq 1 ]; then
		ctx_files+=("${_arg}")
		_next_is_ctx=0
		continue
	fi
	case "${_arg}" in
		--session-ctx) _next_is_ctx=1 ;;
		--session-ctx=*) ctx_files+=("${_arg#--session-ctx=}") ;;
		*) pass_args+=("${_arg}") ;;
	esac
done

cmd=(aichat --session "${session_name}")

if [ ! -f "${session_file}" ]; then
	if [ "$(uname -s)" = "Darwin" ]; then
		_os_info="$(sw_vers 2>/dev/null | tr '\n' ' ' || true)"
	elif [ -r /etc/os-release ]; then
		# shellcheck source=/dev/null
		_os_info="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-unknown}")"
	else
		_os_info="unknown"
	fi

	# command -v, not a package: this is an availability check for something
	# that may not be running. Likewise `nix` is whichever one the system has.
	if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
		_hyprland_info="$(hyprctl version)"
	else
		_hyprland_info="not running"
	fi

	_context="$(printf 'Kernel: %s\nOS: %s\nShell: %s\nTerminal: %s\nCompositor: %s / %s\nTmux: %s\nHyprland: %s\nNix: %s\n' \
		"$(uname -a)" \
		"${_os_info}" \
		"${SHELL:-unknown}" \
		"${TERM_PROGRAM:-unknown}" \
		"${WAYLAND_DISPLAY:-none}" \
		"${DISPLAY:-none}" \
		"${TMUX:+yes}" \
		"${_hyprland_info}" \
		"$(nix --version 2>/dev/null || printf 'unknown')")"

	cmd+=(--prompt "System context: \n${_context}")
	for _ctx_file in "${ctx_files[@]}"; do
		cmd+=(--file "${_ctx_file}")
	done
fi

exec "${cmd[@]}" "${pass_args[@]}"
