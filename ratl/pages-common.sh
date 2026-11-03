#!/bin/sh
# Shared implementations for rstl-tune's individual settings pages.
# Source this file from a category launcher in ratl/pages/.
set -u
DOTFILES_DIR="${RSTL_SWAY_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/rstl.sway}"
. "$DOTFILES_DIR/ratl/lib.sh"

valid_line() {
    case "$1" in
        ''|*[![:print:]]*|*'`'*|*'$('*|*';'*|*'#'*) return 1 ;;
        *) return 0 ;;
    esac
}

brightness_page() {
    settings_need_tty
    settings_have brightnessctl || { ratl_message "Brightness" "Install brightnessctl to control display brightness."; return 1; }
    current=$(brightnessctl -m 2>/dev/null | awk -F, 'NR == 1 { gsub(/%/, "", $4); print $4 }')
    case "$current" in ''|*[!0-9]*) current=50 ;; esac
    [ "$current" -lt 1 ] && current=1
    [ "$current" -gt 100 ] && current=100
    dialog=$(jq -n --argjson value "$current" '{title:"Brightness",width:72,children:[{type:"label",text:"Set the active backlight level."},{type:"slider",id:"level",label:"Brightness (%)",min:1,max:100,step:1,value:$value}],buttons:[{label:"Apply",action:"submit",kind:"primary"},{label:"Cancel",action:"cancel"}]}')
    result=$(ratl_page "$dialog") || return 0
    value=$(printf '%s' "$result" | jq -r '.values.level // 50')
    case "$value" in ''|*[!0-9]*) return 1 ;; esac
    brightnessctl set "${value}%" >/dev/null 2>&1 || ratl_message "Brightness" "Could not set brightness. Check backlight permissions."
}

peripherals_page() {
    settings_need_tty
    options=$(jq -n '[{label:"Bluetooth",value:"bluetooth"},{label:"Wi-Fi",value:"wifi"},{label:"All radio devices",value:"all"}]')
    result=$(ratl_select "Peripherals" "Toggle radio" "$options" 0) || return 0
    choice=$(printf '%s' "$result" | jq -r '.values.choice // empty')
    case "$choice" in
        bluetooth) if command -v bluetoothctl >/dev/null 2>&1; then if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then bluetoothctl power off; else bluetoothctl power on; fi; elif command -v rfkill >/dev/null 2>&1; then if rfkill list bluetooth | grep -q 'Soft blocked: no'; then rfkill block bluetooth; else rfkill unblock bluetooth; fi; else ratl_message "Peripherals" "Bluetooth tools are not installed."; fi ;;
        wifi) if command -v nmcli >/dev/null 2>&1; then if nmcli -t -f WIFI radio 2>/dev/null | grep -q enabled; then nmcli radio wifi off; else nmcli radio wifi on; fi; elif command -v rfkill >/dev/null 2>&1; then if rfkill list wlan | grep -q 'Soft blocked: no'; then rfkill block wlan; else rfkill unblock wlan; fi; else ratl_message "Peripherals" "NetworkManager tools are not installed."; fi ;;
        all) command -v rfkill >/dev/null 2>&1 && { if rfkill list | grep -q 'Soft blocked: no'; then rfkill block all; else rfkill unblock all; fi; } || ratl_message "Peripherals" "rfkill is not installed." ;;
    esac
}

