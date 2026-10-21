#!/bin/sh
# Control the sov (sway overview) overlay.
#
# sov reads commands from a FIFO: 0 hide, 1 show, 2 toggle, 3 quit. Keeping a
# single daemon around means workspace keybindings stay instant instead of
# spawning a process on every keypress.

set -u

pipe="${XDG_RUNTIME_DIR:-/tmp}/sovpipe"

case "${1:-toggle}" in
  daemon)
    command -v sov >/dev/null 2>&1 || exit 0
    rm -f "$pipe"
    mkfifo "$pipe" || exit 1
    tail -f "$pipe" | sov -t 500
    ;;
  show)
    [ -p "$pipe" ] && printf '1\n' > "$pipe"
    ;;
  hide)
    [ -p "$pipe" ] && printf '0\n' > "$pipe"
    ;;
  toggle)
    [ -p "$pipe" ] && printf '2\n' > "$pipe"
    ;;
  quit)
    [ -p "$pipe" ] && printf '3\n' > "$pipe"
    ;;
  *)
    printf 'usage: %s {daemon|show|hide|toggle|quit}\n' "$0" >&2
    exit 2
    ;;
esac
