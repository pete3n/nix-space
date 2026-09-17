# shellcheck disable=SC2148
# Runs with nounset only. errexit is deliberately off: every action here is
# best effort and returns to its menu, and an mpc failure must not tear down
# the rofi session. pipefail is off because `sort | head -n N` lets sort take
# SIGPIPE, which pipefail would report as a failed pipeline.

# Two-column TAB-separated lines throughout: file path or queue position in
# column one, a human label in column two.
track_fmt='%artist% — %title%'
tab_fmt='%file%\t'"${track_fmt}" # mpc expands the \t itself

rofi_menu() {
	_prompt="${1}"
	shift
	rofi -dmenu -i -p "${_prompt}" "$@"
}

rofi_multi() {
	_prompt="${1}"
	shift
	rofi -dmenu -i -multi-select -p "${_prompt}" "$@"
}

# stdin: file<TAB>pretty. Prints file<TAB>pretty, or with "pos" as the argument
# the 1-based line number in place of the file. An empty or bare "—" label falls
# back to the file's base name, which mpc cannot do on its own.
fmt_pretty() {
	awk -F'\t' -v key="${1}" '
		function base(s) { sub(/^.*\//, "", s); sub(/\.[^.]*$/, "", s); return s }
		{
			pretty = $2
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", pretty)
			if (pretty == "" || pretty ~ /^[[:space:]]*—[[:space:]]*$/) pretty = base($1)
			printf "%s\t%s\n", (key == "pos" ? NR : $1), pretty
		}'
}

# stdin: file<TAB>pretty lines as multi-selected; adds the file column.
add_files_from_tablist() {
	while IFS=$'\t' read -r _file _; do
		[ -n "${_file}" ] || continue
		mpc add "${_file}" >/dev/null
	done
}

# The numbered queue as pos<TAB>pretty, or nothing if it is empty.
queue_lines() {
	mpc -f "${tab_fmt}" playlist 2>/dev/null | fmt_pretty pos
}

queue_jump() {
	_lines="$(queue_lines)"
	if [ -z "${_lines}" ]; then
		printf '%s\n' "Queue is empty" | rofi_menu "Queue"
		return 0
	fi
	_sel="$(printf '%s\n' "${_lines}" | rofi_menu "Jump to")" || return 0
	_pos="${_sel%%$'\t'*}"
	[ -n "${_pos}" ] || return 0
	mpc play "${_pos}" >/dev/null
}

queue_delete() {
	_lines="$(queue_lines)"
	if [ -z "${_lines}" ]; then
		printf '%s\n' "Queue is empty" | rofi_menu "Queue"
		return 0
	fi
	_picks="$(printf '%s\n' "${_lines}" | rofi_multi "Delete")" || return 0
	[ -n "${_picks}" ] || return 0
	# Delete highest -> lowest so indices stay valid.
	printf '%s\n' "${_picks}" | cut -f1 | sort -rn | while IFS= read -r _pos; do
		[ -n "${_pos}" ] || continue
		mpc del "${_pos}" >/dev/null
	done
}

queue_clear() {
	_confirm="$(printf '%s\n' "← Back" "Clear queue (confirm)" | rofi_menu "Clear Queue")" || return 0
	[ "${_confirm}" = "Clear queue (confirm)" ] || return 0
	mpc clear >/dev/null
}

queue_save() {
	_name="$(rofi_menu "Playlist name" </dev/null)" || return 0
	[ -n "${_name}" ] || return 0
	mpc save "${_name}" >/dev/null
}

queue_menu() {
	while :; do
		_choice="$(printf '%s\n' \
			"← Back" \
			"Jump" \
			"Delete" \
			"Clear" \
			"Save" \
			| rofi_menu "Queue")" || return 0
		case "${_choice}" in
			"← Back") return 0 ;;
			"Jump") queue_jump ;;
			"Delete") queue_delete ;;
			"Clear") queue_clear ;;
			"Save") queue_save ;;
		esac
	done
}

# Prints the chosen playlist name; fails on back, escape, or no playlists.
pick_playlist() {
	_pls="$(mpc lsplaylists 2>/dev/null)"
	if [ -z "${_pls}" ]; then
		printf '%s\n' "No playlists found" | rofi_menu "Playlists"
		return 1
	fi
	_pl="$(printf '%s\n' "← Back" "${_pls}" | rofi_menu "Playlists")" || return 1
	[ "${_pl}" != "← Back" ] || return 1
	[ -n "${_pl}" ] || return 1
	printf '%s\n' "${_pl}"
}

