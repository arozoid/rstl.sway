#!/bin/sh
while ! pw-cli info 0 >/dev/null 2>&1; do
    sleep 0.3
done

sleep 0.3
pw-play ~/.config/rstl.sway/assets/sounds/chime.flac
