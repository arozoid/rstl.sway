#!/usr/bin/env sh
if ! pgrep -xf "foot --server" >/dev/null; then
    foot --server >/dev/null 2>&1 &
    sleep 0.05
fi
exec footclient "$@"
