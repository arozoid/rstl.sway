#!/usr/bin/env sh
if ! pgrep -x foot >/dev/null; then
    foot --server >/dev/null 2>&1 &
fi
exec footclient "$@"
