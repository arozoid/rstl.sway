#!/bin/sh
# Shared helpers for the ratl-based settings tools in ../bin.
#
# This file is sourced, so it must not call `set` or `exit` at the top level.
# Every tool gets the same dialog look, the same local state directory, and the
# same "print instead of apply" escape hatch for testing.

RSTL_SETTINGS_DIR="${RSTL_SWAY_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/rstl.sway}"
RSTL_LOCAL_DIR="$RSTL_SETTINGS_DIR/local"
if [ -n "${RATL:-}" ]; then
    RATL_BIN="$RATL"
elif [ -x "$HOME/.local/bin/ratl" ]; then
    # foot's server keeps the PATH it was started with, which often predates
    # ~/.local/bin. Prefer the user's build so the settings dialogs do not fall
    # back to an older system ratl.
    RATL_BIN="$HOME/.local/bin/ratl"
else
    RATL_BIN=ratl
fi

settings_die() {
    printf '%s: %s\n' "${0##*/}" "$*" >&2
    exit 2
}

settings_have() {
    command -v "$1" >/dev/null 2>&1
}

settings_need_ratl() {
    settings_have "$RATL_BIN" ||
        settings_die "ratl is not installed (expected in PATH, or set RATL)"
}

settings_need_jq() {
    settings_have jq || settings_die "jq is not installed"
}

settings_need_sway() {
    settings_have swaymsg || settings_die "swaymsg is not available"
}

# ratl is a TUI and needs a terminal on both ends. When a settings script is
# started from swaymsg/cron/another non-interactive context, reopen it in foot
# instead of failing with ratl's tty error. Normal terminal and win+comma
# launches already have a tty and pass straight through.
settings_need_tty() {
    if [ -t 0 ] && [ -t 1 ]; then
        return 0
    fi
    [ "${DRY_RUN:-0}" = 1 ] && return 0

    if [ "${RSTL_TERMINAL_RELAUNCHED:-0}" = 1 ]; then
        settings_die "ratl needs an interactive terminal (run this from foot or another terminal)"
    fi

    # Only auto-open a terminal when both ends are non-interactive. A redirected
    # stdout in an interactive shell should stay a plain error, not spawn a
    # second window.
    if [ ! -t 0 ] && [ ! -t 1 ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
        # footclient does not forward the caller's environment to the client
        # (the foot server supplies its own), so pass the recursion marker
        # through env explicitly.
        if [ -x "$RSTL_SETTINGS_DIR/scripts/foot-smart.sh" ]; then
            exec "$RSTL_SETTINGS_DIR/scripts/foot-smart.sh" \
                --app-id=rstl-settings -e env RSTL_TERMINAL_RELAUNCHED=1 "$0" "$@"
        elif settings_have footclient; then
            exec footclient --app-id=rstl-settings \
                -e env RSTL_TERMINAL_RELAUNCHED=1 "$0" "$@"
        elif settings_have foot; then
            exec foot --app-id=rstl-settings \
                -e env RSTL_TERMINAL_RELAUNCHED=1 "$0" "$@"
        fi
    fi

    settings_die "ratl needs an interactive terminal (run this from foot or another terminal)"
}

# Image elements are newer than the first ratl release. Keep the wallpaper
# dialog usable with an older ratl by falling back to a text-only preview.
ratl_supports_images() {
    "$RATL_BIN" --schema 2>/dev/null | jq -e '.["$defs"].image' >/dev/null 2>&1
}

ensure_local_dir() {
    mkdir -p "$RSTL_LOCAL_DIR" ||
        settings_die "cannot create $RSTL_LOCAL_DIR"
}

# Run a ratl dialog and print its JSON result. Returns 1 when the user
# cancels, so callers can simply `|| exit 0`.
ratl_run() {
    settings_need_ratl
    "$RATL_BIN" --json "$1"
}

ratl_select() {
    title="$1"
    label="$2"
    options="$3"
    selected="${4:-0}"
    json=$(jq -n \
        --arg title "$title" \
        --arg label "$label" \
        --argjson options "$options" \
        --argjson selected "$selected" \
        '{
            title: $title,
            width: 76,
            min_width: 50,
            max_width: 100,
            children: [
                {
                    type: "select",
                    id: "choice",
                    label: $label,
                    options: $options,
                    selected: $selected
                }
            ],
            buttons: [
                { label: "OK", action: "submit", kind: "primary" },
                { label: "Cancel", action: "cancel" }
            ]
        }') || return 1
    ratl_run "$json"
}

ratl_message() {
    title="$1"
    text="$2"
    json=$(jq -n \
        --arg title "$title" \
        --arg text "$text" \
        '{
            title: $title,
            width: 80,
            min_width: 50,
            max_width: 100,
            children: [
                { type: "label", text: $text }
            ],
            buttons: [
                { label: "OK", action: "submit", kind: "primary" }
            ]
        }') || return 1
    ratl_run "$json" >/dev/null || true
}

atomic_write() {
    file="$1"
    tmp="${file}.tmp.$$"
    if ! cat > "$tmp"; then
        rm -f "$tmp"
        return 1
    fi
    mv -f "$tmp" "$file"
}

expand_home() {
    case "$1" in
        "~") printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

valid_name() {
    case "$1" in
        "" | *[!A-Za-z0-9_-]*) return 1 ;;
        *) return 0 ;;
    esac
}

