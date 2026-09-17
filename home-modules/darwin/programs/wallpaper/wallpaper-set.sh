# Set the desktop wallpaper to a specific image.
set -eu

WALLPAPER="${1:-}"

if [ -z "${WALLPAPER}" ]; then
	printf 'Usage: wallpaper-set <image>\n' >&2
	exit 1
fi

if [ ! -f "${WALLPAPER}" ]; then
	printf 'wallpaper-set: not a file: %s\n' "${WALLPAPER}" >&2
	exit 1
fi

# An absolute path: System Events resolves POSIX file against the root, so a
# relative one silently sets nothing.
case "${WALLPAPER}" in
	/*) ;;
	*) WALLPAPER="${PWD}/${WALLPAPER}" ;;
esac

osascript -e "tell application \"System Events\" to set picture of every desktop to (POSIX file \"${WALLPAPER}\")"
