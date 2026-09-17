# shellcheck disable=SC2148
cover="${STATE_DIR}/cover.jpg"
cover_tmp="${STATE_DIR}/cover.tmp"

mkdir -p "${STATE_DIR}"

# Hide the cursor for the life of the window and restore it on exit — a block
# cursor parked over album art is distracting.
printf '\033[?25l'
trap 'printf "\033[?25h"' EXIT INT TERM

dump_cover() {
	_uri="$(mpc current -f %file% 2>/dev/null || true)"

	if [ -z "${_uri}" ]; then
		rm -f "${cover}" 2>/dev/null || true
		return 0
	fi

	# Temp file then rename, so a redraw never reads a partial write.
	if mpc albumart "${_uri}" > "${cover_tmp}" 2>/dev/null && [ -s "${cover_tmp}" ]; then
		mv -f "${cover_tmp}" "${cover}"
	else
		# A failed extraction leaves NOTHING rather than the previous track's
		# art, which would be actively misleading.
		rm -f "${cover_tmp}" "${cover}" 2>/dev/null || true
	fi
}

draw() {
	printf '\033[2J\033[3J\033[H'

	[ -s "${cover}" ] || return 0

	# No --size. chafa reads the terminal size itself and keeps one row free at
	# the bottom; forcing --size to the full height let the image be exactly as
	# tall as the window, so its trailing newline scrolled the top row away.
	# --scale max fits the image within the view (the default for kitty/sixel
	# output is native pixel size), and --align then centres it in the space
	# that leaves. --polite stops chafa re-showing the cursor after each draw.
	chafa \
		--clear \
		--polite on \
		--scale max \
		--align center,center \
		"${cover}" 2>/dev/null || true

	printf '\033[H'
}

dump_cover
draw

# `mpc idle player` blocks until playback state changes — no polling, and it
# wakes on track change rather than on a timer.
#
# NOTE this is why killing this process needs the process GROUP: bash defers
# signals while waiting on a foreground child, so a plain SIGTERM sits pending
# until the next playback event.
while mpc idle player >/dev/null 2>&1; do
	dump_cover
	draw
done
