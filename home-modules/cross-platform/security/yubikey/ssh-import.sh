# shellcheck disable=SC2148
# Import resident SSH keys from a security key.
#
# `ssh-keygen -K` writes every resident key in the token to the CURRENT
# DIRECTORY, which is why this changes to ~/.ssh first — there is no output
# path option.
set -eu

ssh_dir="${HOME}/.ssh"

mkdir -p "${ssh_dir}"
chmod 700 "${ssh_dir}"
cd "${ssh_dir}"

need_import=0

if [ "$#" -eq 0 ]; then
	# No expected names given: import if there are no resident keys at all.
	if ! find . -maxdepth 1 -type f -name 'id_ed25519_sk_rk_*' ! -name '*.pub' \
		-print -quit | grep -q .
	then
		need_import=1
	fi
else
	for key in "$@"; do
		if [ ! -f "${ssh_dir}/${key}" ] || [ ! -f "${ssh_dir}/${key}.pub" ]; then
			need_import=1
			break
		fi
	done
fi

[ "${need_import}" -eq 1 ] || exit 0

# The import needs a PIN and a touch, so it cannot run unattended.
if [ ! -t 0 ]; then
	printf 'yubi-ssh-import: not a TTY; skipping key import\n' >&2
	printf '  Re-run activation from a terminal, or run yubi-ssh-import by hand.\n' >&2
	exit 0
fi

printf 'yubi-ssh-import: importing resident keys (touch your key)...\n' >&2

# `|| rc=$?` rather than running it bare.
#
# Under set -e a failing ssh-keygen terminates the script at that line.
rc=0
ssh-keygen -K || rc=$?

if [ "${rc}" -eq 0 ]; then
	printf 'yubi-ssh-import: imported\n' >&2
else
	printf 'yubi-ssh-import: import failed (exit %s)\n' "${rc}" >&2
	printf '  A wrong PIN, a missing touch, or no resident keys on the token.\n' >&2
fi

exit "${rc}"
