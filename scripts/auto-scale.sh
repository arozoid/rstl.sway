#!/bin/sh

# ============================================================
# rstl.sway auto scaling
#
# Configurable, density-based scaling for sway output scale, the yambar
# bar/font, and the cursor. Sizes are expressed in PHYSICAL MILLIMETERS so
# the bar/font keep the same real size regardless of resolution or display
# size, then scaled back into pixels per output.
#
# reference ("on here"): 12.5" 2560x1440 @ scale 2.0, 280x160 mm
#   bar 35px  -> 7.78 mm    bar_px * scale * phys_h_mm / height
#   font 23px -> 5.11 mm
#
# scaling rule: pick the output scale from PIXEL DENSITY (PPI), not the
# diagonal. Diagonal alone cannot tell a 34" 2560x1080 ultrawide (~81 PPI,
# needs 1.0x) from a 12.5" 2560x1440 laptop (~235 PPI, needs 2.0x). We aim
# for the reference panel's effective density (~117 PPI):
#   scale = round(PPI / target_PPI / 0.25) * 0.25, clamped to 1.0..2.0
# so a large low-density panel stays at 1.0x instead of getting a huge UI.
#
# Density alone under-scales a big standard-aspect 1440p panel: a 32"
# 2560x1440 is only ~92 PPI and would land at 1.0x, which is too much
# desktop for that viewing distance. Large 16:9/16:10 panels (>=30",
# >=1440 vertical lines) therefore get a 1.5x floor. The aspect-ratio
# check is deliberate: a 34" 2560x1080 ultrawide has a 1080-line height
# and a wide 21:9 frame, so it stays on the density ladder at 1.0x.
#
# An explicit `output <name> scale <n>` line in 25-displays.conf wins
# over both rules, for panels whose EDID is wrong or whose user simply
# wants a different scale.
#
# Sizing philosophy: the bar/font are expressed in PHYSICAL MILLIMETERS,
# then converted to pixels per output as  px = mm * height / (scale * phys_h_mm).
# They keep the same real-world size on normal panels; the cursor uses a fixed
# logical size that stays comfortable at both 1x and 2x. Large standard-aspect
# panels get one extra yambar multiplier: keeping the reference's 7.8mm bar on
# a 32" desktop makes it look tiny at 1.5x, so those panels use a 1.75x larger
# bar and font. For a TV viewed from across the room, raise REF_BAR_PX /
# REF_FONT_PX instead of reintroducing diagonal bands.
# ============================================================

set -u

DOTFILES_DIR="$HOME/.config/rstl.sway"
YAMBAR_SRC="$DOTFILES_DIR/yambar/config.yml"
YAMBAR_OUT="${XDG_CACHE_HOME:-$HOME/.cache}/rstl.sway/yambar-config.yml"

# ---------- cursor theme ----------
# The theme is a user setting, so it lives with the other settings in
# sway/config.d/20-cursor.conf. Read it from there instead of duplicating it
# here: this script re-applies the theme (with a runtime-computed size) on every
# start and every reload, so a second copy would silently win over the user's.
# The fallback is only used when the config is missing or has no such line.
CURSOR_CONF="$DOTFILES_DIR/sway/config.d/20-cursor.conf"
CURSOR_THEME="$(sed -nE 's/^[^#]*xcursor_theme[[:space:]]+([^[:space:]]+).*/\1/p' \
    "$CURSOR_CONF" 2>/dev/null | head -n 1)"
[ -n "$CURSOR_THEME" ] || CURSOR_THEME="Notwaita-Gray"

# per-output scale overrides. The ratl display dialog writes local/display.conf;
# an `output <name> scale <n>` line there wins, then 25-displays.conf.
DISPLAY_SETTINGS="$DOTFILES_DIR/local/display.conf"
DISPLAYS_CONF="$DOTFILES_DIR/sway/config.d/25-displays.conf"

# ---------- reference ("on here") ----------
REF_WIDTH=2560
REF_HEIGHT=1440
REF_DIAG=12.5
# mm of the reference panel's physical height
REF_PHYS_H_MM=160

