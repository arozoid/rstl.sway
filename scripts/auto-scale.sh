#!/usr/bin/env bash

# ============================================================
# rstl.sway auto scaling
#
# output scale:
#   >= 20"  -> base 1.5
#   <  20"  -> base 2.0
#
# output scale is based on horizontal resolution.
#
# yambar:
#   scales directly with vertical resolution.
#   1440p -> 36px bar / 24px font
#
# cursor:
#   scales at half the rate of the bar.
# ============================================================

REF_WIDTH=2560
REF_HEIGHT=1440

BAR_HEIGHT=36
BAR_FONT=24

CURSOR_SIZE=20
CURSOR_THEME="GoogleDot-Black"

DOTFILES_DIR="$HOME/.config/rstl.sway"
YAMBAR_SRC="$DOTFILES_DIR/yambar/config.yml"
YAMBAR_OUT="${XDG_CACHE_HOME:-$HOME/.cache}/rstl.sway/yambar-config.yml"


# ============================================================
# helpers
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


# ============================================================
# physical monitor sizes
#
# OUTPUT_DIAG[DP-1] = 31.5
# ============================================================

declare -A OUTPUT_DIAG

current_output=""

while IFS= read -r line; do
    case "$line" in
        [![:space:]]*)
            current_output=${line%% *}
            ;;

        *"Physical size:"*)
            ps=${line##*: }

            ps_w=${ps%%x*}
            rest=${ps#*x}
            ps_h=${rest%% *}

            OUTPUT_DIAG["$current_output"]=$(
                calc "sqrt($ps_w*$ps_w+$ps_h*$ps_h)/25.4"
            )
            ;;
    esac
done < <(wlr-randr)


# ============================================================
# debug physical sizes
# ============================================================

for output in "${!OUTPUT_DIAG[@]}"; do
    printf \
        'detected physical size: %s -> %.1f"\n' \
        "$output" \
        "${OUTPUT_DIAG[$output]}"
done


# ============================================================
# read current resolutions from sway
# ============================================================

while IFS=$'\t' read -r cur_out cur_width cur_height; do
    [[ -n "$cur_out" ]] || continue

    cur_diag=${OUTPUT_DIAG["$cur_out"]:-0}

    printf \
        'detected output: %s -> %sx%s, %.1f"\n' \
        "$cur_out" \
        "$cur_width" \
        "$cur_height" \
        "$cur_diag"

    if [[ -z "$cur_diag" || "$cur_diag" == "0" ]]; then
        echo "auto-scale: no physical size found for $cur_out" >&2
        continue
    fi

    if [[ "$(calc "$cur_diag < 20")" -eq 1 ]]; then
        base=2
    else
        base=1.5
    fi

    scale=$(calc "$base * $cur_width / $REF_WIDTH")

    printf \
        'setting %s: %.1f" %dx%d -> scale %.2f\n' \
        "$cur_out" \
        "$cur_diag" \
        "$cur_width" \
        "$cur_height" \
        "$scale"

    swaymsg output "$cur_out" scale "$scale"

    if (( cur_height > max_height )); then
        max_height=$cur_height
    fi

done < <(
    swaymsg -t get_outputs -r |
    jq -r '
        .[] |
        [
            .name,
            .current_mode.width,
            .current_mode.height
        ] |
        @tsv
    '
)
# ============================================================
# fallback
# ============================================================

if (( max_height <= 0 )); then
    echo \
        "auto-scale: could not read display height, keeping reference sizing" \
        >&2

    max_height=$REF_HEIGHT
fi


# ============================================================
# yambar scaling
#
# directly proportional to vertical resolution
# ============================================================

bar_height=$(round \
    "$(calc "$BAR_HEIGHT * $max_height / $REF_HEIGHT")")

bar_font=$(round \
    "$(calc "$BAR_FONT * $max_height / $REF_HEIGHT")")


# ============================================================
# cursor scaling
#
# half as aggressive as bar scaling
# ============================================================

cursor_size=$(round \
    "$(calc "$CURSOR_SIZE * (1 + 0.5 * ($max_height / $REF_HEIGHT - 1))")")


printf \
    'ui sizing: height %dpx -> bar %dpx, font %dpx, cursor %dpx\n' \
    "$max_height" \
    "$bar_height" \
    "$bar_font" \
    "$cursor_size"


# ============================================================
# render yambar config
# ============================================================

if [[ -f "$YAMBAR_SRC" ]]; then
    mkdir -p "${YAMBAR_OUT%/*}"

    sed -E \
        -e "s/^([[:space:]]*height:[[:space:]]*)[0-9]+/\1$bar_height/" \
        -e "s/pixelsize=[0-9]+/pixelsize=$bar_font/" \
        "$YAMBAR_SRC" \
        > "${YAMBAR_OUT}.new" \
        && mv "${YAMBAR_OUT}.new" "$YAMBAR_OUT"
else
    echo \
        "auto-scale: missing $YAMBAR_SRC, skipping bar render" \
        >&2
fi


# ============================================================
# cursor
# ============================================================

swaymsg seat seat0 xcursor_theme \
    "$CURSOR_THEME" \
    "$cursor_size" \
    >/dev/null

dbus-update-activation-environment \
    XCURSOR_THEME="$CURSOR_THEME" \
    XCURSOR_SIZE="$cursor_size" \
    2>/dev/null || true


# ============================================================
# restart yambar
# ============================================================

if pgrep -x yambar >/dev/null 2>&1; then
    killall -q yambar yambar-fullscreen.sh 2>/dev/null

    sleep 0.2

    setsid \
        "$DOTFILES_DIR/scripts/yambar-fullscreen.sh" \
        >/dev/null 2>&1 &
fi
