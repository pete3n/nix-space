# shellcheck disable=SC2148
# Preserve PATH across tmux on a host where the OS is not managed by Nix.
#
# This is meant for hosts not managed by Nix where the PATH isn't passsed to
# tmux from the Nix profile. 
#
# This is not needed where Nix manages the OS: there the profile is on PATH from 
# the session environment, and tmux inherits it like anything else.
_ns_path_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}"
_ns_path_state_file="${_ns_path_state_dir}/nix-path.env"

mkdir -p "${_ns_path_state_dir}"

if [ -z "${TMUX:-}" ]; then
	# Outside tmux: this PATH is the good one. Record it if it changed.
	if [ -f "${_ns_path_state_file}" ]; then
		_ns_saved_path="$(sed -n 's/^PATH="\(.*\)"$/\1/p' "${_ns_path_state_file}")"
	else
		_ns_saved_path=""
	fi

	if [ "${PATH}" != "${_ns_saved_path}" ]; then
		printf 'PATH="%s"\nexport PATH\n' "${PATH}" > "${_ns_path_state_file}"
	fi
else
	# Inside tmux: restore, if what we have differs from what was saved.
	if [ -f "${_ns_path_state_file}" ]; then
		_ns_saved_path="$(sed -n 's/^PATH="\(.*\)"$/\1/p' "${_ns_path_state_file}")"

		if [ -n "${_ns_saved_path}" ] && [ "${PATH}" != "${_ns_saved_path}" ]; then
			PATH="${_ns_saved_path}"
			export PATH
		fi
	fi
fi

unset _ns_path_state_dir _ns_path_state_file _ns_saved_path
