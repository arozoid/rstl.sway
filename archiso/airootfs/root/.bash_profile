# Boot the rstl.sway live medium straight into the rstl-inst installer TUI on
# tty1 (instead of a login manager or the sway desktop). The TUI's own menu
# offers "Try Live" (sway via /usr/local/bin/rstl-live), so sway stays one
# keystroke away.
if [ -n "$BASH_VERSION" ] && [ "$(tty)" = "/dev/tty1" ] && [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    if command -v rstl-inst >/dev/null 2>&1; then
        exec rstl-inst
    fi
    [ -x /usr/local/bin/rstl-live ] && exec /usr/local/bin/rstl-live
fi
