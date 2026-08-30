# Autostart the rstl.sway live environment on console login (tty1).
if [ -n "$BASH_VERSION" ] && [ "$(tty)" = "/dev/tty1" ] && [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    [ -x /usr/local/bin/rstl-live ] && exec /usr/local/bin/rstl-live
fi
