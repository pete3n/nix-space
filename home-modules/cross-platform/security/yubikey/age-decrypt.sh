# shellcheck disable=SC2148
# Decrypt one age file using a YubiKey identity.
#
# Args: output_file age_file identity_file
set -eu

output_file="${1:?output file required}"
age_file="${2:?age file required}"
identity_file="${3:?identity file required}"

# Already decrypted: nothing to do.
#
# NOTE this means a rotated secret is not re-decrypted: the file exists, so
# the old plaintext stays. Remove it to force a fresh decrypt.
[ -f "${output_file}" ] && exit 0

if ! [ -S "${PCSCD_SOCKET}" ]; then
	printf 'yubi-age-decrypt: pcscd socket not found at %s\n' "${PCSCD_SOCKET}" >&2
	printf '  The smartcard daemon is not running, so the YubiKey cannot be\n' >&2
	printf '  reached. Enable services.pcscd on the system, then re-run.\n' >&2
	printf '  Skipping %s.\n' "${output_file}" >&2
	exit 0
fi

# A YubiKey decrypt needs a PIN and a touch, neither of which can be supplied
# without a terminal. A non-interactive activation would hang on the prompt.
if [ ! -t 0 ]; then
	printf 'yubi-age-decrypt: not a TTY; skipping %s\n' "${output_file}" >&2
	printf '  Re-run activation from a terminal to decrypt.\n' >&2
	exit 0
fi

output_dir="$(dirname "${output_file}")"
mkdir -p "${output_dir}"
chmod 700 "${output_dir}"

printf 'yubi-age-decrypt: decrypting %s (touch your key)...\n' "${output_file}" >&2

# age writing directly to the destination leaves a partial file if the touch
# times out, and then the existence check above would skip it forever.
tmp_file="${output_file}.partial"

if age --decrypt --identity "${identity_file}" --output "${tmp_file}" "${age_file}"; then
	chmod 600 "${tmp_file}"
	mv -f "${tmp_file}" "${output_file}"
	printf 'yubi-age-decrypt: wrote %s\n' "${output_file}" >&2
else
	rm -f "${tmp_file}"
	printf 'yubi-age-decrypt: FAILED to decrypt %s\n' "${output_file}" >&2
	exit 1
fi