appearance_page() {
    settings_need_tty
    options=$(jq -n '[{label:"Choose wallpaper",value:"wallpaper"},{label:"Cursor theme",value:"cursor"}]')
    result=$(ratl_select "Appearance" "Setting" "$options" 0) || return 0
    choice=$(printf '%s' "$result" | jq -r '.values.choice // empty')
    [ "$choice" = wallpaper ] && "$DOTFILES_DIR/ratl/rstl-wallpaper" && return 0
    [ "$choice" = cursor ] || return 0
    themes=$(find /usr/share/icons "$HOME/.local/share/icons" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's#.*/##' | sort -u | jq -R -s 'split("\n")|map(select(length>0)|{label:.,value:.})')
    [ "$(printf '%s' "$themes" | jq 'length')" -gt 0 ] || themes='[{"label":"Notwaita-Gray","value":"Notwaita-Gray"}]'
    current="Notwaita-Gray"; size=25; cursor_file="$DOTFILES_DIR/sway/config.d/20-cursor.conf"
    [ ! -r "$RSTL_LOCAL_DIR/cursor.conf" ] || cursor_file="$RSTL_LOCAL_DIR/cursor.conf"
    current=$(sed -nE 's/^[^#]*xcursor_theme[[:space:]]+([^[:space:]]+).*/\1/p' "$cursor_file" | head -n1)
    size=$(sed -nE 's/^[^#]*xcursor_theme[[:space:]]+[^[:space:]]+[[:space:]]+([0-9]+).*/\1/p' "$cursor_file" | head -n1)
    [ -n "$current" ] || current=Notwaita-Gray; [ -n "$size" ] || size=25
    selected=$(printf '%s' "$themes" | jq --arg current "$current" 'map(.value)|index($current) // 0')
    dialog=$(jq -n --argjson options "$themes" --argjson selected "$selected" --argjson size "$size" '{title:"Cursor theme",width:72,children:[{type:"select",id:"theme",label:"Theme",options:$options,selected:$selected},{type:"slider",id:"size",label:"Size",min:8,max:96,step:2,value:$size}],buttons:[{label:"Apply",action:"submit",kind:"primary"},{label:"Cancel",action:"cancel"}]}')
    result=$(ratl_page "$dialog") || return 0
    theme=$(printf '%s' "$result" | jq -r '.values.theme // empty'); size=$(printf '%s' "$result" | jq -r '.values.size // 24')
    valid_line "$theme" || return 1
    case "$size" in ''|*[!0-9]*) return 1 ;; esac
    ensure_local_dir
    printf 'seat seat0 xcursor_theme %s %s\n' "$theme" "$size" > "$RSTL_LOCAL_DIR/cursor.conf"
    swaymsg "seat seat0 xcursor_theme $theme $size" >/dev/null 2>&1 || true
    swaymsg reload >/dev/null 2>&1 || true
}

apps_page() {
    settings_need_tty
    term="$DOTFILES_DIR/scripts/foot-smart.sh"; launcher="rofi -show drun"
    [ -r "$RSTL_LOCAL_DIR/default-apps.conf" ] && {
        term=$(sed -n 's/^set \$term //p' "$RSTL_LOCAL_DIR/default-apps.conf" | head -n1)
        launcher=$(sed -n 's/^set \$menu //p' "$RSTL_LOCAL_DIR/default-apps.conf" | head -n1)
    }
    dialog=$(jq -n --arg term "$term" --arg launcher "$launcher" '{title:"Default apps",width:84,children:[{type:"text",id:"term",label:"Terminal command",value:$term},{type:"text",id:"launcher",label:"Application launcher command",value:$launcher},{type:"label",text:"Sway defaults live in config.d/05-default-apps.conf; personal choices are kept in local/."}],buttons:[{label:"Apply",action:"submit",kind:"primary"},{label:"Cancel",action:"cancel"}]}')
    result=$(ratl_page "$dialog") || return 0
    term=$(printf '%s' "$result" | jq -r '.values.term // empty'); launcher=$(printf '%s' "$result" | jq -r '.values.launcher // empty')
    valid_line "$term" && valid_line "$launcher" || { ratl_message "Default apps" "Commands cannot be empty or contain shell control characters."; return 1; }
    ensure_local_dir
    printf 'set $term %s\nset $menu %s\n' "$term" "$launcher" > "$RSTL_LOCAL_DIR/default-apps.conf"
    swaymsg reload >/dev/null 2>&1 || true
}

