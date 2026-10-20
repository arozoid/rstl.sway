#!/bin/sh
# Apply CachyOS's pacman output defaults to /etc/pacman.conf:
#   Color, ILoveCandy, VerbosePkgLists, DisableDownloadTimeout,
#   ParallelDownloads = 10
#
# Only those option lines are touched. Repositories, mirrors, IgnorePkg,
# NoExtract and every other setting stay as they are. The edit is idempotent,
# so running it from every installer (or by hand) is safe.
#
# PACMAN_CONF can point at another file for testing.

set -u

conf="${PACMAN_CONF:-/etc/pacman.conf}"
[ -f "$conf" ] || exit 0
command -v pacman >/dev/null 2>&1 || exit 0
grep -q '^[[:space:]]*\[options\]' "$conf" || exit 0

write_conf() {
    if [ "$(id -u)" -eq 0 ] || [ -w "$conf" ]; then
        cp "$1" "$conf"
    else
        sudo -v
        sudo cp "$1" "$conf"
    fi
}

if grep -q '^[[:space:]]*# Misc options[[:space:]]*$' "$conf"; then
    anchor_misc=1
else
    anchor_misc=0
fi

has_color=0
has_candy=0
has_verbose=0
has_disable=0
has_parallel=0
grep -q '^[[:space:]]*#\?[[:space:]]*Color[[:space:]]*$' "$conf" && has_color=1
grep -q '^[[:space:]]*#\?[[:space:]]*ILoveCandy[[:space:]]*$' "$conf" && has_candy=1
grep -q '^[[:space:]]*#\?[[:space:]]*VerbosePkgLists[[:space:]]*$' "$conf" && has_verbose=1
grep -q '^[[:space:]]*#\?[[:space:]]*DisableDownloadTimeout[[:space:]]*$' "$conf" && has_disable=1
grep -q '^[[:space:]]*#\?[[:space:]]*ParallelDownloads[[:space:]]*=' "$conf" && has_parallel=1

tmp="$(mktemp)" || exit 1
trap 'rm -f "$tmp"' EXIT HUP INT TERM

awk -v anchor_misc="$anchor_misc" \
    -v has_color="$has_color" -v has_candy="$has_candy" \
    -v has_verbose="$has_verbose" -v has_disable="$has_disable" \
    -v has_parallel="$has_parallel" '
    anchor_misc == 1 && /^[[:space:]]*# Misc options[[:space:]]*$/ && !anchored {
        print
        if (!has_color)  { print "Color"; print "ILoveCandy"; color_done = 1; candy_done = 1 }
        if (!has_verbose) { print "VerbosePkgLists"; print "DisableDownloadTimeout"; verbose_done = 1; disable_done = 1 }
        if (!has_parallel) { print "ParallelDownloads = 10"; parallel_done = 1 }
        anchored = 1
        next
    }
    anchor_misc == 0 && /^[[:space:]]*\[options\][[:space:]]*$/ && !anchored {
        print
        if (!has_color)  { print "Color"; print "ILoveCandy"; color_done = 1; candy_done = 1 }
        if (!has_verbose) { print "VerbosePkgLists"; print "DisableDownloadTimeout"; verbose_done = 1; disable_done = 1 }
        if (!has_parallel) { print "ParallelDownloads = 10"; parallel_done = 1 }
        anchored = 1
        next
    }
    /^[[:space:]]*#?[[:space:]]*Color[[:space:]]*$/ {
        if (!color_done) {
            print "Color"
            color_done = 1
            if (!has_candy && !candy_done) { print "ILoveCandy"; candy_done = 1 }
        }
        next
    }
    /^[[:space:]]*#?[[:space:]]*ILoveCandy[[:space:]]*$/ {
        if (!candy_done) { print "ILoveCandy"; candy_done = 1 }
        next
    }
    /^[[:space:]]*#?[[:space:]]*VerbosePkgLists[[:space:]]*$/ {
        if (!verbose_done) {
            print "VerbosePkgLists"
            verbose_done = 1
            if (!has_disable && !disable_done) { print "DisableDownloadTimeout"; disable_done = 1 }
        }
        next
    }
    /^[[:space:]]*#?[[:space:]]*DisableDownloadTimeout[[:space:]]*$/ {
        if (!disable_done) { print "DisableDownloadTimeout"; disable_done = 1 }
        next
    }
    /^[[:space:]]*#?[[:space:]]*ParallelDownloads[[:space:]]*=/ {
        if (!parallel_done) { print "ParallelDownloads = 10"; parallel_done = 1 }
        next
    }
    { print }
' "$conf" > "$tmp" || exit 1

if cmp -s "$conf" "$tmp"; then
    echo "  pacman output already uses the CachyOS settings"
    exit 0
fi

write_conf "$tmp" || exit 1
echo "  pacman: enabled Color, ILoveCandy, VerbosePkgLists, DisableDownloadTimeout, 10 parallel downloads"
