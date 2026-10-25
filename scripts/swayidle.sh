#!/bin/sh
# rstl.sway idle daemon wrapper.
#
# The ratl power dialog writes a generated config to
# ~/.config/rstl.sway/local/swayidle. Prefer it, and fall back to the
# repository default when the dialog has never been used.

DOTFILES_DIR="${RSTL_SWAY_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/rstl.sway}"
CONFIG="$DOTFILES_DIR/local/swayidle"
[ -r "$CONFIG" ] || CONFIG="$DOTFILES_DIR/swayidle/config"

if ! command -v swayidle >/dev/null 2>&1; then
    echo "swayidle: swayidle is not installed" >&2
    exit 127
fi

exec swayidle -w -C "$CONFIG" "$@"
