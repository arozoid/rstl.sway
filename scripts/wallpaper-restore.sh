#!/bin/sh
# Start awww-daemon and apply the configured wallpaper.
#
# The wallpaper path is read from ${WALLPAPER_CONF} (default
# ~/.config/rstl.sway/wallpaper), a plain text file holding one path.
# If that file is missing or points to a file that does not exist, the
# previously cached wallpaper is restored instead (awww restore).

WALLPAPER_CONF="${WALLPAPER_CONF:-$HOME/.config/rstl.sway/wallpaper}"

# wait until the compositor is actually up (wayland socket present)
while [ -z "${WAYLAND_DISPLAY:-}" ] ||
      [ ! -S "${XDG_RUNTIME_DIR:-/tmp}/${WAYLAND_DISPLAY:-}" ]; do
    sleep 0.2
done

# fresh daemon so awww-daemon always matches the current sway instance
pkill -f awww-daemon 2>/dev/null || true
awww-daemon &

sleep 0.5

wallpaper=""
if [ -r "$WALLPAPER_CONF" ]; then
    wallpaper="$(head -n1 "$WALLPAPER_CONF")"
fi

# expand a leading ~ to $HOME
: "${wallpaper:=}"
if [ "${wallpaper#\~}" != "$wallpaper" ]; then
    wallpaper="$HOME${wallpaper#\~}"
fi

if [ -n "$wallpaper" ] && [ -f "$wallpaper" ]; then
    awww img "$wallpaper"
else
    # fall back to whatever was cached last (a no-op on the first run)
    awww restore 2>/dev/null || true
fi
