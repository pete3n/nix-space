# shellcheck disable=SC2148
# Show tmux keybindings in rofi, as selectable rows.
#
# Reads the live server, not a config file:`tmux list-keys` reports the
# bindings actually in effect, including anything a plugin added or a session
# changed at runtime.
#
# Prints rows only. The caller adds its own header and handles selection.
# This writes nothing but the list.

set -eu

# Require server running
if ! tmux ls >/dev/null 2>&1; then
	printf "<b>tmux not running</b>  <i>start default session</i><span color='#dddddd'>  tmux new-session -A -s 0</span>\n"
	exit 0
fi

# Prefer list-keys (shows effective binds).
out="$(tmux list-keys 2>/dev/null || true)"
if [ -z "$out" ]; then
	printf "<b>No keybinds returned</b><span color='#dddddd'>  echo 'tmux list-keys produced no output'</span>\n"
	exit 0
fi

printf '%s\n' "$out" \
	| awk -v q="'" '
			function esc(s) {
				gsub(/&/, "\\&amp;", s)
				gsub(/</, "\\&lt;", s)
				gsub(/>/, "\\&gt;", s)
				return s
			}

			# Split a line into tokens by spaces, preserving quoted strings as single tokens.
			# tmux output can include quoted args (e.g., run-shell "foo bar").
			function tokenize(s, a,    i, n, c, tok, inq) {
				n = 0; tok = ""; inq = 0
				for (i = 1; i <= length(s); i++) {
					c = substr(s, i, 1)
					if (c == "\"") { inq = !inq; tok = tok c; continue }
					if (!inq && c == " ") {
						if (tok != "") { a[++n] = tok; tok = "" }
						continue
					}
					tok = tok c
				}
				if (tok != "") a[++n] = tok
				return n
			}

			{
				line = $0
				sub(/^[[:space:]]+/, "", line)
				if (line == "") next

				# Accept bind / bind-key
				if (line !~ /^(bind|bind-key)[[:space:]]/) next

				# Normalize whitespace
				gsub(/[[:space:]]+/, " ", line)

				# Tokenize (preserve quoted strings)
				n = tokenize(line, t)
				if (n < 3) next

				# Defaults
				table = "root"
				key = ""
				cmd_start = 0

				# Walk tokens, skip known flags, capture -T table and find key
				# Typical forms:
				# bind-key -T prefix c new-window
				# bind -n M-Left previous-window
				i = 2
				while (i <= n) {
					if (t[i] == "-T" && i+1 <= n) { table = t[i+1]; i += 2; continue }
					if (t[i] == "-n" || t[i] == "-r") { i += 1; continue }
					# Some tmux versions include -N "note" in list-keys, keep it if present as tokens
					if (t[i] == "-N" && i+1 <= n) { i += 2; continue }

					# First non-flag token after options is key
					key = t[i]
					cmd_start = i + 1
					break
				}

				if (key == "" || cmd_start == 0 || cmd_start > n) next

				# Rebuild command (everything after key) exactly as tokens
				cmd = ""
				for (j = cmd_start; j <= n; j++) {
					cmd = cmd t[j]
					if (j < n) cmd = cmd " "
				}
				if (cmd == "") next

				# Display label
				table_esc = esc(table)
				key_esc   = esc(key)
				disp = "<b>" table_esc "  " key_esc "</b>"

				action = esc("tmux " cmd)
				printf "%s<span color=%s#dddddd%s>  %s</span>\n", disp, q, q, action
			}
		'
