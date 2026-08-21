#!/bin/bash

# Hide yambar when any window is fullscreen, show it again when none are.

YAMBAR_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/rstl.sway/yambar/config.yml"

is_fullscreen=0

yambar -c "$YAMBAR_CFG" &
disown

while read -r event; do
    fs=0
    change=$(echo "$event" | jq -r '.change')
    if [ "$change" = "fullscreen_mode" ]; then
        [ "$(echo "$event" | jq -r '.container.fullscreen_mode')" -eq 1 ] && fs=1
    else
        swaymsg -t get_tree | jq -e '
            [.. | objects | select(.type == "con" and .fullscreen_mode == 1)] | length > 0
        ' >/dev/null 2>&1 && fs=1
    fi

    if [ "$fs" -eq 1 ] && [ "$is_fullscreen" -eq 0 ]; then
        is_fullscreen=1
        pkill -x yambar 2>/dev/null
    elif [ "$fs" -eq 0 ] && [ "$is_fullscreen" -eq 1 ]; then
        is_fullscreen=0
        yambar -c "$YAMBAR_CFG" &
        disown
    fi
done < <(swaymsg -t subscribe -m '["window", "workspace"]')
