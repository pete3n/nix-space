# shellcheck disable=SC2148
if hypr-popup is-open "${WINDOW_CLASS}"; then
	exec hypr-popup close "${WINDOW_CLASS}"
fi

# TERMINAL_CMD is a complete command line rendered by the terminals module, so
# eval re-splits it into words rather than passing it as one argument.
eval "exec ${TERMINAL_CMD}"
