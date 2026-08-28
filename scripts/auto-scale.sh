#!/usr/bin/env bash

# ============================================================
# rstl.sway auto scaling
#
# Configurable, size-band based scaling for sway output scale,
# the yambar bar/font, and the cursor. Everything is expressed in
# PHYSICAL MILLIMETERS so the bar/cursor are the same real size
# regardless of resolution or display size, then scaled back into
# pixels per output.
#
# reference ("on here"): 12.5" 2560x1440 @ scale 2.0, 280x160 mm
#   bar 35px  -> 7.78 mm    bar_px * scale * phys_h_mm / height
#   font 23px -> 5.11 mm
#
# display-size bands (by diagonal):
#   < 17"  scale 2.00  yambar x1.0 (matches on-here mm)
#   < 25"  scale 1.75  yambar x1.5
#   >=25"  scale 1.50  yambar x2.0
#
# within a band, the base scale assumes a 1440p (2k) panel. lower
# resolution -> lower physical dpi, so scale is corrected by the
# resolution relative to 2k (see SCALE_HEIGHT_REF). height also
# feeds the yambar/cursor pixel math.
# ============================================================

set -u

CURSOR_THEME="GoogleDot-Black"

DOTFILES_DIR="$HOME/.config/rstl.sway"
YAMBAR_SRC="$DOTFILES_DIR/yambar/config.yml"
YAMBAR_OUT="${XDG_CACHE_HOME:-$HOME/.cache}/rstl.sway/yambar-config.yml"

# ---------- reference ("on here") ----------
REF_HEIGHT=1440
# mm of the reference panel's physical height
REF_PHYS_H_MM=160

# reference pixels (at scale 2.0) that we consider "1.0x"
REF_BAR_PX=35
REF_FONT_PX=23
REF_CURSOR_PX=20

# ---------- size bands (by diagonal inches) ----------
# each band: <diag|max> scale yambar_mult cursor_default
# scale is the 2k baseline; yambar_mult scales the bar/font mm
BAND_1_MAX=17
BAND_1_SCALE=2.0
BAND_1_YBAR=1.0
BAND_1_CURSOR=20

BAND_2_MAX=25
BAND_2_SCALE=1.75
BAND_2_YBAR=1.5
BAND_2_CURSOR=20

BAND_3_MAX=9999
BAND_3_SCALE=1.5
BAND_3_YBAR=2.0
BAND_3_CURSOR=20


# ============================================================
# helpers
# ============================================================

calc() { awk "BEGIN { print ($1) }"; }

round() {
    awk -v n="$1" '
        BEGIN {
            s = n < 0 ? -1 : 1
            printf "%d", s * int(s * n + 0.5)
        }
    '
}

# derived physical mm of the reference UI (later multiplied by band yambar)
REF_BAR_MM=$(calc           "$REF_BAR_PX * 2 * $REF_PHYS_H_MM / $REF_HEIGHT")    # 7.78
REF_FONT_MM=$(calc          "$REF_FONT_PX * 2 * $REF_PHYS_H_MM / $REF_HEIGHT")   # 5.11
REF_CURSOR_MM=$(calc        "$REF_CURSOR_PX * 2 * $REF_PHYS_H_MM / $REF_HEIGHT") # 4.44


# ============================================================
# read physical sizes from wlr-randr
# ============================================================

declare -A PHYS_W
declare -A PHYS_H
declare -A DIAG

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
            PHYS_W["$current_output"]=$ps_w
            PHYS_H["$current_output"]=$ps_h
            DIAG["$current_output"]=$(
                calc "sqrt($ps_w*$ps_w+$ps_h*$ps_h)/25.4"
            )
            ;;
    esac
done < <(wlr-randr)


# ============================================================
# per-output scaling
# ============================================================

max_height=0
bar_height=0
bar_font=0
cursor_size=0

