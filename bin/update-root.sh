#!/bin/sh
# rstl.sway updater (root-friendly)
#
# Usage:
#   bin/update-root.sh                          update this root installation
#   bin/update-root.sh --yes                    do not ask for confirmation
#   bin/update-root.sh --edition install-min    update a specific edition
#   bin/update-root.sh --help                   show the underlying updater help
#
# Root variant of bin/update.sh: keeps the installation in root's home (/root),
# runs privileged commands directly and does not use sudo. It must be started as
# root (a root shell, container or rootfs build); use bin/update.sh for a
# regular user account.

set -eu

if [ "$(id -u)" -ne 0 ]; then
    case " $* " in
        *" --help "*|*" -h "*) ;;
        *) echo "update-root.sh: must be run as root" >&2; exit 1 ;;
    esac
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RSTL_ROOT=1
export RSTL_ROOT
exec sh "$SCRIPT_DIR/update.sh" --root "$@"
