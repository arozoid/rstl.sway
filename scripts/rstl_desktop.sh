#!/bin/sh

# ============================================================
# rstl.sway desktop manager
#
# Gives every output a bar and a wallpaper, and keeps the bar of
# a screen out of the way while that screen shows something
# fullscreen.
#
# yambar draws a single bar, on the monitor named by `monitor:`
# in its config (the primary one when the key is absent), so a
# second screen would sit bare. Hence one yambar per output, each
# fed a generated copy of the config with `monitor:` set to that
# output (a `monitor:` in the source config is replaced, the copy
# is per output by definition). The copies are rendered next to
# the DPI-sized config auto-scale.sh produces and are regenerated
# whenever that changes, so the bars keep the sizes they had.
#
# Wallpapers: `local/wallpapers/<OUTPUT>` (one file per screen, e.g.
# `local/wallpapers/DP-1`, holding an image path or an awww colour such
# as 0x1b1b1bff) wins over `wallpapers/<OUTPUT>` in the repository, which
# in turn wins over the single `local/wallpaper` or `wallpaper` file that
# applies to every output. An output with nothing configured goes back to
# whatever awww had cached for it. RSTL_WALLPAPERS moves the per-output
# directory out of the dotfiles.
#
# Fullscreen is per output: a fullscreen window on a *visible*
# workspace hides only the bar of the output showing it, the
# other screens keep theirs, and a fullscreen window nobody can
# see is ignored. (Workspace nodes always report
# fullscreen_mode == 1, an i3 compat quirk, so only con and
# floating_con nodes count.)
#
# autostart runs this in the background, and it owns
# awww-daemon, so nothing else has to start it. By hand:
#
#   rstl_desktop.sh            supervise: react to sway events
#   rstl_desktop.sh --once     one reconcile pass, then exit
#   rstl_desktop.sh --status   what runs where, per output
#   rstl_desktop.sh --stop     stop the supervisor and every bar
#
# Bookkeeping lives in $XDG_RUNTIME_DIR/rstl.sway/desktop: bar
# pids, the wallpaper each output last got, the event fifo. It is
# wiped on logout, so a new session always starts from scratch.
# ============================================================

set -u

DOTFILES_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rstl.sway"
# the config as written in the repo, plus the DPI-sized copy
# auto-scale.sh renders from it on every start
YAMBAR_SRC="$DOTFILES_DIR/yambar/config.yml"
YAMBAR_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/rstl.sway/yambar-config.yml"
YAMBAR_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/rstl.sway/yambar"
YAMBAR_CFG="$YAMBAR_BASE"
[ -f "$YAMBAR_CFG" ] || YAMBAR_CFG="$YAMBAR_SRC"
# pids, last applied wallpapers, the event fifo
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/rstl.sway/desktop"
# The wallpaper dialog writes local/wallpaper and local/wallpapers/<OUTPUT>.
# Prefer those over the repository defaults, and keep the environment
# overrides working for tests and one-off runs.
if [ -n "${WALLPAPER_CONF:-}" ]; then
    :
elif [ -r "$DOTFILES_DIR/local/wallpaper" ]; then
    WALLPAPER_CONF="$DOTFILES_DIR/local/wallpaper"
else
    WALLPAPER_CONF="$DOTFILES_DIR/wallpaper"
fi
if [ -n "${RSTL_WALLPAPERS:-}" ]; then
    WALLPAPER_DIR="$RSTL_WALLPAPERS"
elif [ -d "$DOTFILES_DIR/local/wallpapers" ]; then
    WALLPAPER_DIR="$DOTFILES_DIR/local/wallpapers"
else
    WALLPAPER_DIR="$DOTFILES_DIR/wallpapers"
fi
# how often the loop wakes up on its own, to notice a bar that died
# or a wallpaper that was edited
WATCHDOG=10

# say it once here rather than once per sway event
bars=1
if ! command -v yambar >/dev/null 2>&1; then
    echo "rstl-desktop: no yambar, leaving the bars alone" >&2
    bars=0
elif [ ! -r "$YAMBAR_CFG" ]; then
    echo "rstl-desktop: no bar config at $YAMBAR_CFG" >&2
    bars=0
fi


# ============================================================
# sway state
# ============================================================

# both lists hold one output name per line, as sway spells them
active_outputs=""
fullscreen_outputs=""

