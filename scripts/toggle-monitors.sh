#!/bin/sh

# ============================================================
# rstl.sway: toggle ALL outputs off, then back on (win+shift+o)
#
# Off: snapshot every active output (name, mode, scale, the
# workspace on it), then disable all of them. The session keeps
# running headless; input still works.
#
# On: re-enable exactly the recorded outputs, restore their
# mode and scale, and pull the recorded workspace back to its
# home output.
#
# State lives in $XDG_RUNTIME_DIR/rstl.sway so it is cleared on
# logout; a stale press can never restore ghost outputs.
# ============================================================

set -u

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/rstl.sway"
STATE_FILE="$STATE_DIR/monitors-toggle.tsv"

# ---------- off: snapshot + disable everything ----------
off() {
    mkdir -p "$STATE_DIR"
    snap="$STATE_DIR/.monitors-toggle.snap"

    swaymsg -t get_outputs -r 2>/dev/null | jq -r '
        .[] |
        select(.active) |
        [
            .name,
            "\(.current_mode.width)x\(.current_mode.height)",
            (.scale | tostring),
            (.current_workspace // "")
        ] |
        @tsv
    ' > "$snap"

    # nothing active - nothing to toggle
    if [ ! -s "$snap" ]; then
        rm -f "$snap" "$STATE_FILE"
        exit 0
    fi

    while IFS="$(printf '\t')" read -r out _mode _scale _ws; do
        case "$out" in
            ""|*[!a-zA-Z0-9_-]*) continue ;;
        esac
        swaymsg output "$out" disable >/dev/null 2>&1 || true
    done < "$snap"

    mv "$snap" "$STATE_FILE"
    printf '%s\n' "rstl monitor toggle: all outputs off (win+shift+o to restore)"
}

# ---------- on: restore every recorded output ----------
on() {
    while IFS="$(printf '\t')" read -r out mode scale ws; do
        case "$out" in
            ""|*[!a-zA-Z0-9_-]*) continue ;;
        esac

        swaymsg output "$out" enable >/dev/null 2>&1 || true
        [ -n "$mode" ]  && swaymsg output "$out" mode "$mode" >/dev/null 2>&1 || true
        [ -n "$scale" ] && swaymsg output "$out" scale "$scale" >/dev/null 2>&1 || true
        if [ -n "$ws" ]; then
            # pull the previously-resident workspace back to this output
            swaymsg workspace "$ws" output "$out" >/dev/null 2>&1 || true
        fi
    done < "$STATE_FILE"

    rm -f "$STATE_FILE"
}

if [ -f "$STATE_FILE" ]; then
    on
else
    off
fi