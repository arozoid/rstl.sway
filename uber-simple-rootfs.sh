#!/bin/sh
# simple-rootfs.sh - build a minimal rstl.sway rootfs with pacstrap
#
# Usage:
#   ./simple-rootfs.sh [target]
#
#   target    directory to bootstrap into.
#               - a bare name (no '/', e.g. 'rstl') creates ./rstl in the
#                 current directory.
#               - a path containing '/' is used as-is (absolute or relative).
#               - if omitted, prompts (defaults to 'rstl').
#
# Steps:
#   1. pacstrap a minimal base system (base + sudo + git) into the target.
#   2. Copy this dotfiles repository (and install-uber-min.sh) into the rootfs.
#   3. arch-chroot into it and run install-uber-min.sh as root to set up the
#      rstl.sway environment.
#
# Requires: root privileges, pacstrap + arch-chroot (arch-install-scripts),
# and a configured pacman mirror.

set -eu

SELF_BIND=0
cleanup() {
    if [ "$SELF_BIND" -eq 1 ]; then
        echo "simple-rootfs: unmounting '$target'"
        umount "$target" 2>/dev/null || true
    fi
}
trap cleanup EXIT

usage() {
    cat <<'EOF'
simple-rootfs.sh - build a minimal rstl.sway rootfs with pacstrap

Usage:
  ./simple-rootfs.sh [target]

  target    directory to bootstrap into.
              - a bare name (no '/', e.g. 'rstl') creates ./rstl in the
                current directory.
              - a path containing '/' is used as-is.
              - if omitted, prompts (defaults to 'rstl').

Steps:
  1. pacstrap a minimal base system (base + sudo + git) into the target.
  2. Copy this dotfiles repository (and install-uber-min.sh) into the rootfs.
  3. arch-chroot into it and run install-uber-min.sh as root to set up the
     rstl.sway environment.

Requires: root privileges, pacstrap + arch-chroot (arch-install-scripts),
and a configured pacman mirror.
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "simple-rootfs: must be run as root (pacstrap needs it)" >&2
    exit 1
fi

for cmd in pacstrap arch-chroot; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "simple-rootfs: '$cmd' not found (install arch-install-scripts)" >&2
        exit 1
    fi
done

# ---- resolve target directory ----
target="${1:-}"
if [ -z "$target" ]; then
    printf 'Enter target directory [rstl]: '
    read -r ans || :
    target="${ans:-rstl}"
fi

case "$target" in
    /|*/*) ;;                # absolute path, or contains a '/' -> use as-is
    *) target="./$target" ;; # bare name -> current directory
esac

# ---- 1. bootstrap a minimal base system ----
repo_root="$(cd "$(dirname "$0")" && pwd)"

echo "simple-rootfs: bootstrapping base system into '$target'"
mkdir -p "$target"
pacstrap -C "pacman.conf" -K "$target" base sudo git

# marker so install-uber-min.sh knows it is running inside a rootfs and may run
# as root (it otherwise refuses to run as root on a normal host).
touch "$target/etc/.rstl-sway-rootfs"

# ---- 2. copy this repository into the rootfs ----
install_dir="$target/root/.config/rstl.sway"
echo "simple-rootfs: copying dotfiles into '$install_dir'"
mkdir -p "$install_dir"
cp -a "$repo_root"/. "$install_dir"/
chmod +x "$install_dir"/install-uber-min.sh "$install_dir"/scripts/*.sh 2>/dev/null || true

# also add to /etc/skel
echo "simple-rootfs: copying dotfiles into /etc/skel/.config/rstl.sway"
mkdir -p "/etc/skel/.config/rstl.sway"
cp -a "$repo_root"/. "/etc/skel/.config/rstl.sway"

# ---- 3. run install-uber-min.sh inside the rootfs ----
echo "simple-rootfs: entering rootfs to run install-uber-min.sh"
if ! mountpoint -q "$target"; then
    echo "simple-rootfs: bind-mounting '$target' onto itself (pacman needs a root mountpoint)"
    mount --bind "$target" "$target"
    SELF_BIND=1
fi
arch-chroot "$target" /bin/sh /root/rstl.sway/install-uber-min.sh

echo "simple-rootfs: done."