playlist_load_replace() {
	_pl="$(pick_playlist)" || return 0

	_preview="$(mpc -f "${track_fmt}" playlist "${_pl}" 2>/dev/null)"

	_confirm="$(printf '%s\n' "← Back" "Replace queue (confirm)" "${_preview}" \
		| rofi_menu "Load: ${_pl}")" || return 0
	[ "${_confirm}" = "Replace queue (confirm)" ] || return 0

	mpc clear >/dev/null
	mpc load "${_pl}" >/dev/null
	mpc play >/dev/null 2>&1
}

playlist_append() {
	_pl="$(pick_playlist)" || return 0
	mpc load "${_pl}" >/dev/null
}

playlist_delete() {
	_pl="$(pick_playlist)" || return 0
	_confirm="$(printf '%s\n' "← Back" "Delete (confirm): ${_pl}" | rofi_menu "Delete Playlist")" || return 0
	[ "${_confirm}" = "Delete (confirm): ${_pl}" ] || return 0
	mpc rm "${_pl}" >/dev/null
}

# Sets current_file and current_pretty for the playing track; fails, after
# telling the user, if nothing is playing.
current_track() {
	current_file="$(mpc -f '%file%' current 2>/dev/null)"
	if [ -z "${current_file}" ]; then
		printf '%s\n' "Nothing is currently playing" | rofi_menu "${1}"
		return 1
	fi
	current_pretty="$(mpc -f "${track_fmt}" current 2>/dev/null)"
	[ -n "${current_pretty}" ] || current_pretty="${current_file}"
}

playlist_add_current() {
	current_track "Add to Playlist" || return 0

	_existing="$(mpc lsplaylists 2>/dev/null)"
	_choice="$(printf '%s\n' "← Back" "New playlist" "${_existing}" \
		| rofi_menu "Add: ${current_pretty}")" || return 0
	[ "${_choice}" != "← Back" ] || return 0
	[ -n "${_choice}" ] || return 0

	if [ "${_choice}" = "New playlist" ]; then
		_pl="$(rofi_menu "New playlist name" </dev/null)" || return 0
		[ -n "${_pl}" ] || return 0
	else
		_pl="${_choice}"
	fi

	if ! mpc addplaylist "${_pl}" "${current_file}" >/dev/null; then
		printf '%s\n' "Failed to add to ${_pl}" | rofi_menu "Error" >/dev/null
		return 0
	fi
	printf '%s\n' "Added to ${_pl} — press Enter" | rofi_menu "Add to Playlist" >/dev/null
}

playlist_remove_current() {
	current_track "Remove from Playlist" || return 0

	_existing="$(mpc lsplaylists 2>/dev/null)"
	if [ -z "${_existing}" ]; then
		printf '%s\n' "No playlists found" | rofi_menu "Remove from Playlist"
		return 0
	fi

	_pl="$(printf '%s\n' "← Back" "${_existing}" | rofi_menu "Remove: ${current_pretty}")" || return 0
	[ "${_pl}" != "← Back" ] || return 0
	[ -n "${_pl}" ] || return 0

	# Every 1-based position of the current file in the playlist, highest first
	# so deletions do not shift the ones still to come.
	mpc -f '%file%' playlist "${_pl}" 2>/dev/null \
		| awk -v target="${current_file}" '$0 == target { print NR }' \
		| sort -rn \
		| while IFS= read -r _pos; do
			[ -n "${_pos}" ] || continue
			mpc delplaylist "${_pl}" "${_pos}" >/dev/null
		done
}

playlist_menu() {
	while :; do
		_choice="$(printf '%s\n' \
			"← Back" \
			"Load playlist (replace queue)" \
			"Append playlist to queue" \
			"Add current track to playlist" \
			"Remove current track" \
			"Delete playlist" \
			| rofi_menu "Playlist")" || return 0
		case "${_choice}" in
			"← Back") return 0 ;;
			"Load playlist (replace queue)") playlist_load_replace ;;
			"Append playlist to queue") playlist_append ;;
			"Add current track to playlist") playlist_add_current ;;
			"Remove current track") playlist_remove_current ;;
			"Delete playlist") playlist_delete ;;
		esac
	done
}

# Runs an mpc search, offers the results for multi-selection, adds the picks.
search_and_add() {
	_prompt="${1}"
	shift
	_picks="$(mpc -f "${tab_fmt}" search "$@" 2>/dev/null | fmt_pretty file | rofi_multi "${_prompt}")" || return 0
	printf '%s\n' "${_picks}" | add_files_from_tablist
}