# reference pixels (at scale 2.0) that we consider "1.0x"
REF_BAR_PX=35
REF_FONT_PX=23
REF_CURSOR_PX=25

# ---------- scale rule (by pixel density) ----------
# The reference panel is ~235 PPI at scale 2.0, so aim for ~117 effective
# PPI. Scale to the nearest 0.25 and clamp to 1.0..2.0: this keeps a 34"
# 2560x1080 ultrawide (~81 PPI) at 1.0x, gives a 27" 4K (~163 PPI) 1.5x,
# and a 12.5" 2560x1440 laptop (~235 PPI) 2.0x. Diagonal alone is not enough:
# large low-density panels and smaller high-density panels can share a
# diagonal but need very different scales.
REF_SCALE=2.0
MIN_SCALE=1.0
MAX_SCALE=2.0
SCALE_STEP=0.25

# large standard-aspect monitor floor (see the rule above)
LARGE_PANEL_MIN_DIAG=30
LARGE_PANEL_MIN_HEIGHT=1440
LARGE_PANEL_MAX_ASPECT=1.9
LARGE_PANEL_MIN_SCALE=1.5
LARGE_PANEL_YAMBAR_MULT=1.75

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

# derived physical mm of the reference UI (constant across panels)
REF_BAR_MM=$(calc "$REF_BAR_PX * $REF_SCALE * $REF_PHYS_H_MM / $REF_HEIGHT")    # 7.78
REF_FONT_MM=$(calc "$REF_FONT_PX * $REF_SCALE * $REF_PHYS_H_MM / $REF_HEIGHT")  # 5.11

# reference pixel density and the effective density we scale towards
REF_PPI=$(calc "sqrt($REF_WIDTH*$REF_WIDTH + $REF_HEIGHT*$REF_HEIGHT) / $REF_DIAG")  # ~235
TARGET_PPI=$(calc "$REF_PPI / $REF_SCALE")                                           # ~117
# ============================================================
# outputs + physical sizes
#   - name / mode WxH come from swaymsg (no wlr-randr needed)
#   - physical mm come from each connector's EDID base block
#     (bytes 0x15-0x16 carry the max image size in cm); that is
#     exactly what wlr-randr used to report as "Physical size".
# ============================================================