autostart_page() {
    settings_need_tty
    ensure_local_dir
    state="$RSTL_LOCAL_DIR/autostart.conf"
    actions='[{"label":"Add a command","value":"add"}]'
    [ ! -s "$state" ] || actions='[{"label":"Add a command","value":"add"},{"label":"Remove a command","value":"remove"}]'
    action_result=$(ratl_select "Autostart" "Action" "$actions" 0) || return 0
    action=$(printf '%s' "$action_result" | jq -r '.values.choice // empty')
    if [ "$action" = remove ]; then
        options=$(awk '/^exec(_always)? --no-startup-id / { line=$0; sub(/^exec(_always)? --no-startup-id /, "", line); printf "%d\t%s\n", NR, line }' "$state" | jq -R 'split("\t") as $f | {label:$f[1],value:$f[0]}' | jq -s '.')
        result=$(ratl_select "Autostart" "Command to remove" "$options" 0) || return 0
        line_number=$(printf '%s' "$result" | jq -r '.values.choice // empty')
        case "$line_number" in ''|*[!0-9]*) return 0 ;; esac
        tmp="$state.tmp.$$"
        awk -v skip="$line_number" 'NR != skip { print }' "$state" > "$tmp" && mv -f "$tmp" "$state"
        swaymsg reload >/dev/null 2>&1 || true
        return 0
    fi
    dialog=$(jq -n '{title:"Autostart",width:84,children:[{type:"text",id:"command",label:"Command",placeholder:"example: blueman-applet"},{type:"checkbox",id:"always",label:"Restart it on every Sway reload",checked:false}],buttons:[{label:"Add",action:"submit",kind:"primary"},{label:"Cancel",action:"cancel"}]}')
    result=$(ratl_page "$dialog") || return 0
    command=$(printf '%s' "$result" | jq -r '.values.command // empty'); [ -n "$command" ] || return 0
    valid_line "$command" || { ratl_message "Autostart" "Command contains unsupported shell control characters."; return 1; }
    always=$(printf '%s' "$result" | jq -r '.values.always // false')
    if [ "$always" = true ]; then printf 'exec_always --no-startup-id %s\n' "$command" >> "$state"; else printf 'exec --no-startup-id %s\n' "$command" >> "$state"; fi
    swaymsg reload >/dev/null 2>&1 || true
    ratl_message "Autostart" "Command added. Remove its line from local/autostart.conf to stop it from starting."
}

services_page() {
    settings_need_tty
    manager=systemd
    [ -d /run/runit ] && manager=runit
    dialog=$(jq -n --arg manager "$manager" '{title:"Services",width:84,children:[{type:"label",text:("Detected service manager: " + $manager)},{type:"text",id:"service",label:"Service name",placeholder:"example: NetworkManager"},{type:"select",id:"action",label:"Action",options:[{label:"Enable and start",value:"enable"},{label:"Disable and stop",value:"disable"},{label:"Start now",value:"start"},{label:"Stop now",value:"stop"}],selected:0},{type:"label",text:"System services require administrator access."}],buttons:[{label:"Apply",action:"submit",kind:"primary"},{label:"Cancel",action:"cancel"}]}')
    result=$(ratl_page "$dialog") || return 0
    service=$(printf '%s' "$result" | jq -r '.values.service // empty'); action=$(printf '%s' "$result" | jq -r '.values.action // empty')
    case "$service" in ''|*[!A-Za-z0-9_.@-]*) ratl_message "Services" "Enter a valid service name."; return 1 ;; esac
    case "$action" in enable|disable|start|stop) ;; *) return 1 ;; esac
    if [ "$manager" = runit ]; then
        case "$action" in enable) run_sudo ln -sfn "/etc/sv/$service" "/etc/runit/runsvdir/default/$service" ;; disable) run_sudo rm -f "/etc/runit/runsvdir/default/$service" ;; start) run_sudo sv up "$service" ;; stop) run_sudo sv down "$service" ;; esac
    else
        case "$action" in enable) run_sudo systemctl enable --now "$service" ;; disable) run_sudo systemctl disable --now "$service" ;; start) run_sudo systemctl start "$service" ;; stop) run_sudo systemctl stop "$service" ;; esac
    fi
}

