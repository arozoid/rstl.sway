#!/bin/bash

# Battery charge reminder. Single-shot: a scheduler (systemd user timer
# batt.timer, 10s) invokes it repeatedly. Throttle state survives across
# invocations via a state file, so no long-running while-loop is needed.

LOW=40
HIGH=80
INTERVAL=60

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/mango"
state_file="$state_dir/batt.state"

last_low=0
last_high=0
if [ -f "$state_file" ]; then
    read -r last_low last_high < "$state_file"
fi

capacity=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null) || exit 0
status=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null) || exit 0

now=$(date +%s)

# Low battery reminder
if [ "$capacity" -le "$LOW" ] && [ "$status" = "Discharging" ]; then
    if (( now - last_low >= INTERVAL )); then
        notify-send "Plug in Charger!" "Battery is at ${capacity}%"
        paplay /usr/share/sounds/freedesktop/stereo/suspend-error.oga
        last_low=$now
    fi
else
    last_low=0
fi

# High battery reminder
if [ "$capacity" -ge "$HIGH" ] && [ "$status" = "Charging" ]; then
    if (( now - last_high >= INTERVAL )); then
        notify-send "Unplug Charger!" "Battery reached ${capacity}%"
        paplay /usr/share/sounds/freedesktop/stereo/suspend-error.oga
        last_high=$now
    fi
else
    last_high=0
fi

mkdir -p "$state_dir"
printf '%s %s\n' "$last_low" "$last_high" > "$state_file"