# fill both lists. bail out (leaving the bars alone) when sway does
# not answer: an empty answer is a broken socket, not a session
# without screens - killing every bar on a hiccup would be wrong
sway_state() {
    outputs=$(swaymsg -t get_outputs -r 2>/dev/null) || return 1
    [ -n "$outputs" ] || return 1
    tree=$(swaymsg -t get_tree 2>/dev/null) || return 1
    active_outputs=$(printf '%s' "$outputs" | jq -r '
        .[] | select(.active) | .name')
    # which workspaces are on screen comes from get_workspaces: the
    # tree's workspace nodes do not carry a visible flag (sway 1.12)
    visible=$(swaymsg -t get_workspaces 2>/dev/null \
        | jq -c '[.[] | select(.visible) | .name]') || return 1
    # [] is a real answer (nothing on screen), nothing at all is not
    case "$visible" in
        '' | null) return 1 ;;
    esac
    # one entry per output showing a fullscreen window
    fullscreen_outputs=$(printf '%s' "$tree" | jq -r --argjson vis "$visible" '
        [ .nodes[]
          | select(.type == "output" and .name != "__i3")
          | select(any( .nodes[]?;
                select(.type == "workspace" and (.name | IN($vis[])))
                | any(.. | objects;
                      (.type == "con" or .type == "floating_con")
                      and .fullscreen_mode == 1)))
          | .name ]
        | .[]')
}

# exit 0 when $1 is one of the words in $2
has_word() {
    needle="$1"
    haystack="$2"
    for word in $haystack; do
        [ "$word" = "$needle" ] && return 0
    done
    return 1
}


# ============================================================
# bars
# ============================================================

# the generated config for one output
bar_cfg() {
    printf '%s/%s.yml' "$YAMBAR_DIR" "$1"
}

bar_pid_file() {
    printf '%s/bar.%s.pid' "$STATE_DIR" "$1"
}

bar_stamp_file() {
    printf '%s/bar.%s.stamp' "$STATE_DIR" "$1"
}

bar_bad_file() {
    printf '%s/bar.%s.bad' "$STATE_DIR" "$1"
}

# render the per-output config: drop any monitor: from the source
# (one copy per output, so the generated one has to win) and add
# ours right under the bar: key
render_bar_cfg() {
    out="$1"
    mkdir -p "$YAMBAR_DIR" 2>/dev/null || return 1
    awk -v out="$out" '
        /^[ \t]*monitor:/ { next }
        /^bar:[ \t]*$/ && !done {
            print
            print "  monitor: " out
            done = 1
            next
        }
        { print }
    ' "$YAMBAR_CFG" > "$(bar_cfg "$out").new" 2>/dev/null || return 1
    mv -f "$(bar_cfg "$out").new" "$(bar_cfg "$out")"
}

# the pid of the bar for one output, if it is still running. the
# pid file alone is not enough: pids get recycled, so the running
# process has to be a yambar still reading that output's config
bar_pid() {
    pid_file=$(bar_pid_file "$1")
    [ -f "$pid_file" ] || return 1
    pid=$(cat "$pid_file" 2>/dev/null)
    case "$pid" in
        '' | *[!0-9]*) return 1 ;;
    esac
    kill -0 "$pid" 2>/dev/null || return 1
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    # no cmdline readable (/proc not mounted): trust the pid file
    if [ -n "$cmdline" ]; then
        case "$cmdline" in
            *"$YAMBAR_DIR/$1.yml"*) ;;
            *) return 1 ;;
        esac
    fi
    printf '%s' "$pid"
}

start_bar() {
    out="$1"
    cfg="$2"
    yambar -c "$cfg" >/dev/null 2>&1 &
    pid=$!
    printf '%s\n' "$pid" > "$(bar_pid_file "$out")"
    # a config yambar cannot parse makes it bail out at once
    sleep 0.1
    if ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$(bar_pid_file "$out")"
        echo "rstl-desktop: yambar exited on $out, check $cfg" >&2
        return 1
    fi
}

# kill the bar of one output and wait for it to be gone, so a
# following start cannot race the teardown
stop_bar() {
    out="$1"
    pid=$(bar_pid "$out") || pid=""
    rm -f "$(bar_pid_file "$out")"
    [ -n "$pid" ] || return 0
    kill "$pid" 2>/dev/null || return 0
    i=0
    while [ "$i" -lt 50 ]; do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.02
        i=$((i + 1))
    done
    kill -9 "$pid" 2>/dev/null || true
}

