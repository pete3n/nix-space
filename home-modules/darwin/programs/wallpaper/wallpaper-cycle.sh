# Set the desktop wallpaper to the next image in its directory.
#
# The directory comes from the CURRENT wallpaper rather than from
# configuration, so pointing the desktop at a different folder by any means —
# System Settings, another script — moves the cycle with it.
set -eu

WALLPAPER_DIR="${1:-}"

get_current() {
	osascript -e 'tell application "System Events" to get picture of desktop 1' 2>/dev/null
}

set_wallpaper() {
	# POSIX file, not a plain string: System Events wants an alias, and a
	# bare path is accepted and silently ignored.
	osascript -e "tell application \"System Events\" to set picture of every desktop to (POSIX file \"${1}\")"
}

current="$(get_current)" || current=""

if [ -z "${WALLPAPER_DIR}" ]; then
	if [ -z "${current}" ]; then
		printf 'wallpaper-cycle: no current wallpaper and no directory given\n' >&2
		exit 1
	fi
	WALLPAPER_DIR="$(dirname "${current}")"
fi

if [ ! -d "${WALLPAPER_DIR}" ]; then
	printf 'wallpaper-cycle: not a directory: %s\n' "${WALLPAPER_DIR}" >&2
	exit 1
fi

# Sorted so the order is stable between runs — find returns directory order,
# which is neither alphabetical nor consistent across filesystems.
#
# A newline-delimited list rather than an array: this needs no bash, and a
# wallpaper path containing a newline is not a case worth carrying machinery
# for.
files="$(
	find "${WALLPAPER_DIR}" -maxdepth 1 -type f \
		\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
		   -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.heic' \) \
		| sort
)"

if [ -z "${files}" ]; then
	printf 'wallpaper-cycle: no images in %s\n' "${WALLPAPER_DIR}" >&2
	exit 1
fi

# Take the line after the current one, wrapping to the first.
#
# The previous version compared each candidate against the current path with
# string equality and left next_wallpaper empty when nothing matched — which
# happens whenever the reported path differs in form from what find produces,
# a resolved symlink or a trailing space being enough. Falling back to the
# first entry means an unrecognised current wallpaper starts the cycle rather
# than failing.
next="$(
	printf '%s\n' "${files}" | awk -v cur="${current}" '
		{ lines[NR] = $0 }
		$0 == cur { found = NR }
		END {
			if (found && found < NR) print lines[found + 1]
			else print lines[1]
		}
	'
)"

set_wallpaper "${next}"
