#!/usr/bin/env bash

# scales outputs (and the bar/cursor) from each panel's real physical size.
# calibration reference: 2560px-wide mode at scale 1.5 -> bar height 23,
# font pixelsize 15, cursor 15. everything else is linear from that.

REF_WIDTH=2560
REF_SCALE=1.5
BAR_HEIGHT=23
BAR_FONT=15
CURSOR_SIZE=15
CURSOR_THEME="GoogleDot-Black"

DOTFILES_DIR="$HOME/.config/rstl.sway"
YAMBAR_SRC="$DOTFILES_DIR/yambar/config.yml"
YAMBAR_OUT="${XDG_CACHE_HOME:-$HOME/.cache}/rstl.sway/yambar-config.yml"

calc() { awk "BEGIN{print ($1)}"; }
round() { awk -v n="$1" 'BEGIN{s=n<0?-1:1; printf "%d", s*int(s*n+0.5)}'; }

max_scale=0

cur_out="" cur_diag=0 cur_width=0

apply_out() {
    [[ "$cur_width" -gt 0 ]] || return 0
    [[ "$(calc "$cur_diag > 0")" -eq 1 ]] || return 0

    local base scale
    if [[ "$(calc "$cur_diag < 20")" -eq 1 ]]; then
        base=2      # small panel: denser pixels, needs a bigger scale
    else
        base=1.5
    fi

    scale=$(calc "$base * $cur_width / $REF_WIDTH")
    printf 'setting %s: %.1f" %dpx -> scale %.2f\n' "$cur_out" "$cur_diag" "$cur_width" "$scale"
    swaymsg output "$cur_out" scale "$scale" >/dev/null

    # global ui sizing follows the densest display
    if [[ "$(calc "$scale > $max_scale")" -eq 1 ]]; then
        max_scale=$scale
    fi
}

while IFS= read -r line; do
    case $line in
        Output\ *)
            apply_out
            cur_out=${line#Output }
            cur_out=${cur_out%% *}
            cur_diag=0
            cur_width=0
            ;;
        *"Physical size:"*)
            ps=${line##*: }          # "600x340 mm"
            ps_w=${ps%%x*}
            rest=${ps#*x}; ps_h=${rest%% *}
            cur_diag=$(calc "sqrt($ps_w*$ps_w+$ps_h*$ps_h)/25.4")
            ;;
        " "*)
            if [[ $line == *current* && $line =~ [[:space:]]([0-9]+)x[0-9]+ ]]; then
                cur_width=${BASH_REMATCH[1]}
            fi
            ;;
    esac
done < <(wlr-randr)
apply_out

if [[ "$(calc "$max_scale > 0")" -ne 1 ]]; then
    echo "auto-scale: could not read display info, keeping reference sizing" >&2
    max_scale=$REF_SCALE
fi

bar_height=$(round "$(calc "$BAR_HEIGHT * $max_scale / $REF_SCALE")")
bar_font=$(round "$(calc "$BAR_FONT * $max_scale / $REF_SCALE")")
cursor_size=$(round "$(calc "$CURSOR_SIZE * $max_scale / $REF_SCALE")")

printf 'ui sizing: scale %.2f -> bar %dpx, font %dpx, cursor %dpx\n' \
    "$max_scale" "$bar_height" "$bar_font" "$cursor_size"

# render the yambar config with scaled dimensions (source stays pristine)
if [[ -f $YAMBAR_SRC ]]; then
    mkdir -p "${YAMBAR_OUT%/*}"
    sed -E \
        -e "s/^([[:space:]]*height:[[:space:]]*)[0-9]+/\1$bar_height/" \
        -e "s/pixelsize=[0-9]+/pixelsize=$bar_font/" \
        "$YAMBAR_SRC" > "${YAMBAR_OUT}.new" \
        && mv "${YAMBAR_OUT}.new" "$YAMBAR_OUT"
else
    echo "auto-scale: missing $YAMBAR_SRC, skipping bar render" >&2
fi

# cursor size for sway-managed clients...
swaymsg seat seat0 xcursor_theme "$CURSOR_THEME" "$cursor_size" >/dev/null
# ...and everything launched through dbus/systemd
dbus-update-activation-environment XCURSOR_THEME="$CURSOR_THEME" XCURSOR_SIZE="$cursor_size" 2>/dev/null || true

# bar already up? (manual or hotplug run) bounce it onto the new config
if pgrep -x yambar >/dev/null 2>&1; then
    killall -q yambar yambar-fullscreen.sh 2>/dev/null
    sleep 0.2
    setsid "$DOTFILES_DIR/scripts/yambar-fullscreen.sh" >/dev/null 2>&1 &
fi