# one bar per active output, hidden on the outputs that show a
# fullscreen window
reconcile_bars() {
    [ "$bars" = 1 ] || return 0
    for out in $active_outputs; do
        cfg=$(bar_cfg "$out")
        # auto-scale.sh re-rendered the base config: new config,
        # new yambar. the stamp is its checksum, not its mtime, so
        # a rewrite inside the same second still counts
        stamp=$(cksum < "$YAMBAR_CFG" 2>/dev/null | awk '{print $1 "-" $2}')
        old_stamp=$(cat "$(bar_stamp_file "$out")" 2>/dev/null)
        if [ ! -f "$cfg" ] || [ "$stamp" != "$old_stamp" ]; then
            if render_bar_cfg "$out"; then
                printf '%s' "$stamp" > "$(bar_stamp_file "$out")"
                if yambar -C -c "$cfg" >/dev/null 2>&1; then
                    rm -f "$(bar_bad_file "$out")"
                else
                    # yambar said no: remember it, so the same broken
                    # config is not re-rendered and re-blamed on every
                    # sway event. it is retried once the base config
                    # changes.
                    : > "$(bar_bad_file "$out")"
                    echo "rstl-desktop: yambar rejects $cfg" >&2
                fi
                stop_bar "$out"
            else
                echo "rstl-desktop: cannot render $cfg" >&2
            fi
        elif [ -f "$(bar_bad_file "$out")" ]; then
            continue    # broken config, leave this output bare
        fi

        if has_word "$out" "$fullscreen_outputs"; then
            stop_bar "$out"
        elif ! bar_pid "$out" >/dev/null; then
            start_bar "$out" "$cfg"
        fi
    done
}

# forget the outputs that are gone: bar down, pid and wallpaper
# state dropped, so a monitor plugged in later starts clean
drop_stale_bars() {
    for pid_file in "$STATE_DIR"/bar.*.pid; do
        [ -f "$pid_file" ] || continue
        out=${pid_file##*/bar.}
        out=${out%.pid}
        has_word "$out" "$active_outputs" && continue
        stop_bar "$out"
        rm -f "$(bar_stamp_file "$out")" "$(bar_bad_file "$out")" \
            "$STATE_DIR/wp.$out"
    done
}


# ============================================================
# wallpapers
# ============================================================

# start awww-daemon unless one is already answering. started here so
# the per-output wallpapers always have a daemon to talk to
ensure_awww() {
    command -v awww >/dev/null 2>&1 || return 1
    awww query >/dev/null 2>&1 && return 0
    # a daemon from a previous session can be around but dead
    pkill -f awww-daemon 2>/dev/null || true
    awww-daemon >/dev/null 2>&1 &
    i=0
    while [ "$i" -lt 30 ]; do
        awww query >/dev/null 2>&1 && return 0
        sleep 0.1
        i=$((i + 1))
    done
    echo "rstl-desktop: awww-daemon did not come up" >&2
    return 1
}

# the image one output should show: its own file, else the single
# wallpaper file. empty when neither names something usable
wallpaper_for() {
    img=$(read_wallpaper "$WALLPAPER_DIR/$1")
    # local/wallpapers may only contain the outputs the dialog has touched;
    # fall back to a repository per-output file, then to the global wallpaper.
    [ -n "$img" ] || img=$(read_wallpaper "$DOTFILES_DIR/wallpapers/$1")
    [ -n "$img" ] || img=$(read_wallpaper "$WALLPAPER_CONF")
    printf '%s' "$img"
}

# one wallpaper file as awww wants it: an image path (a leading ~
# is $HOME) or an 0x colour. empty when the file is missing, empty
# or points at nothing
read_wallpaper() {
    img=""
    if [ -r "$1" ]; then
        img=$(head -n1 "$1" 2>/dev/null)
        if [ "${img#\~}" != "$img" ]; then
            img="$HOME${img#\~}"
        fi
    fi
    case "$img" in
        0x*) ;;                        # a colour, taken as is
        *) [ -f "$img" ] || img="" ;;  # a path: only if it exists
    esac
    printf '%s' "$img"
}

reconcile_wallpapers() {
    for out in $active_outputs; do
        want=$(wallpaper_for "$out")
        have=$(cat "$STATE_DIR/wp.$out" 2>/dev/null)
        [ "$want" = "$have" ] && continue
        if [ -z "$want" ]; then
            # nothing configured: whatever awww had cached for this
            # output (a no-op on the first run)
            awww restore --outputs "$out" >/dev/null 2>&1 || true
            printf '<restore>' > "$STATE_DIR/wp.$out"
        elif awww img "$want" --outputs "$out" >/dev/null 2>&1; then
            printf '%s' "$want" > "$STATE_DIR/wp.$out"
        fi
    done
}


# ============================================================
# one pass over everything
# ============================================================

reconcile() {
    sway_state || return 1
    ensure_awww || true
    reconcile_bars
    drop_stale_bars
    reconcile_wallpapers
}


# ============================================================
# modes
# ============================================================

