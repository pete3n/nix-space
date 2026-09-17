# shellcheck disable=SC2148
# git runs commit-msg hooks from the top of the working tree with the message
# file as the only argument.
message_file="${1}"

# A repository's own .gitlint wins; otherwise the module's config applies.
# gitlint itself reads only ./.gitlint or --config: it has no per-user file.
config_args=()
if [ ! -f .gitlint ]; then
	config_args=(--config "${GITLINT_CONFIG_FILE}")
fi

if gitlint "${config_args[@]}" --staged --msg-filename "${message_file}"; then
	exit 0
fi

printf '\n' >&2
printf 'Commit message rejected by gitlint; see the rule codes above.\n' >&2
printf 'Titles follow Conventional Commits, e.g.:\n' >&2
printf '  feat: add lid event daemon\n' >&2
printf '  fix(nfs): order automount after network-online\n' >&2
printf '\n' >&2
printf 'To bypass for this commit: git commit --no-verify\n' >&2
exit 1
