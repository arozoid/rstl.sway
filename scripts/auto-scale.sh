#!/usr/bin/env bash

wlr-randr | awk '
/^[A-Za-z0-9-]+/ { out=$1 }

/^[[:space:]]*[0-9]+x[0-9]+/ && /\*/ {
    split($1, r, "x")
    px = r[1]
}

/Physical size:/ {
    w = $3; h = $4
    sub(/mm/, "", w)
    sub(/mm/, "", h)

    diagonal = sqrt(w*w + h*h) / 25.4

    # baseline scale for a 1440p display
    base = (diagonal < 20) ? 1.5 : 2

    # scale proportional to resolution (2560 is 1440p width)
    scale = base * (px / 2560)

    printf "setting %s: %.1f\" %dx -> scale %.2f\n", out, diagonal, px, scale
    system("swaymsg output " out " scale " scale " >/dev/null")
}'
