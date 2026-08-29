#!/bin/sh
# rstl.sway lock screen — swaylock with the current wallpaper as background.
#
# The wallpaper path is read from ${WALLPAPER_CONF} (default
# ~/.config/rstl.sway/wallpaper), a plain text file holding one path.
# If that file is missing or points to a missing file, the most recently
# modified wallpaper in ~/Pictures/Wallpapers is used instead.

WALLPAPER_CONF="${WALLPAPER_CONF:-$HOME/.config/rstl.sway/wallpaper}"

image=""
if [ -r "$WALLPAPER_CONF" ]; then
    image="$(head -n1 "$WALLPAPER_CONF")"
    [ "${image#\~}" != "$image" ] && image="$HOME${image#\~}"
fi

if [ -z "$image" ] || [ ! -f "$image" ]; then
    image="$(ls -t "$HOME"/Pictures/Wallpapers/* 2>/dev/null | head -n1)"
fi

if [ -n "$image" ] && [ -f "$image" ]; then
    exec swaylock --daemonize --image "$image" --scaling fill
else
    exec swaylock --daemonize
fi
