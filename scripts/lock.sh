#!/bin/sh
# rstl.sway lock screen — swaylock with the current wallpaper as background.
#
# The wallpaper path is read from ${WALLPAPER_CONF}, then
# local/wallpaper (written by the ratl wallpaper dialog), then the
# repository wallpaper file; each is a plain text file holding one path.
# If that file is missing or points to a missing file, the most recently
# modified wallpaper in ~/Pictures/Wallpapers is used instead.

DOTFILES_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rstl.sway"
if [ -n "${WALLPAPER_CONF:-}" ]; then
    :
elif [ -r "$DOTFILES_DIR/local/wallpaper" ]; then
    WALLPAPER_CONF="$DOTFILES_DIR/local/wallpaper"
else
    WALLPAPER_CONF="$DOTFILES_DIR/wallpaper"
fi

image=""
if [ -r "$WALLPAPER_CONF" ]; then
    image="$(head -n1 "$WALLPAPER_CONF")"
    [ "${image#\~}" != "$image" ] && image="$HOME${image#\~}"
fi

if [ -z "$image" ] || [ ! -f "$image" ]; then
    image="$(ls -t "$HOME"/Pictures/Wallpapers/* 2>/dev/null | head -n1)"
fi

LOCK_CONF="$DOTFILES_DIR/local/lock"
LOCK_ARGS=""
if [ -r "$LOCK_CONF" ]; then
    LOCK_ARGS="--config $LOCK_CONF"
fi

if [ -n "$image" ] && [ -f "$image" ]; then
    # The generated config contains only validated swaylock options.
    if [ -n "$LOCK_ARGS" ]; then
        exec swaylock --daemonize --config "$LOCK_CONF" --image "$image" --scaling fill
    fi
    exec swaylock --daemonize --image "$image" --scaling fill
else
    if [ -n "$LOCK_ARGS" ]; then exec swaylock --daemonize --config "$LOCK_CONF"; fi
    exec swaylock --daemonize
fi
