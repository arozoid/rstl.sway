#!/usr/bin/env sh
# Invoked by xdg-desktop-portal-termfilechooser. Dispatches to the first
# terminal file manager that is installed, in this order:
#   superfile (spf) -> rovr -> lf
# This repo installs no file manager; the chooser uses whichever is present.
#
# For the termfilechooser I/O contract read xdg-desktop-portal-termfilechooser(5).

multiple="$1"
directory="$2"
save="$3"
path="$4"
out="$5"
debug="$6"

set -e

if [ "$debug" = 1 ]; then
    set -x
fi

termcmd="${TERMCMD:-foot -a termfilechooser -T 'terminal filechooser'}"

fm=
for c in spf rovr lf; do
    if command -v "$c" >/dev/null 2>&1; then
        fm=$c
        break
    fi
done

case "$fm" in
    spf)
        # superfile: --chooser-file writes the focused item's path (file OR
        # directory) to $out on the open key, then quits. Used for every mode,
        # matching the official xdg-desktop-portal-termfilechooser contrib
        # wrapper. (--print-last-dir is NOT used: it only echoes the dir you
        # were in when pressing the *quit* key, i.e. wrong selection UX.)
        args='--chooser-file'
        ;;
    rovr)
        # rovr can't open a file that doesn't exist yet (save mode), so start
        # in its parent directory instead.
        if [ "$save" = "1" ] && [ ! -e "$path" ]; then
            path="$(dirname "$path")"
        fi
        args='--chooser-file'
        [ "$directory" = "1" ] && args='--cwd-file'
        ;;
    lf)
        args='-selection-path'
        [ "$directory" = "1" ] && args='-last-dir-path'
        ;;
    *)
        printf '%s\n' "fm-wrapper.sh: no terminal file manager found (tried superfile, rovr, lf)" >&2
        exit 1
        ;;
esac

escaped_out=$(printf "%s" "$out" | sed 's/"/\\"/g')
escaped_path=$(printf "%s" "$path" | sed 's/"/\\"/g')

# The portal hands us a temp "out" file (by default
# /tmp/termfilechooser/<uid>.portal) that the file manager must write the
# selected path into, but the portal never creates that directory. Without
# it, superfile's chooser write fails and it silently falls back to launching
# its editor/xdg-open instead of selecting. Make sure the parent exists.
mkdir -p "$(dirname "$out")"

command="$termcmd $fm $args \"$escaped_out\" \"$escaped_path\""
sh -c "$command"
