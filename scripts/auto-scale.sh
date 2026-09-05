#!/bin/sh

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
# resolution -> lower physical dpi, so output scale is corrected down,
# but the yambar/cursor mm are corrected UP: readability matters, and
# the same physical mm that looks good on 2k is hard to read on a
# 1366x768 display. so lower-res panels get a bigger bar/cursor
# (inverse-of-height factor, clamped to never go tiny).
# ============================================================

set -u

CURSOR_THEME="phinger-cursors-dark"

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
REF_CURSOR_PX=24

# ---------- size bands (by diagonal inches) ----------
# each band: <diag|max> scale yambar_mult cursor_default
# scale is the 2k baseline; yambar_mult scales the bar/font mm
BAND_1_MAX=17
BAND_1_SCALE=2.0
BAND_1_YBAR=1.0
BAND_1_CURSOR=24

BAND_2_MAX=25
BAND_2_SCALE=1.75
BAND_2_YBAR=1.5
BAND_2_CURSOR=24

BAND_3_MAX=9999
BAND_3_SCALE=1.5
BAND_3_YBAR=2.0
BAND_3_CURSOR=24


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
# outputs + physical sizes
#   - name / mode WxH come from swaymsg (no wlr-randr needed)
#   - physical mm come from each connector's EDID base block
#     (bytes 0x15-0x16 carry the max image size in cm); that is
#     exactly what wlr-randr used to report as "Physical size".
# ============================================================

# $1 = sway output name ("eDP-1"); echoes "W H" (mm) or nothing
phys_mm() {
    out="$1"
    for edid in /sys/class/drm/card*/card*-${out}/edid; do
        [ -f "$edid" ] || continue
        set -- $(dd if="$edid" bs=1 skip=21 count=2 2>/dev/null | od -An -v -tu1)
        w_cm=${1:-0}
        h_cm=${2:-0}
        # trust whatever the kernel parsed out of the EDID (this is exactly
        # what wlr-randr reported); just sanity-check for a real size
        if [ "$w_cm" -gt 0 ] && [ "$w_cm" -lt 255 ] && [ "$h_cm" -gt 0 ] && [ "$h_cm" -lt 255 ]; then
            printf '%s %s\n' "$((w_cm * 10))" "$((h_cm * 10))"
            return 0
        fi
        return 1
    done
    return 1
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
outfile="$tmpdir/out"

swaymsg -t get_outputs -r | jq -r '
    .[] |
    [
        .name,
        .current_mode.width,
        .current_mode.height
    ] |
    @tsv
' > "$outfile"


# ============================================================
# per-output scaling
# ============================================================

max_height=0
bar_height=0
bar_font=0
cursor_size=0

swaymsg -t get_outputs -r | jq -r '
    .[] |
    [
        .name,
        .current_mode.width,
        .current_mode.height
    ] |
    @tsv
' > "$outfile"

while IFS="$(printf '\t')" read -r cur_out cur_width cur_height; do
    case "$cur_out" in
        ""|*[!a-zA-Z0-9_-]*) continue ;;
    esac

    # physical mm from EDID (empty/0 -> unknown, goes to the fallback path)
    set -- $(phys_mm "$cur_out")
    cur_w=${1:-0}
    cur_h=${2:-0}
    cur_diag=$(calc "sqrt($cur_w*$cur_w+$cur_h*$cur_h)/25.4")

    # physical dims unknown -> default sane 2k values
    if [ "$cur_w" -eq 0 ] || [ "$cur_h" -eq 0 ] || [ "$(calc "$cur_diag < 1")" -eq 1 ]; then
        base_scale=1.0
        ybar_mult=1.0
        cur_cursor=$REF_CURSOR_PX
        scale=$base_scale
        cur_bar=$(round "$(calc "$REF_BAR_PX * $cur_height / $REF_HEIGHT")")
        cur_fnt=$(round "$(calc "$REF_FONT_PX * $cur_height / $REF_HEIGHT")")
        printf 'setting %s: unknown size -> scale %.2f, bar %dpx, font %dpx, cursor %dpx\n' \
            "$cur_out" "$scale" "$cur_bar" "$cur_fnt" "$cur_cursor"
        swaymsg output "$cur_out" scale "$scale"
        [ "$cur_height" -gt "$max_height" ] && max_height=$cur_height
        continue
    fi

    # ---- pick band by diagonal ----
    if [ "$(calc "$cur_diag < $BAND_1_MAX")" -eq 1 ]; then
        band=1; base_scale=$BAND_1_SCALE; ybar_mult=$BAND_1_YBAR
        cur_cursor=$BAND_1_CURSOR
    elif [ "$(calc "$cur_diag < $BAND_2_MAX")" -eq 1 ]; then
        band=2; base_scale=$BAND_2_SCALE; ybar_mult=$BAND_2_YBAR
        cur_cursor=$BAND_2_CURSOR
    else
        band=3; base_scale=$BAND_3_SCALE; ybar_mult=$BAND_3_YBAR
        cur_cursor=$BAND_3_CURSOR
    fi

    # ---- resolution / dpi correction ----
    # base scale assumes a 1440p panel; lower res -> lower scale.
    res_corr=$(calc "$cur_height / $REF_HEIGHT")
    scale=$(calc "$base_scale * $res_corr")

    # ---- yambar / cursor READABILITY factor ----
    # lower resolution = harder to read the same physical mm, so bump
    # the yambar/cursor mm up as resolution drops. use the SQUARE ROOT
    # of the inverse-of-height so the bump is gentle (1366 ~= x1.37,
    # 1080p ~= x1.15, 2k = x1.0) rather than a full inverse (x1.88).
    dpi_k=$(calc "sqrt($REF_HEIGHT / $cur_height)")

    bar_mm=$(calc "$REF_BAR_MM * $ybar_mult * $dpi_k")
    font_mm=$(calc "$REF_FONT_MM * $ybar_mult * $dpi_k")
    # cursor bumps gentler than the bar on lower res so it doesn't
    # overwhelm; uses the cube-root of the readability factor.
    cur_cur=$(round "$(calc "$cur_cursor * ($REF_HEIGHT / $cur_height) ^ (1/3)")")

    # convert back to pixels for this panel: px = mm * height / (scale * phys_h)
    cur_bar=$(round "$(calc "$bar_mm * $cur_height / ($scale * $cur_h)")")
    cur_fnt=$(round "$(calc "$font_mm * $cur_height / ($scale * $cur_h)")")

    [ "$cur_bar" -gt "$bar_height" ] && bar_height=$cur_bar
    [ "$cur_fnt" -gt "$bar_font" ]   && bar_font=$cur_fnt
    [ "$cur_cur" -gt "$cursor_size" ] && cursor_size=$cur_cur

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

    [ "$cur_height" -gt "$max_height" ] && max_height=$cur_height
done < "$outfile"


# ============================================================
# fallback sizing (nothing usable)
# ============================================================

if [ "$max_height" -le 0 ]; then
    max_height=$REF_HEIGHT
fi
[ "$bar_height" -gt 0 ] || bar_height=$(round "$(calc "$REF_BAR_PX * $max_height / $REF_HEIGHT")")
[ "$bar_font" -gt 0 ]   || bar_font=$(round "$(calc "$REF_FONT_PX * $max_height / $REF_HEIGHT")")
[ "$cursor_size" -gt 0 ] || cursor_size=$REF_CURSOR_PX


# ============================================================
# render yambar config
# ============================================================

printf 'ui sizing: bar %dpx, font %dpx, cursor %dpx\n' \
    "$bar_height" "$bar_font" "$cursor_size"

if [ -f "$YAMBAR_SRC" ]; then
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
