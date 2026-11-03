#!/bin/sh
DOTFILES_DIR="${RSTL_SWAY_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/rstl.sway}"
timeout=8000
if [ -r "$DOTFILES_DIR/local/notification-timeout" ]; then
    seconds=$(cat "$DOTFILES_DIR/local/notification-timeout")
    case "$seconds" in ''|*[!0-9]*) ;; *) timeout=$((seconds * 1000)) ;; esac
fi
killall -q mako 2>/dev/null || true
exec mako --default-timeout "$timeout"
