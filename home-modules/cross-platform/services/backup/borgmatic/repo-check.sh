# shellcheck disable=SC2148
# Report whether the configured borg repositories exist.
#
# This does not create a repository. A borg repo must be initialised before
# borgmatic can use it. If the repo location is a network mount, `borg init` 
# will succeed even if the mountpoint is down and create a second empty 
# repository there. When the mount returns, the real one is shadowed and backups 
# silently go to the wrong place, with the archive history apparently gone.
#
set -eu

exit_status=0

check_repo() {
	_repo="$1"
	_label="$2"

	case "${_repo}" in
		ssh://*)
			# A remote repository cannot be checked with a file test, and
			# `borg info` over ssh is too slow for a routine check.
			# This reports what command should be run.
			printf '%s: %s (remote - check with: borg info %s)\n' \
				"${_label}" "${_repo}" "${_repo}"
			return 0
			;;
	esac

	if [ ! -d "${_repo}" ]; then
		printf '%s: Missing directory %s\n' "${_label}" "${_repo}" >&2
		exit_status=1
		return 0
	fi

	# A borg repository has a `config` file at its root. An empty directory
	# is the symptom of an unmounted filesystem, which is exactly the case
	# not to initialise into.
	if [ ! -f "${_repo}/config" ]; then
		printf '%s: %s exists but is NOT a borg repository\n' "${_label}" "${_repo}" >&2

		if [ -z "$(ls -A "${_repo}" 2>/dev/null)" ]; then
			printf '  The directory is empty. If it is a mountpoint, check the\n' >&2
			printf '  mount before initialising. Creating a repository on an\n' >&2
			printf '  unmounted path shadows the real one when it returns.\n' >&2
		fi

		printf '  Initialise with:\n' >&2
		printf '    borgmatic rcreate --encryption repokey-blake2 --repository %s\n' "${_repo}" >&2
		exit_status=1
		return 0
	fi

	printf '%s: ok %s\n' "${_label}" "${_repo}"
}

for spec in "$@"; do
	label="${spec%%=*}"
	repo="${spec#*=}"
	check_repo "${repo}" "${label}"
done

exit "${exit_status}"