search_add_any() {
	search_and_add "Add (All)" any ""
}

search_add_field_prompt() {
	_field="${1}"

	# Pre-populate every unique value for the field so rofi can fuzzy filter.
	_all_values="$(mpc list "${_field}" 2>/dev/null)"
	if [ -z "${_all_values}" ]; then
		printf '%s\n' "No ${_field} values found in library" | rofi_menu "${_field}"
		return 0
	fi

	_query="$(printf '%s\n' "${_all_values}" | rofi_menu "Search ${_field}")" || return 0
	[ -n "${_query}" ] || return 0

	search_and_add "Add (${_field}: ${_query})" "${_field}" "${_query}"
}

search_add_genre() {
	_genres="$(mpc list genre 2>/dev/null)"
	if [ -z "${_genres}" ]; then
		printf '%s\n' "No genres found" | rofi_menu "Genre"
		return 0
	fi
	_genre="$(printf '%s\n' "← Back" "${_genres}" | rofi_menu "Genre")" || return 0
	[ "${_genre}" != "← Back" ] || return 0
	search_and_add "Add (Genre)" genre "${_genre}"
}

# Prints mpd's music directory: from its config, then $MPD_MUSIC_DIR, then
# ~/Music. Fails if none exists.
get_music_dir() {
	_dir="$(mpc config 2>/dev/null | awk -F' = ' '$1 == "music_directory" { gsub(/"/, "", $2); print $2; exit }')"
	for _candidate in "${_dir}" "${MPD_MUSIC_DIR:-}" "${HOME}/Music"; do
		if [ -n "${_candidate}" ] && [ -d "${_candidate}" ]; then
			printf '%s\n' "${_candidate}"
			return 0
		fi
	done
	return 1
}

search_add_newest() {
	_music_dir="$(get_music_dir)"
	if [ -z "${_music_dir}" ]; then
		printf '%s\n' "music_directory not found (set MPD_MUSIC_DIR?)" | rofi_menu "Newest"
		return 0
	fi

	# find -printf, NOT a read loop with a stat per file. The previous form
	# forked stat once per track and ran the whole body in a subshell; on a
	# library of any size that is a pause long enough to read as a hang.
	#
	# %T@ is the mtime as a number and %P the path relative to the search root,
	# which is exactly the form mpc wants. The path alone goes to fmt_pretty,
	# whose empty-label fallback supplies the base name.
	_newest="$(find "${_music_dir}" -type f -printf '%T@\t%P\n' 2>/dev/null \
		| sort -rn -k1,1 \
		| head -n "${NEWEST_LIMIT}" \
		| cut -f2 \
		| fmt_pretty file)"

	if [ -z "${_newest}" ]; then
		printf '%s\n' "No files found" | rofi_menu "Newest"
		return 0
	fi

	_picks="$(printf '%s\n' "${_newest}" | rofi_multi "Add (Newest)")" || return 0
	printf '%s\n' "${_picks}" | add_files_from_tablist
}

search_rescan_db() {
	_confirm="$(printf '%s\n' "← Back" "Rescan MPD database (confirm)" | rofi_menu "Rescan DB")" || return 0
	[ "${_confirm}" = "Rescan MPD database (confirm)" ] || return 0
	mpc rescan >/dev/null 2>&1 || mpc update >/dev/null 2>&1
	printf '%s\n' "Scan started (Go back)" | rofi_menu "MPD" >/dev/null
}

search_menu() {
	while :; do
		_choice="$(printf '%s\n' \
			"← Back" \
			"All (any)" \
			"Artist (prompt)" \
			"Genre (pick)" \
			"Newest (file mtime)" \
			"Title (prompt)" \
			"Update DB (re-scan)" \
			| rofi_menu "Search")" || return 0
		case "${_choice}" in
			"← Back") return 0 ;;
			"All (any)") search_add_any ;;
			"Artist (prompt)") search_add_field_prompt artist ;;
			"Genre (pick)") search_add_genre ;;
			"Newest (file mtime)") search_add_newest ;;
			"Title (prompt)") search_add_field_prompt title ;;
			"Update DB (re-scan)") search_rescan_db ;;
		esac
	done
}

while :; do
	_choice="$(printf '%s\n' "Queue" "Playlist" "Search" "Close" | rofi_menu "MPD")" || exit 0
	case "${_choice}" in
		"Queue") queue_menu ;;
		"Playlist") playlist_menu ;;
		"Search") search_menu ;;
		"Close"|"") exit 0 ;;
	esac
done
