#!/usr/bin/env bash

# ============================================================
# rstl.sway auto scaling
# ============================================================

REF_HEIGHT=1440

CURSOR_THEME="GoogleDot-Black"

SCALE_D1=232.2
SCALE_V1=2.0
SCALE_D2=91.9
SCALE_V2=1.5

TARGET_BAR_MM=7
TARGET_FONT_MM=5
TARGET_CURSOR_MM=5

DOTFILES_DIR="$HOME/.config/rstl.sway"
YAMBAR_SRC="$DOTFILES_DIR/yambar/config.yml"
YAMBAR_OUT="${XDG_CACHE_HOME:-$HOME/.cache}/rstl.sway/yambar-config.yml"

# ============================================================
# pure helpers
# ============================================================

calc() {
    awk "BEGIN { print ($1) }"
}

round() {
    awk -v n="$1" '
        BEGIN {
            s = n < 0 ? -1 : 1
            printf "%d", s * int(s * n + 0.5)
        }
    '
}

diag_from_size() {
    calc "sqrt($1*$1+$2*$2)/25.4"
}

dpi_from_width() {
    calc "$1 / ($2 / 25.4)"
}

scale_from_dpi() {
    calc "$SCALE_V1 + ($SCALE_V2 - $SCALE_V1) * ($1 - $SCALE_D1) / ($SCALE_D2 - $SCALE_D1)"
}

physical_px() {
    round "$(calc "$1 * $2 / ($3 * $4)")"
}

compute_output_settings() {
    local width=$1 height=$2 phys_w=$3 phys_h=$4

    if (( phys_w > 0 && phys_h > 0 )); then
        local dpi scale
        dpi=$(dpi_from_width "$width" "$phys_w")
        scale=$(scale_from_dpi "$dpi")

        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$scale" \
            "$(physical_px "$TARGET_BAR_MM" "$height" "$scale" "$phys_h")" \
            "$(physical_px "$TARGET_FONT_MM" "$height" "$scale" "$phys_h")" \
            "$(physical_px "$TARGET_CURSOR_MM" "$height" "$scale" "$phys_h")" \
            "dpi $(printf '%.0f' "$dpi")"
    else
        printf '1\t34\t25\t20\tproportional\n'
    fi
}

# ============================================================
# read display information (dishonest)
# ============================================================

read_physical_displays() {
    wlr-randr | awk '
        /^[^[:space:]]/ { out=$1 }
        /Physical size:/ {
            split($3,a,"x")
            printf "%s\t%s\t%s\n", out, a[1], a[2]
        }
    '
}

read_current_outputs() {
    swaymsg -t get_outputs -r |
    jq -r '.[] | [.name,.current_mode.width,.current_mode.height] | @tsv'
}

# ============================================================
# apply settings (dishonest)
# ============================================================

apply_output_scale() {
    swaymsg output "$1" scale "$2" >/dev/null
}

render_yambar() {
    local bar=$1 font=$2

    [[ -f "$YAMBAR_SRC" ]] || {
        echo "auto-scale: missing $YAMBAR_SRC" >&2
        return
    }

    mkdir -p "${YAMBAR_OUT%/*}"

    sed -E \
        -e "s/^([[:space:]]*height:[[:space:]]*)[0-9]+/\1$bar/" \
        -e "s/pixelsize=[0-9]+/pixelsize=$font/" \
        "$YAMBAR_SRC" > "${YAMBAR_OUT}.new"

    mv "${YAMBAR_OUT}.new" "$YAMBAR_OUT"
}

apply_cursor() {
    local size=$1

    swaymsg seat seat0 xcursor_theme "$CURSOR_THEME" "$size" >/dev/null

    dbus-update-activation-environment \
        XCURSOR_THEME="$CURSOR_THEME" \
        XCURSOR_SIZE="$size" \
        2>/dev/null || true
}

restart_yambar() {
    pgrep -x yambar >/dev/null 2>&1 || return

    killall -q yambar yambar-fullscreen.sh 2>/dev/null
    sleep 0.2

    setsid "$DOTFILES_DIR/scripts/yambar-fullscreen.sh" \
        >/dev/null 2>&1 &
}

# ============================================================
# main
# ============================================================

main() {
    declare -A PHYS_W PHYS_H DIAG

    while IFS=$'\t' read -r out w h; do
        PHYS_W["$out"]=$w
        PHYS_H["$out"]=$h
        DIAG["$out"]=$(diag_from_size "$w" "$h")

        printf 'detected physical size: %s -> %.1f" (%smm high)\n' \
            "$out" "${DIAG[$out]}" "$h"
    done < <(read_physical_displays)

    local max_height=0
    local bar=0 font=0 cursor=0

    while IFS=$'\t' read -r out width height; do
        local pw=${PHYS_W[$out]:-0}
        local ph=${PHYS_H[$out]:-0}
        local diag=${DIAG[$out]:-0}

        printf 'detected output: %s -> %sx%s, %.1f" (%sx%smm)\n' \
            "$out" "$width" "$height" "$diag" "$pw" "$ph"

        IFS=$'\t' read -r scale b f c key \
            <<<"$(compute_output_settings "$width" "$height" "$pw" "$ph")"

        printf 'setting %s: %s %dx%d -> scale %.2f, bar %dpx, font %dpx, cursor %dpx\n' \
            "$out" "$key" "$width" "$height" "$scale" "$b" "$f" "$c"

        apply_output_scale "$out" "$scale"

        (( b > bar )) && bar=$b
        (( f > font )) && font=$f
        (( c > cursor )) && cursor=$c
        (( height > max_height )) && max_height=$height
    done < <(read_current_outputs)

    (( max_height > 0 )) || max_height=$REF_HEIGHT

    printf 'ui sizing: height %dpx -> bar %dpx, font %dpx, cursor %dpx\n' \
        "$max_height" "$bar" "$font" "$cursor"

    render_yambar "$bar" "$font"
    apply_cursor "$cursor"
    restart_yambar
}

main "$@"