# Input identifiers look like "1:1:AT_Translated_Set_2_keyboard" or
# "2:1:PS/2_Generic_Mouse". Sway config quotes them, so a slash is safe.
valid_identifier() {
    case "$1" in
        "" | *[!A-Za-z0-9:._/-]*) return 1 ;;
        *) return 0 ;;
    esac
}

valid_scale() {
    case "$1" in
        "" | *[!0-9.]* | *.*.*) return 1 ;;
        *) return 0 ;;
    esac
}

valid_mode() {
    case "$1" in
        *x*@*Hz) return 0 ;;
        *) return 1 ;;
    esac
}

valid_transform() {
    case "$1" in
        normal | 90 | 180 | 270 | flipped | flipped-90 | flipped-180 | flipped-270)
            return 0
            ;;
        *) return 1 ;;
    esac
}

# Apply a command now, or print it when DRY_RUN=1. Tests use this to exercise
# the whole script without touching the running session.
run_cmd() {
    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf 'would run:' >&2
        printf ' %s' "$@" >&2
        printf '\n' >&2
        return 0
    fi
    "$@"
}

# Same as run_cmd, but captures combined output so a dialog can show the
# compositor's error message instead of dying silently.
run_cmd_capture() {
    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf 'would run:' >&2
        printf ' %s' "$@" >&2
        printf '\n' >&2
        return 0
    fi
    "$@" 2>&1
}

sway_outputs() {
    swaymsg -t get_outputs -r
}

sway_inputs() {
    swaymsg -t get_inputs -r
}

minutes_options() {
    jq -n '[
        { label: "Never", value: "0" },
        { label: "1 minute", value: "60" },
        { label: "2 minutes", value: "120" },
        { label: "3 minutes", value: "180" },
        { label: "5 minutes", value: "300" },
        { label: "10 minutes", value: "600" },
        { label: "15 minutes", value: "900" },
        { label: "20 minutes", value: "1200" },
        { label: "30 minutes", value: "1800" },
        { label: "45 minutes", value: "2700" },
        { label: "1 hour", value: "3600" }
    ]'
}

# One image path per line, de-duplicated. The current wallpaper comes first so
# the picker opens on something useful even when the search directories are
# empty.
wallpaper_paths() {
    {
        [ -r "$RSTL_LOCAL_DIR/wallpaper" ] &&
            head -n 1 "$RSTL_LOCAL_DIR/wallpaper"
        [ -r "$RSTL_SETTINGS_DIR/wallpaper" ] &&
            head -n 1 "$RSTL_SETTINGS_DIR/wallpaper"
        for dir in \
            "$HOME/Pictures/Wallpapers" \
            "$HOME/Pictures" \
            "$HOME/.local/share/backgrounds" \
            "$RSTL_SETTINGS_DIR/wallpapers" \
            "$RSTL_SETTINGS_DIR/assets/images"
        do
            [ -d "$dir" ] || continue
            find "$dir" -maxdepth 1 -type f \
                \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
                -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \
                -o -iname '*.tif' -o -iname '*.tiff' \) \
                -print 2>/dev/null
        done
    } | while IFS= read -r path; do
        [ -n "$path" ] || continue
        path=$(expand_home "$path")
        [ -f "$path" ] && printf '%s\n' "$path"
    done | awk '!seen[$0]++'
}
