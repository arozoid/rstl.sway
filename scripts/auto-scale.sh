#!/usr/bin/env bash

# ============================================================
# rstl.sway auto scaling
#
# Every output is sized by interpolating (linearly) between two
# calibrated plot points given its physical diagonal (inches).
# Values extrapolate linearly below/above the anchor sizes too.
#
#   anchor            diag   scale  bar  font  cursor
#   12.5" 1440p laptop 12.5"   2.0    34   25     20
#   32"   1440p monitor 32"    1.5    34   25     20
#
# scale, bar, font and cursor are all linear in inch-size between
# the anchors and beyond. (Bar/font/cursor happen to be equal at both
# anchors, so they stay constant across all screen sizes.)
#
# When physical size is unknown, falls back to proportional-to-width
# for scale and proportional-to-resolution for bar/font/cursor.
# ============================================================

REF_WIDTH=2560
REF_HEIGHT=1440

CURSOR_THEME="GoogleDot-Black"

# fallback values (used only when physical size is unknown)
BAR_HEIGHT=34
BAR_FONT=25
CURSOR_SIZE=20

# --- anchor plot points: diag(in) -> (scale, bar, font, cursor) ---
SCALE_ANCHOR_D1=12.5; SCALE_ANCHOR_V1=2.0
SCALE_ANCHOR_D2=32.0; SCALE_ANCHOR_V2=1.5

BAR_ANCHOR_D1=12.5;  BAR_ANCHOR_V1=34
BAR_ANCHOR_D2=32.0;  BAR_ANCHOR_V2=34

FONT_ANCHOR_D1=12.5; FONT_ANCHOR_V1=25
FONT_ANCHOR_D2=32.0; FONT_ANCHOR_V2=25

CURSOR_ANCHOR_D1=12.5; CURSOR_ANCHOR_V1=20
CURSOR_ANCHOR_D2=32.0; CURSOR_ANCHOR_V2=20

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

# linear interpolation/extrapolation between (x1,y1) and (x2,y2)
lerp() {
    awk -v x="$1" -v x1="$2" -v y1="$3" -v x2="$4" -v y2="$5" \
        'BEGIN { print y1 + (y2 - y1) * (x - x1) / (x2 - x1) }'
}


# ============================================================
# physical monitor sizes
#
# OUTPUT_DIAG[DP-1] = 31.5
# ============================================================

declare -A OUTPUT_DIAG
declare -A OUTPUT_PHYS_H

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
            OUTPUT_PHYS_H["$current_output"]=$ps_h
            ;;
    esac
done < <(wlr-randr)


# ============================================================
# debug physical sizes
# ============================================================

for output in "${!OUTPUT_DIAG[@]}"; do
    printf \
        'detected physical size: %s -> %.1f" (%smm high)\n' \
        "$output" \
        "${OUTPUT_DIAG[$output]}" \
        "${OUTPUT_PHYS_H[$output]:-?}"
done


# ============================================================
# read current resolutions from sway
# ============================================================

max_height=0
bar_height=0
bar_font=0
cursor_size=0

while IFS=$'\t' read -r cur_out cur_width cur_height; do
    # skip empty / malformed lines (e.g. jq returning "[]")
    [[ "$cur_out" =~ ^[a-zA-Z0-9_-]+$ ]] || continue

    cur_diag=${OUTPUT_DIAG["$cur_out"]:-0}

    printf \
        'detected output: %s -> %sx%s, %.1f"\n' \
        "$cur_out" \
        "$cur_width" \
        "$cur_height" \
        "$cur_diag"

    if [[ -z "$cur_diag" || "$cur_diag" == "0" ]]; then
        echo "auto-scale: no physical size found for $cur_out" >&2
    fi

    # scale / bar / font / cursor are linear in screen diagonal (inches)
    # between the calibrated anchor points; values extrapolate beyond them.
    cur_phys_h=${OUTPUT_PHYS_H["$cur_out"]:-0}
    if (( cur_phys_h > 0 )) && (( $(calc "$cur_diag > 0") == 1 )); then
        scale=$(calc "$(lerp "$cur_diag" \
            "$SCALE_ANCHOR_D1" "$SCALE_ANCHOR_V1" \
            "$SCALE_ANCHOR_D2" "$SCALE_ANCHOR_V2")")

        cur_bar=$(round "$(calc "$(lerp "$cur_diag" \
            "$BAR_ANCHOR_D1" "$BAR_ANCHOR_V1" \
            "$BAR_ANCHOR_D2" "$BAR_ANCHOR_V2")")")
        cur_fnt=$(round "$(calc "$(lerp "$cur_diag" \
            "$FONT_ANCHOR_D1" "$FONT_ANCHOR_V1" \
            "$FONT_ANCHOR_D2" "$FONT_ANCHOR_V2")")")
        cur_cur=$(round "$(calc "$(lerp "$cur_diag" \
            "$CURSOR_ANCHOR_D1" "$CURSOR_ANCHOR_V1" \
            "$CURSOR_ANCHOR_D2" "$CURSOR_ANCHOR_V2")")")

        (( cur_bar > bar_height )) && bar_height=$cur_bar
        (( cur_fnt > bar_font ))   && bar_font=$cur_fnt
        (( cur_cur > cursor_size )) && cursor_size=$cur_cur
    else
        scale=$(calc "$cur_width / $REF_WIDTH")
    fi

    printf \
        'setting %s: %.1f" %dx%d -> scale %.2f, bar %dpx, font %dpx, cursor %dpx\n' \
        "$cur_out" \
        "$cur_diag" \
        "$cur_width" \
        "$cur_height" \
        "$scale" \
        "$cur_bar" \
        "$cur_fnt" \
        "$cur_cur"

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

# fall back to proportional sizing when physical dimensions are unknown
if (( bar_height <= 0 )); then
    bar_height=$(round "$(calc "$BAR_HEIGHT * $max_height / $REF_HEIGHT")")
fi
if (( bar_font <= 0 )); then
    bar_font=$(round "$(calc "$BAR_FONT * $max_height / $REF_HEIGHT")")
fi
if (( cursor_size <= 0 )); then
    cursor_size=$(round "$(calc "$CURSOR_SIZE * (1 + 0.5 * ($max_height / $REF_HEIGHT - 1))")")
fi


# ============================================================
# yambar / cursor sizing
#
# scale/bar/font/cursor interpolated from the anchor plot points
# per output above; falls back to proportional sizing when
# physical dimensions are unknown.
# ============================================================


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
