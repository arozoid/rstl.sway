#!/usr/bin/env sh
# ===============================================
# simple foot --server kill script for rstl.sway
# ===============================================
if ! pgrep -xf "footclient" >/dev/null; then
	pkill -xf "foot --server"
fi
