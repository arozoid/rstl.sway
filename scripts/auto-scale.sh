#!/usr/bin/env bash

# ============================================================
# rstl.sway auto scaling
#
# Every output's scale, bar, font and cursor are sized by
# interpolating (linearly) between two calibrated plot points,
# keyed by the panel's PHYSICAL HEIGHT in mm (more reliable than
# diagonal). Values extrapolate linearly below/above the anchors.
#
# anchor                     height    scale  bar  font  cursor
# 12.5" 16:9 1440p laptop    155.7mm    2.0    34   25     20
# 32"   16:9 1440p monitor   398.5mm    1.5    34   25     20
#
# scale slides 2.0 -> 1.5 as panels get taller; bar/font/cursor are
# equal at both anchors, so they stay constant across all sizes
# (the laptop bar matches the monitor's).
#
# If physical height is unavailable, falls back to the same anchors
# expressed as diagonal in inches (12.5"/32"), then to
# proportional-to-width scale / proportional-to-resolution sizes.
# ============================================================

REF_WIDTH=2560
REF_HEIGHT=1440

CURSOR_THEME="GoogleDot-Black"

# fallback values (used only when physical size is unknown)
BAR_HEIGHT=34
BAR_FONT=25
CURSOR_SIZE=20

# --- anchor plot points, keyed by physical height in mm ---
SCALE_ANCHOR_X1=155.7; SCALE_ANCHOR_V1=2.0
SCALE_ANCHOR_X2=398.5; SCALE_ANCHOR_V2=1.5

BAR_ANCHOR_X1=155.7;  BAR_ANCHOR_V1=34
BAR_ANCHOR_X2=398.5;  BAR_ANCHOR_V2=34

FONT_ANCHOR_X1=155.7; FONT_ANCHOR_V1=25
FONT_ANCHOR_X2=398.5; FONT_ANCHOR_V2=25

CURSOR_ANCHOR_X1=155.7; CURSOR_ANCHOR_V1=20
CURSOR_ANCHOR_X2=398.5; CURSOR_ANCHOR_V2=20

# fallback anchors keyed by diagonal in inches (used when physical
# height is unknown but diagonal was computed; values shared with the
# mm anchors above via *_ANCHOR_V1/V2)
SCALE_ANCHOR_D1=12.5
SCALE_ANCHOR_D2=32.0

BAR_ANCHOR_D1=12.5
BAR_ANCHOR_D2=32.0

FONT_ANCHOR_D1=12.5
FONT_ANCHOR_D2=32.0

CURSOR_ANCHOR_D1=12.5
CURSOR_ANCHOR_D2=32.0

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

    # scale / bar / font / cursor are linear in PHYSICAL HEIGHT (mm)
    # between the calibrated anchor points; values extrapolate beyond.
    # Fall back to the same anchors keyed by diagonal (inches) when the
    # physical height is unknown, then to proportional width scaling.
    cur_phys_h=${OUTPUT_PHYS_H["$cur_out"]:-0}
    if (( cur_phys_h > 0 )); then
        x=$cur_phys_h
        sa1=$SCALE_ANCHOR_X1;   sa2=$SCALE_ANCHOR_X2
        ba1=$BAR_ANCHOR_X1;     ba2=$BAR_ANCHOR_X2
        fa1=$FONT_ANCHOR_X1;    fa2=$FONT_ANCHOR_X2
        ca1=$CURSOR_ANCHOR_X1;  ca2=$CURSOR_ANCHOR_X2
        sizing_key="height ${cur_phys_h}mm"
    elif (( $(calc "$cur_diag > 0") == 1 )); then
        x=$cur_diag
        sa1=$SCALE_ANCHOR_D1;   sa2=$SCALE_ANCHOR_D2
        ba1=$BAR_ANCHOR_D1;     ba2=$BAR_ANCHOR_D2
        fa1=$FONT_ANCHOR_D1;    fa2=$FONT_ANCHOR_D2
        ca1=$CURSOR_ANCHOR_D1;  ca2=$CURSOR_ANCHOR_D2
        sizing_key="diag ${cur_diag}\""
    else
        scale=$(calc "$cur_width / $REF_WIDTH")
        sizing_key="proportional width"
    fi

    if [[ -n "${sizing_key:-}" && "$sizing_key" != "proportional width" ]]; then
        scale=$(calc "$(lerp "$x" "$sa1" "$SCALE_ANCHOR_V1" "$sa2" "$SCALE_ANCHOR_V2")")
        cur_bar=$(round "$(calc "$(lerp "$x" "$ba1" "$BAR_ANCHOR_V1" "$ba2" "$BAR_ANCHOR_V2")")")
        cur_fnt=$(round "$(calc "$(lerp "$x" "$fa1" "$FONT_ANCHOR_V1" "$fa2" "$FONT_ANCHOR_V2")")")
        cur_cur=$(round "$(calc "$(lerp "$x" "$ca1" "$CURSOR_ANCHOR_V1" "$ca2" "$CURSOR_ANCHOR_V2")")")

        (( cur_bar > bar_height )) && bar_height=$cur_bar
        (( cur_fnt > bar_font ))   && bar_font=$cur_fnt
        (( cur_cur > cursor_size )) && cursor_size=$cur_cur
    fi

    printf \
        'setting %s: %s %dx%d -> scale %.2f, bar %dpx, font %dpx, cursor %dpx\n' \
        "$cur_out" \
        "$sizing_key" \
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
