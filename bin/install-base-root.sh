#!/bin/sh
# rstl.sway dotfiles installer for Arch Linux (base, root-friendly)
#
# Usage:
#   bin/install-base-root.sh                  run every step, confirming each one
#   bin/install-base-root.sh --yes            run every step without asking
#   bin/install-base-root.sh --no-cleanup     every step except the last one (cleanup)
#   bin/install-base-root.sh --firefox        bundle the firefox browser
#   bin/install-base-root.sh --help           show the underlying installer help
#
# Root variant of bin/install-base.sh: installs into root's home (/root), runs
# privileged commands directly and does not use sudo. It must be started as
# root (a root shell, container or rootfs build); use the normal installer for
# a regular user account.

set -eu

if [ "$(id -u)" -ne 0 ]; then
    case " $* " in
        *" --help "*|*" -h "*) ;;
        *) echo "install-base-root.sh: must be run as root" >&2; exit 1 ;;
    esac
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RSTL_ROOT=1
export RSTL_ROOT
exec sh "$SCRIPT_DIR/install-base.sh" --root "$@"
