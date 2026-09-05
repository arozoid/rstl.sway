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
        # superfile: -chooser-file writes the opened file's path on exit;
        # -print-last-dir prints the last browsed dir to stdout (directory
        # mode redirects it into $out).
        args='-chooser-file'
        [ "$directory" = "1" ] && args='-print-last-dir'
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
command="$termcmd $fm $args \"$escaped_out\" \"$escaped_path\""

if [ "$fm" = spf ] && [ "$directory" = "1" ]; then
    # superfile directory mode: capture the printed last dir
    sh -c "$command" > "$out"
else
    sh -c "$command"
fi