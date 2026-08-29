#!/bin/sh

# Hide yambar while a fullscreen window is on a *visible* workspace, show it
# again otherwise. Handles fullscreen toggles as well as workspace switches:
# fullscreen windows on non-visible workspaces are ignored.

YAMBAR_SRC="${XDG_CONFIG_HOME:-$HOME/.config}/rstl.sway/yambar/config.yml"
# auto-scale.sh renders a DPI-sized copy at startup; fall back to the source
RENDERED_CFG="${XDG_CACHE_HOME:-$HOME/.cache}/rstl.sway/yambar-config.yml"
YAMBAR_CFG="$RENDERED_CFG"
[ -f "$YAMBAR_CFG" ] || YAMBAR_CFG="$YAMBAR_SRC"

is_fullscreen=0
yambar_pid=""

start_yambar() {
    if [ -n "$yambar_pid" ] && kill -0 "$yambar_pid" 2>/dev/null; then
        return
    fi
    # adopt an orphaned instance if one exists, else spawn our own
    yambar_pid=$(pgrep -x yambar | head -n1)
    if [ -z "$yambar_pid" ]; then
        yambar -c "$YAMBAR_CFG" &
        disown
        yambar_pid=$!
    fi
}

stop_yambar() {
    [ -n "$yambar_pid" ] || return
    kill "$yambar_pid" 2>/dev/null
    # wait for it to die so a following start can't race the teardown
    i=1
    while [ "$i" -le 50 ]; do
        kill -0 "$yambar_pid" 2>/dev/null || break
        sleep 0.02
        i=$((i + 1))
    done
    yambar_pid=""
}

# exit 0 if any visible workspace currently has a fullscreen window.
# note: workspace nodes themselves always report fullscreen_mode == 1
# (i3 compat quirk), so only con/floating_con nodes count.
check_fullscreen() {
    vis=$(swaymsg -t get_workspaces | jq -c '[.[] | select(.visible) | .name]') || return 1
    [ "$vis" != "[]" ] || return 1
    swaymsg -t get_tree | jq -e --argjson vis "$vis" '
        any(.. | objects
            | select(.type == "workspace" and (.name | IN($vis[])));
            any(.. | objects;
                (.type == "con" or .type == "floating_con") and .fullscreen_mode == 1))
    ' >/dev/null
}

# adopt or spawn according to current state (e.g. reload while already fullscreen)
start_yambar
if check_fullscreen; then
    is_fullscreen=1
    stop_yambar
fi

# subscribe to window/workspace events and react until the pipe closes
swaymsg -t subscribe -m '["window", "workspace"]' | while read -r _event; do
    if check_fullscreen; then fs=1; else fs=0; fi

    if [ "$fs" -eq 1 ] && [ "$is_fullscreen" -eq 0 ]; then
        is_fullscreen=1
        stop_yambar
    elif [ "$fs" -eq 0 ] && [ "$is_fullscreen" -eq 1 ]; then
        is_fullscreen=0
        start_yambar
    fi
done