while IFS=$'\t' read -r cur_out cur_width cur_height; do
    [[ "$cur_out" =~ ^[a-zA-Z0-9_-]+$ ]] || continue

    cur_w=${PHYS_W["$cur_out"]:-0}
    cur_h=${PHYS_H["$cur_out"]:-0}
    cur_diag=${DIAG["$cur_out"]:-0}

    # physical dims unknown -> default sane 2k values
    if (( cur_w == 0 || cur_h == 0 || cur_diag == 0 )); then
        base_scale=1.0
        ybar_mult=1.0
        cur_cursor=$REF_CURSOR_PX
        scale=$base_scale
        cur_bar=$(round "$(calc "$REF_BAR_PX * $cur_height / $REF_HEIGHT")")
        cur_fnt=$(round "$(calc "$REF_FONT_PX * $cur_height / $REF_HEIGHT")")
        printf 'setting %s: unknown size -> scale %.2f, bar %dpx, font %dpx, cursor %dpx\n' \
            "$cur_out" "$scale" "$cur_bar" "$cur_fnt" "$cur_cursor"
        swaymsg output "$cur_out" scale "$scale"
        (( cur_height > max_height )) && max_height=$cur_height
        continue
    fi

    # ---- pick band by diagonal ----
    if (( $(calc "$cur_diag < $BAND_1_MAX") == 1 )); then
        band=1; base_scale=$BAND_1_SCALE; ybar_mult=$BAND_1_YBAR
        cur_cursor=$BAND_1_CURSOR
    elif (( $(calc "$cur_diag < $BAND_2_MAX") == 1 )); then
        band=2; base_scale=$BAND_2_SCALE; ybar_mult=$BAND_2_YBAR
        cur_cursor=$BAND_2_CURSOR
    else
        band=3; base_scale=$BAND_3_SCALE; ybar_mult=$BAND_3_YBAR
        cur_cursor=$BAND_3_CURSOR
    fi

    # ---- resolution / dpi correction: base_scale assumes 1440p ----
    res_corr=$(calc "$cur_height / $REF_HEIGHT")
    scale=$(calc "$base_scale * $res_corr")

    # ---- yambar / cursor physical mm (band * reference) ----
    bar_mm=$(calc "$REF_BAR_MM * $ybar_mult")
    font_mm=$(calc "$REF_FONT_MM * $ybar_mult")

    # convert back to pixels for this panel: px = mm * height / (scale * phys_h)
    cur_bar=$(round "$(calc "$bar_mm * $cur_height / ($scale * $cur_h)")")
    cur_fnt=$(round "$(calc "$font_mm * $cur_height / ($scale * $cur_h)")")

    # cursor: band default at 2k baseline, corrected for resolution (dpi)
    cur_cur=$(round "$(calc "$cur_cursor * $cur_height / $REF_HEIGHT")")

    (( cur_bar > bar_height )) && bar_height=$cur_bar
    (( cur_fnt > bar_font ))   && bar_font=$cur_fnt
    (( cur_cur > cursor_size )) && cursor_size=$cur_cur

    printf \
        'setting %s: band%d %.1f" -> scale %.2f, bar %dpx (%.1fmm), font %dpx, cursor %dpx\n' \
        "$cur_out" \
        "$band" \
        "$cur_diag" \
        "$scale" \
        "$cur_bar" \
        "$bar_mm" \
        "$cur_fnt" \
        "$cur_cur"

    swaymsg output "$cur_out" scale "$scale"

    (( cur_height > max_height )) && max_height=$cur_height
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
# fallback sizing (nothing usable)
# ============================================================

if (( max_height <= 0 )); then
    max_height=$REF_HEIGHT
fi
(( bar_height > 0 )) || bar_height=$(round "$(calc "$REF_BAR_PX * $max_height / $REF_HEIGHT")")
(( bar_font > 0 ))   || bar_font=$(round "$(calc "$REF_FONT_PX * $max_height / $REF_HEIGHT")")
(( cursor_size > 0 )) || cursor_size=$REF_CURSOR_PX


# ============================================================
# render yambar config
# ============================================================

printf 'ui sizing: bar %dpx, font %dpx, cursor %dpx\n' \
    "$bar_height" "$bar_font" "$cursor_size"

if [[ -f "$YAMBAR_SRC" ]]; then
    mkdir -p "${YAMBAR_OUT%/*}"
    sed -E \
        -e "s/^([[:space:]]*height:[[:space:]]*)[0-9]+/\1$bar_height/" \
        -e "s/pixelsize=[0-9]+/pixelsize=$bar_font/" \
        "$YAMBAR_SRC" > "${YAMBAR_OUT}.new" \
        && mv "${YAMBAR_OUT}.new" "$YAMBAR_OUT"
else
    echo "auto-scale: missing $YAMBAR_SRC, skipping bar render" >&2
fi


# ============================================================
# cursor
# ============================================================

swaymsg seat seat0 xcursor_theme "$CURSOR_THEME" "$cursor_size" >/dev/null
dbus-update-activation-environment \
    XCURSOR_THEME="$CURSOR_THEME" XCURSOR_SIZE="$cursor_size" 2>/dev/null || true


# ============================================================
# restart yambar
# ============================================================

if pgrep -x yambar >/dev/null 2>&1; then
    killall -q yambar yambar-fullscreen.sh 2>/dev/null
    sleep 0.2
    setsid "$DOTFILES_DIR/scripts/yambar-fullscreen.sh" >/dev/null 2>&1 &
fi
