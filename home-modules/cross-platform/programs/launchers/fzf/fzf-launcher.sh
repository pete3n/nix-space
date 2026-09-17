# shellcheck disable=SC2148
# Application launcher for macOS: picks an app or a command, and run it.
#
# Indexes macOS applications, home-manager's app bundles, and
# executables in the Nix profile.
set -eu

PROFILE_BIN="${NS_LAUNCHER_PROFILE_BIN:-$HOME/.nix-profile/bin}"
TERMINAL_CMD="${NS_LAUNCHER_TERMINAL:-}"
PROMPT="${NS_LAUNCHER_PROMPT:-Launch: }"
HEIGHT="${NS_LAUNCHER_HEIGHT:-40%}"

apps="$(
	{
		find -L /Applications /System/Applications \
			-maxdepth 2 -name '*.app' -type d 2>/dev/null \
			| sed 's|.*/||; s|\.app$||'

		find -L "$HOME/Applications/Home Manager Apps" \
			-maxdepth 1 -name '*.app' -type d 2>/dev/null \
			| sed 's|.*/||; s|\.app$||'

		find -L "${PROFILE_BIN}" /run/current-system/sw/bin \
			-maxdepth 1 \( -type f -o -type l \) 2>/dev/null \
			| sed 's|.*/||'
	} | sort -u
)"

# --print-query so a query matching nothing is still usable: typing
# `vim notes.txt` runs it rather than requiring an existing entry. tail -1
# takes the selection when there is one and the query when there is not.
selection="$(
	printf '%s\n' "${apps}" \
		| fzf --prompt="${PROMPT}" \
			--layout=reverse \
			--border \
			--height="${HEIGHT}" \
			--no-multi \
			--print-query \
		| tail -1
)" || exit 0

[ -n "${selection}" ] || exit 0

# Try the whole selection as a command first, before splitting on spaces.
#
# Splitting is only wanted when the user typed arguments, which
# is the case where the whole string is not a known command.
cmd="${selection}"
args=""

if ! [ -f "${PROFILE_BIN}/${selection}" ] \
	&& ! [ -L "${PROFILE_BIN}/${selection}" ] \
	&& ! [ -d "/Applications/${selection}.app" ] \
	&& ! [ -d "/System/Applications/${selection}.app" ] \
	&& ! [ -d "$HOME/Applications/Home Manager Apps/${selection}.app" ]
then
	cmd="${selection%% *}"
	case "${selection}" in
		*' '*) args="${selection#* }" ;;
	esac
fi

if [ -f "${PROFILE_BIN}/${cmd}" ] || [ -L "${PROFILE_BIN}/${cmd}" ]; then
	# A profile binary needs a terminal AND a login environment: launched
	# from the GUI it doesn't inherit the PATH or the session variables, so the
	# nix-daemon and home-manager profile scripts must be sourced.
	if [ -z "${TERMINAL_CMD}" ]; then
		printf 'fzf-launcher: no terminal configured; cannot run %s\n' "${cmd}" >&2
		exit 1
	fi

	# shellcheck disable=SC2086
	${TERMINAL_CMD} -e /bin/sh -c \
		"source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null; \
		 source $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh 2>/dev/null; \
		 exec ${PROFILE_BIN}/${cmd} ${args}"
else
	open -a "${cmd}"
fi
