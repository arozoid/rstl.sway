#!/usr/bin/env sh

footclient "$@" && exit 0

foot --server >/dev/null 2>&1 &
sleep 0.1

exec footclient "$@"
