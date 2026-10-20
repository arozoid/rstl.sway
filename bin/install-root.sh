#!/bin/sh
# rstl.sway dotfiles installer for Arch Linux (full, root-friendly)
#
# Usage:
#   bin/install-root.sh                  run every step, confirming each one
#   bin/install-root.sh --yes            run every step without asking
#   bin/install-root.sh --no-cleanup     every step except the last one (cleanup)
#   bin/install-root.sh --program mouse  pick the program configuration
#   bin/install-root.sh --firefox        bundle the firefox browser
#   bin/install-root.sh --help           show the underlying installer help
#
# Root variant of bin/install.sh: installs into root's home (/root), runs
# privileged commands directly and does not use sudo. It must be started as
# root (a root shell, container or rootfs build); use the normal installer for
# a regular user account.

set -eu

if [ "$(id -u)" -ne 0 ]; then
    case " $* " in
        *" --help "*|*" -h "*) ;;
        *) echo "install-root.sh: must be run as root" >&2; exit 1 ;;
    esac
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RSTL_ROOT=1
export RSTL_ROOT
exec sh "$SCRIPT_DIR/install.sh" --root "$@"
