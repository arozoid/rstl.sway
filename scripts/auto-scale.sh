#!/usr/bin/env bash

wlr-randr | awk '
/^[A-Za-z0-9-]+ / {
    out=$1
    width=0
}

/Physical size:/ {
    split($3, s, "x")
    w=s[1]
    h=s[2]
    diag=sqrt(w*w+h*h)/25.4
}

/^[[:space:]]+[0-9]+x[0-9]+/ && /\(.*current.*\)/ {
    split($1, r, "x")
    width=r[1]

    base = (diag < 20) ? 2 : 1.5
    scale = base * (width / 2560)

    printf "setting %s: %.1f\" %dpx -> scale %.2f\n", out, diag, width, scale
    system("swaymsg output " out " scale " scale " >/dev/null")
}'
