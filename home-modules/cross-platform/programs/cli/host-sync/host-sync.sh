# shellcheck disable=SC2148
# Sync a home directory with another host, using unison.
#
# Unison is bidirectional by default: it reconciles both sides and propagates
# each change to the other. --push and --pull restrict that to one direction.
set -eu

host=""
push=0
pull=0
preview=0
path=""

usage() {
	printf 'Usage: host-sync [options] <host>\n' >&2
	printf '  --push          send local changes only; ignore remote ones\n' >&2
	printf '  --pull          take remote changes only; ignore local ones\n' >&2
	printf '  --preview       list what would change, then exit\n' >&2
	printf '  --path <path>   sync one path rather than the whole profile\n' >&2
	printf '\nConfigured hosts:\n' >&2
	for h in ${KNOWN_HOSTS}; do
		printf '  %s\n' "${h}" >&2
	done
	exit 1
}

while [ "$#" -gt 0 ]; do
	case "${1}" in
		--push) push=1 ;;
		--pull) pull=1 ;;
		--preview) preview=1 ;;
		--path)
			shift
			path="${1:-}"
			;;
		--path=*) path="${1#--path=}" ;;
		--help | -h) usage ;;
		-*)
			printf 'host-sync: unknown option: %s\n' "${1}" >&2
			usage
			;;
		*)
			if [ -z "${host}" ]; then
				host="${1}"
			else
				printf 'host-sync: unexpected argument: %s\n' "${1}" >&2
				usage
			fi
			;;
	esac
	shift
done

[ -n "${host}" ] || { printf 'host-sync: no host given\n' >&2; usage; }

if [ "${push}" = "1" ] && [ "${pull}" = "1" ]; then
	printf 'host-sync: --push and --pull are mutually exclusive\n' >&2
	exit 1
fi

# Check the host is one we have a profile for. Unison would otherwise fail
# with a profile-not-found error that does not say the name was wrong.
known=0
for h in ${KNOWN_HOSTS}; do
	[ "${h}" = "${host}" ] && known=1
done

if [ "${known}" != "1" ]; then
	printf 'host-sync: no profile for host: %s\n' "${host}" >&2
	usage
fi

# ssh, not a port check.
#
# `nc -z host 22` says the port is open, which is not the question — a host
# with sshd running and your key rejected passes that and then fails inside
# unison, where the error is buried in its output.
[ "${CHECK_REACHABLE}" = "1" ] && { 
	printf 'Checking %s...\n' "${host}" >&2
	if ! ssh -o ConnectTimeout="${SSH_TIMEOUT}" -o BatchMode=yes "${host}" true 2>/dev/null; then
		printf 'host-sync: cannot reach %s over ssh\n' "${host}" >&2
		printf '  The host may be down, or your key may not be accepted there.\n' >&2
		printf '  Try: ssh %s true\n' "${host}" >&2
		exit 1
	fi
}

set -- "${host}"

if [ "${preview}" = "1" ]; then
	# -testserver only connects and exits: it is a reachability check, which
	# the previous version offered as --dry-run.
	#
	# Unison has no dry-run. What it does have is its interactive mode: with
	# auto and batch off it lists every difference and asks. Answering nothing
	# and quitting is the preview.
	set -- "$@" -auto=false -batch=false
fi

if [ "${push}" = "1" ]; then
	# The numbers are unison's roots in profile order: root 1 is local, root 2
	# is the remote. Blocking creation, deletion, and update on root 2 means
	# nothing from the remote comes back.
	set -- "$@" -nocreation=2 -nodeletion=2 -noupdate=2
elif [ "${pull}" = "1" ]; then
	set -- "$@" -nocreation=1 -nodeletion=1 -noupdate=1
fi

[ -n "${path}" ] && set -- "$@" -path "${path}"

exec unison "$@"
