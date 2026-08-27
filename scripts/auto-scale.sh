#!/usr/bin/env bash

# ============================================================
# rstl.sway auto scaling
#
# output scale:
#   computed from physical pixel density (DPI).
#   higher-DPI panels get higher scale.
#   falls back to proportional-to-width when physical size is unknown.
#
# yambar / cursor:
#   constant physical size across all displays:
#     config = target_mm * vertical_pixels_per_mm / scale
#
#   reference: 1440p 27" (336mm) at scale 1.5
#     -> bar 36px / font 24px / cursor 20px
#
#   falls back to proportional-to-resolution when
#   physical dimensions are unknown.
# ============================================================

REF_WIDTH=2560
REF_HEIGHT=1440
REF_DPI=163.3  # scale * dpi: 1.5 * (1440 * 25.4 / 336)

BAR_HEIGHT=36
BAR_FONT=27

CURSOR_SIZE=20
CURSOR_THEME="GoogleDot-Black"

# target physical sizes in mm, calibrated for
# 1440p 27" (336mm) at scale 1.5 -> bar 36px, font 24px, cursor 20px
#
# physical_height = config_px * scale * physical_height_mm / mode_height
TARGET_BAR_MM=7
TARGET_FONT_MM=5
TARGET_CURSOR_MM=4

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
declare -A OUTPUT_PHYS_H
declare -A OUTPUT_SCALE

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

        *"Scale:"*)
            scale_val=${line##*: }
            OUTPUT_SCALE["$current_output"]=$scale_val
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

    # recompute scale from physical DPI every run. trusting the current
    # wlr-randr value lets a stale/reset scale (e.g. 1.0 after a display
    # re-plug or sway restart) stick, which breaks DPI scaling.
    cur_phys_h=${OUTPUT_PHYS_H["$cur_out"]:-0}
    if (( cur_phys_h > 0 )); then
        phys_dpi=$(calc "$cur_height * 25.4 / $cur_phys_h")
        scale=$(calc "$REF_DPI / $phys_dpi")
    else
        scale=$(calc "$cur_width / $REF_WIDTH")
    fi

    printf \
        'setting %s: %.1f" %dx%d -> scale %.2f\n' \
        "$cur_out" \
        "$cur_diag" \
        "$cur_width" \
        "$cur_height" \
        "$scale"

    swaymsg output "$cur_out" scale "$scale"

    # per-output sizing for constant physical bar/cursor across displays.
    # large desktop panels (>20") look undersized at the notebook-calibrated
    # physical targets, so scale the bar and cursor up 2x on those.
    if (( cur_phys_h > 0 )); then
        vppmm=$(calc "$cur_height / $cur_phys_h")

        size_boost=$(calc "$cur_diag > 20 ? 2 : 1")

        cur_bar=$(round "$(calc "$size_boost * $TARGET_BAR_MM * $vppmm / $scale")")
        cur_fnt=$(round "$(calc "$size_boost * $TARGET_FONT_MM * $vppmm / $scale")")
        cur_cur=$(round "$(calc "$size_boost * $TARGET_CURSOR_MM * $vppmm / $scale")")

        (( cur_bar > bar_height )) && bar_height=$cur_bar
        (( cur_fnt > bar_font ))   && bar_font=$cur_fnt
        (( cur_cur > cursor_size )) && cursor_size=$cur_cur
    fi

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
# constant physical size across all displays:
#   config = target_mm * vertical_pixels_per_mm / scale
#
# computed per-output above; falls back to proportional
# sizing when physical dimensions are unknown
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
