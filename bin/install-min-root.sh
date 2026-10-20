#!/bin/sh
# rstl.sway dotfiles installer for Arch Linux (minimal, root-friendly)
#
# Usage:
#   bin/install-min-root.sh                  run every step, confirming each one
#   bin/install-min-root.sh --yes            run every step without asking
#   bin/install-min-root.sh --no-cleanup     every step except the last one (cleanup)
#   bin/install-min-root.sh --program mouse  pick the program's file manager
#   bin/install-min-root.sh --firefox        bundle the firefox browser
#   bin/install-min-root.sh --help           show the underlying installer help
#
# Root variant of bin/install-min.sh: installs into root's home (/root), runs
# privileged commands directly and does not use sudo. It must be started as
# root (a root shell, container or rootfs build); use the normal installer for
# a regular user account.

set -eu

if [ "$(id -u)" -ne 0 ]; then
    case " $* " in
        *" --help "*|*" -h "*) ;;
        *) echo "install-min-root.sh: must be run as root" >&2; exit 1 ;;
    esac
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RSTL_ROOT=1
export RSTL_ROOT
exec sh "$SCRIPT_DIR/install-min.sh" --root "$@"
