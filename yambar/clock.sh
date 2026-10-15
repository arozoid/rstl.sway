#!/bin/sh

while true; do
    hour=$(date +%-I)
    time=$(date +%H:%M)

    printf 'hour|int|%s\ntime|string|%s\n\n' "$hour" "$time"

    sleep 1
done