# $1 = sway output name ("eDP-1"); echoes the explicit scale or nothing
scale_override() {
    name="$1"
    value=""
    for conf in "$DISPLAY_SETTINGS" "$DISPLAYS_CONF"; do
        [ -f "$conf" ] || continue
        value=$(sed -nE \
            "s/^[[:space:]]*output[[:space:]]+${name}[[:space:]]+scale[[:space:]]+([0-9]+([.][0-9]+)?).*/\\1/p" \
            "$conf" 2>/dev/null | head -n 1)
        [ -n "$value" ] && break
    done
    [ -n "$value" ] || return 1
    # keep the override inside the same supported range as the auto rule
    [ "$(calc "$value >= $MIN_SCALE && $value <= $MAX_SCALE")" -eq 1 ] || return 1
    printf '%s\n' "$value"
}

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
    scale="$(scale_override "$cur_out")" || scale=""

    # physical dims unknown -> default sane 2k values
    if [ "$cur_w" -eq 0 ] || [ "$cur_h" -eq 0 ] || [ "$(calc "$cur_diag < 1")" -eq 1 ]; then
        cur_cursor=$REF_CURSOR_PX
        [ -n "$scale" ] || scale=1.0
        cur_bar=$(round "$(calc "$REF_BAR_PX * $cur_height / $REF_HEIGHT")")
        cur_fnt=$(round "$(calc "$REF_FONT_PX * $cur_height / $REF_HEIGHT")")
        printf 'setting %s: unknown size -> scale %.2f, bar %dpx, font %dpx, cursor %dpx\n' \
            "$cur_out" "$scale" "$cur_bar" "$cur_fnt" "$cur_cursor"
        swaymsg output "$cur_out" scale "$scale"
        [ "$cur_height" -gt "$max_height" ] && max_height=$cur_height
        continue
    fi

    cur_ppi=$(calc "sqrt($cur_width*$cur_width+$cur_height*$cur_height)/$cur_diag")
    cur_aspect=$(calc "$cur_width / $cur_height")

    # Large standard-aspect panels also get a larger yambar. The physical-mm
    # reference alone leaves a 32" 1440p bar at 19px logical / ~8mm tall, which
    # reads as tiny next to 1.5x desktop UI.
    ybar_mult=1.0
    if [ "$(calc "$cur_diag >= $LARGE_PANEL_MIN_DIAG")" -eq 1 ] &&
       [ "$cur_height" -ge "$LARGE_PANEL_MIN_HEIGHT" ] &&
       [ "$(calc "$cur_aspect <= $LARGE_PANEL_MAX_ASPECT")" -eq 1 ]; then
        ybar_mult=$LARGE_PANEL_YAMBAR_MULT
    fi

    # ---- explicit per-output override wins ----
    if [ -z "$scale" ]; then
        # ---- otherwise pick scale by pixel density ----
        scale_steps=$(round "$(calc "$cur_ppi / $TARGET_PPI / $SCALE_STEP")")
        scale=$(calc "$scale_steps * $SCALE_STEP")
        if [ "$(calc "$scale < $MIN_SCALE")" -eq 1 ]; then
            scale=$MIN_SCALE
        fi
        if [ "$(calc "$scale > $MAX_SCALE")" -eq 1 ]; then
            scale=$MAX_SCALE
        fi

        # Large standard-aspect 1440p+ panels need more than their low
        # PPI suggests. Keep ultrawides out of this floor: their shorter
        # vertical mode is the reason they stay at 1.0x.
        if [ "$(calc "$cur_diag >= $LARGE_PANEL_MIN_DIAG")" -eq 1 ] &&
           [ "$cur_height" -ge "$LARGE_PANEL_MIN_HEIGHT" ] &&
           [ "$(calc "$cur_aspect <= $LARGE_PANEL_MAX_ASPECT")" -eq 1 ] &&
           [ "$(calc "$scale < $LARGE_PANEL_MIN_SCALE")" -eq 1 ]; then
            scale=$LARGE_PANEL_MIN_SCALE
        fi
    fi

    # bar/font keep their reference physical size on small panels; large
    # standard-aspect panels get ybar_mult to stay readable at desk distance.
    # The cursor uses a fixed logical size instead.
    bar_mm=$(calc "$REF_BAR_MM * $ybar_mult")
    font_mm=$(calc "$REF_FONT_MM * $ybar_mult")
    cur_cursor=$REF_CURSOR_PX

    # convert physical mm to pixels for this panel: px = mm * height / (scale * phys_h)
    cur_bar=$(round "$(calc "$bar_mm * $cur_height / ($scale * $cur_h)")")
    cur_fnt=$(round "$(calc "$font_mm * $cur_height / ($scale * $cur_h)")")

    [ "$cur_bar" -gt "$bar_height" ] && bar_height=$cur_bar
    [ "$cur_fnt" -gt "$bar_font" ]   && bar_font=$cur_fnt
    [ "$cur_cursor" -gt "$cursor_size" ] && cursor_size=$cur_cursor

    printf \
        'setting %s: %.0fppi %.1f" -> scale %.2f, bar %dpx (%.1fmm), font %dpx, cursor %dpx\n' \
        "$cur_out" \
        "$cur_ppi" \
        "$cur_diag" \
        "$scale" \
        "$cur_bar" \
        "$bar_mm" \
        "$cur_fnt" \
        "$cur_cursor"

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
# hand the bars back to the desktop manager, which re-reads the
# config that was just rendered (a fresh supervisor replaces the
# one that was running, so it must not inherit the old bar pids)
# ============================================================

if pgrep -x yambar >/dev/null 2>&1; then
    killall -q yambar rstl_desktop.sh 2>/dev/null
    sleep 0.2
    setsid "$DOTFILES_DIR/scripts/rstl_desktop.sh" >/dev/null 2>&1 &
fi
