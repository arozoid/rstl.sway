#!/bin/sh

today=$(date +%-d)

printf '\n'

cal -w | awk -v today="$today" '
BEGIN {
    # waybar palette
    month = "\033[38;2;150;170;135m"
    week  = "\033[38;2;88;129;87m"
    head  = "\033[38;2;221;184;146m"

    # date colors
    green = "\033[38;2;163;177;138m"
    white = "\033[38;2;233;236;239m"

    # today
    now   = "\033[1;38;2;163;177;138m"

    reset = "\033[0m"
}

NR == 1 {
    printf " %s%s%s\n", month, $0, reset
    next
}

NR == 2 {
    printf " %s%s%s\n", head, $0, reset
    next
}

{
    printf " %s%s%s", week, substr($0, 1, 3), reset

    col = 1

    for (pos = 4; pos <= length($0); pos += 3) {
        cell = substr($0, pos, 3)
        num = cell

        gsub(/^ +/, "", num)
        gsub(/ +$/, "", num)

        if (num == "") {
            printf "%s", cell
        } else {
            if (col <= 3 || col >= 6)
                color = green
            else
                color = white

            if (num == today)
                color = now

            printf "%s%s%s", color, cell, reset
        }

        col++
    }

    printf "\n"
}' | sed 's/^/ /'
