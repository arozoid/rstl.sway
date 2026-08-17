#!/usr/bin/env bash
# rstl.sway power menu — wlogout-style 3x2 grid reimplemented in rofi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
icon_dir="$repo_root/assets/images"
theme="$script_dir/rstl-powermenu.rasi"

opts=(
    "lock\0icon\x1f$icon_dir/lock.png"
    "hibernate\0icon\x1f$icon_dir/hibernate.png"
    "logout\0icon\x1f$icon_dir/logout.png"
    "shutdown\0icon\x1f$icon_dir/shutdown.png"
    "suspend\0icon\x1f$icon_dir/suspend.png"
    "reboot\0icon\x1f$icon_dir/reboot.png"
)

chosen="$(printf '%b\n' "${opts[@]}" | rofi -dmenu -theme "$theme" -i)"

case "$chosen" in
    lock)      $repo_root/scripts/lock.sh ;;
    hibernate) systemctl hibernate ;;
    logout)    loginctl terminate-user "$USER" ;;
    shutdown)  systemctl poweroff ;;
    suspend)   systemctl suspend ;;
    reboot)    systemctl reboot ;;
esac