# watch sway and reconcile on every event, with a watchdog tick so
# a bar that died on its own comes back. both writers hold the fifo
# open for the whole run, so the read below never sees a premature
# end of file; when sway goes away they close and so does the loop
supervise() {
    mkdir -p "$STATE_DIR" 2>/dev/null || {
        echo "rstl-desktop: cannot create $STATE_DIR" >&2
        return 1
    }
    # a supervisor that is somehow still around (a reload whose killall
    # raced, a second manual start) would fight us over the same bars:
    # retire it first, and wait for it to be really gone
    old=$(cat "$STATE_DIR/supervisor.pid" 2>/dev/null)
    if [ -n "$old" ] && [ "$old" != "$$" ] && kill -0 "$old" 2>/dev/null; then
        i=0
        while [ "$i" -lt 150 ] && kill -0 "$old" 2>/dev/null; do
            # again every second, in case the first one arrived while
            # it was busy
            [ $((i % 50)) -eq 0 ] && kill "$old" 2>/dev/null
            sleep 0.02
            i=$((i + 1))
        done
        kill -0 "$old" 2>/dev/null &&
            echo "rstl-desktop: supervisor $old ignored the request to stop" >&2
    fi

    # the fifo carries our pid: a supervisor we are retiring cannot
    # unlink the one we are about to use
    fifo="$STATE_DIR/events.$$"
    mkfifo -m 600 "$fifo" 2>/dev/null || {
        echo "rstl-desktop: cannot create $fifo" >&2
        return 1
    }
    # something that is not a fifo would give the loop below an instant
    # end of file and the supervisor would quit right away
    [ -p "$fifo" ] || {
        echo "rstl-desktop: $fifo is not a fifo" >&2
        return 1
    }
    sub_pid=
    tick_pid=
    # the pid file is only ours to remove while it still names us, so a
    # supervisor that lingers cannot take the successor's entry with it
    trap 'kill "${sub_pid:-}" "${tick_pid:-}" 2>/dev/null
          rm -f "$fifo"
          if [ "$(cat "$STATE_DIR/supervisor.pid" 2>/dev/null)" = "$$" ]; then
              rm -f "$STATE_DIR/supervisor.pid"
          fi' EXIT INT TERM
    printf '%s\n' "$$" > "$STATE_DIR/supervisor.pid"

    swaymsg -t subscribe -m '["output", "window", "workspace"]' > "$fifo" &
    sub_pid=$!
    (
        while :; do
            sleep "$WATCHDOG"
            printf 'tick\n' > "$fifo" 2>/dev/null || break
        done
    ) &
    tick_pid=$!

    # adopt or spawn according to the current state right away, e.g. a
    # reload that happens while a window is already fullscreen. waiting
    # for the first event would leave a barless screen until something
    # happened on it
    reconcile || true

    while IFS= read -r _event; do
        reconcile
    done < "$fifo"
}

# adopt or spawn according to the current state, e.g. a reload that
# happens while a window is already fullscreen, then stop
once() {
    mkdir -p "$STATE_DIR" 2>/dev/null || {
        echo "rstl-desktop: cannot create $STATE_DIR" >&2
        return 1
    }
    reconcile
}

status() {
    pid=$(cat "$STATE_DIR/supervisor.pid" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "supervisor: running (pid $pid)"
    else
        echo "supervisor: not running"
    fi

    sway_state || {
        echo "sway: not answering"
        return 1
    }
    for out in $active_outputs; do
        line="  $out"
        if running=$(bar_pid "$out"); then
            line="$line  bar up (pid $running)"
        elif has_word "$out" "$fullscreen_outputs"; then
            line="$line  bar hidden (fullscreen)"
        else
            line="$line  bar down"
        fi
        echo "$line  wallpaper $(wallpaper_for "$out" | sed 's/^$/<restore>/')"
    done
    # bars left over for outputs that are gone
    for pid_file in "$STATE_DIR"/bar.*.pid; do
        [ -f "$pid_file" ] || continue
        out=${pid_file##*/bar.}
        out=${out%.pid}
        has_word "$out" "$active_outputs" && continue
        echo "  $out  bar stale (output gone)"
    done
}

stop() {
    pid=$(cat "$STATE_DIR/supervisor.pid" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        i=0
        while [ "$i" -lt 50 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 0.02
            i=$((i + 1))
        done
    fi
    for pid_file in "$STATE_DIR"/bar.*.pid; do
        [ -f "$pid_file" ] || continue
        out=${pid_file##*/bar.}
        out=${out%.pid}
        stop_bar "$out"
    done
    case "$STATE_DIR" in
        */desktop) rm -rf "$STATE_DIR" ;;
    esac
}

usage() {
    # the header comment above, uncommented: everything up to the
    # first line that is neither a comment nor blank
    awk 'NR == 1 { next }
         /^[[:space:]]*$/ { next }
         /^# =/ { next }
         /^#/ { sub(/^# ?/, ""); print; next }
         { exit }' "$0"
}

case "${1:-}" in
    '') supervise ;;
    --once) once ;;
    --status) status ;;
    --stop) stop ;;
    --help | -h) usage ;;
    *)
        echo "rstl-desktop: unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
esac