time_page() {
    settings_need_tty
    zone=$(readlink /etc/localtime 2>/dev/null | sed 's#^.*/zoneinfo/##'); [ -n "$zone" ] || zone=UTC
    format='%H:%M'; [ -r "$RSTL_LOCAL_DIR/clock-format" ] && format=$(cat "$RSTL_LOCAL_DIR/clock-format")
    dialog=$(jq -n --arg zone "$zone" --arg format "$format" '{title:"Time and clock",width:82,children:[{type:"text",id:"zone",label:"Time zone (area/location)",value:$zone},{type:"text",id:"format",label:"Panel clock format (strftime)",value:$format},{type:"label",text:"Examples: %H:%M · %a %d %b %H:%M"}],buttons:[{label:"Apply",action:"submit",kind:"primary"},{label:"Cancel",action:"cancel"}]}')
    result=$(ratl_page "$dialog") || return 0
    zone=$(printf '%s' "$result" | jq -r '.values.zone // empty'); format=$(printf '%s' "$result" | jq -r '.values.format // empty')
    case "$zone" in ''|*[!A-Za-z0-9_+/-]*|../*|*/../*) ratl_message "Time" "Enter a valid time zone such as Europe/London."; return 1 ;; esac
    [ -f "/usr/share/zoneinfo/$zone" ] || { ratl_message "Time" "That time zone is not installed."; return 1; }
    case "$format" in ''|*[!%A-Za-z0-9\ :./,_-]*) ratl_message "Time" "Use a plain strftime format such as %H:%M or %a %d %b %H:%M."; return 1 ;; esac
    run_sudo ln -sfn "/usr/share/zoneinfo/$zone" /etc/localtime || return 1
    printf '%s\n' "$zone" | run_sudo tee /etc/timezone >/dev/null
    ensure_local_dir; printf '%s\n' "$format" > "$RSTL_LOCAL_DIR/clock-format"
    "$DOTFILES_DIR/scripts/auto-scale.sh" >/dev/null 2>&1 || true
    swaymsg reload >/dev/null 2>&1 || true
}

notifications_page() {
    settings_need_tty
    timeout=8; [ -r "$RSTL_LOCAL_DIR/notification-timeout" ] && timeout=$(cat "$RSTL_LOCAL_DIR/notification-timeout")
    case "$timeout" in ''|*[!0-9]*) timeout=8 ;; esac
    dialog=$(jq -n --argjson timeout "$timeout" '{title:"Notifications",width:72,children:[{type:"slider",id:"timeout",label:"Dismiss after (seconds; 0 stays until dismissed)",min:0,max:60,step:1,value:$timeout}],buttons:[{label:"Apply",action:"submit",kind:"primary"},{label:"Cancel",action:"cancel"}]}')
    result=$(ratl_page "$dialog") || return 0
    timeout=$(printf '%s' "$result" | jq -r '.values.timeout // 8'); case "$timeout" in ''|*[!0-9]*) return 1 ;; esac
    ensure_local_dir; printf '%s\n' "$timeout" > "$RSTL_LOCAL_DIR/notification-timeout"
    mako_pid=$(pgrep -x mako 2>/dev/null || true); [ -z "$mako_pid" ] || kill $mako_pid 2>/dev/null || true
    nohup "$DOTFILES_DIR/scripts/start-mako.sh" >/dev/null 2>&1 &
}

lock_page() {
    settings_need_tty
    color=1b211d; clock=true
    if [ -r "$RSTL_LOCAL_DIR/lock-settings" ]; then
        color=$(sed -n 's/^color=//p' "$RSTL_LOCAL_DIR/lock-settings" | head -n1)
        clock=$(sed -n 's/^clock=//p' "$RSTL_LOCAL_DIR/lock-settings" | head -n1)
        [ -n "$color" ] || color=1b211d; [ -n "$clock" ] || clock=true
    fi
    dialog=$(jq -n --arg color "$color" --argjson clock "$clock" '{title:"Lock screen",width:76,children:[{type:"text",id:"color",label:"Background color (hex, without #)",value:$color},{type:"checkbox",id:"clock",label:"Show clock",checked:$clock}],buttons:[{label:"Apply",action:"submit",kind:"primary"},{label:"Cancel",action:"cancel"}]}')
    result=$(ratl_page "$dialog") || return 0
    color=$(printf '%s' "$result" | jq -r '.values.color // empty'); clock=$(printf '%s' "$result" | jq -r '.values.clock // false')
    case "$color" in [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]) ;; *) ratl_message "Lock screen" "Use six hexadecimal digits, for example 1b211d."; return 1 ;; esac
    ensure_local_dir
    printf 'color=%s\nclock=%s\n' "$color" "$clock" > "$RSTL_LOCAL_DIR/lock-settings"
    {
        printf 'color=%s\n' "$color"
        [ "$clock" = true ] && printf 'clock\n'
        printf 'indicator\n'
    } > "$RSTL_LOCAL_DIR/lock"
}

