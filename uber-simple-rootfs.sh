#!/bin/sh
# simple-rootfs.sh - build a minimal rstl.sway rootfs with pacstrap
#
# Usage:
#   ./simple-rootfs.sh [target] [-a v1|v2|v3|v4|auto]
#
#   target    directory to bootstrap into.
#               - a bare name (no '/', e.g. 'rstl') creates ./rstl in the
#                 current directory.
#               - a path containing '/' is used as-is (absolute or relative).
#               - if omitted, prompts (defaults to 'rstl').
#   -a, --arch LEVEL
#             x86_64 microarchitecture level for the CachyOS pacman.conf:
#               v1|v2|v3|v4  use that exact config, or
#               auto          auto-detect the host's highest supported level
#               if omitted: interactive when on a TTY, else 'auto'.
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

# ---------------------------------------------------------------------------
# Colors / styling (light purple for headers and non-command status output)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_RESET='\033[0m'
    C_BOLD='\033[1m'
    C_DIM='\033[2m'
    C_PURPLE='\033[95m'
    C_CYAN='\033[36m'
    C_RED='\033[31m'
else
    C_RESET='' C_BOLD='' C_DIM='' C_PURPLE='' C_CYAN='' C_RED=''
fi

# header
header() { printf "\n${C_BOLD}${C_PURPLE}== %s${C_RESET}\n" "$*"; }
# non-command status line
info()  { printf "${C_PURPLE}:: %s${C_RESET}\n" "$*"; }
# error
die()   { printf "${C_RED}error: %s${C_RESET}\n" "$*" >&2; exit 1; }

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
  ./simple-rootfs.sh [target] [-a v1|v2|v3|v4|auto]

  target    directory to bootstrap into.
              - a bare name (no '/', e.g. 'rstl') creates ./rstl in the
                current directory.
              - a path containing '/' is used as-is.
              - if omitted, prompts (defaults to 'rstl').
  -a, --arch LEVEL
            x86_64 microarchitecture level for the CachyOS pacman.conf.
              v1|v2|v3|v4  use that exact config, or
              auto         auto-detect (default when not a TTY).

Steps:
  1. pacstrap a minimal base system (base + sudo + git) into the target.
  2. Copy this dotfiles repository (and install-uber-min.sh) into the rootfs.
  3. arch-chroot into it and run install-uber-min.sh as root to set up the
     rstl.sway environment.

Requires: root privileges, pacstrap + arch-chroot (arch-install-scripts),
and a configured pacman mirror.
EOF
}

# ---- parse arguments ----
target=""
requested_arch=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -a|--arch)
            [ "$#" -ge 2 ] || die "--arch requires an argument (v1|v2|v3|v4|auto)"
            requested_arch="$2"; shift 2 ;;
        --arch=*)
            requested_arch="${1#*=}"; shift ;;
        -*) die "unknown option: $1" ;;
        *) target="$1"; shift ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    die "must be run as root (pacstrap needs it)"
fi

for cmd in pacstrap arch-chroot; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        die "'$cmd' not found (install arch-install-scripts)"
    fi
done

# ---- resolve target directory ----
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

# Auto-detect the host x86_64 microarchitecture level (v1..v4). v1/v2 have no
# optimized CachyOS repo, so both fall back to the generic [cachyos] config.
# Only v3/v4 differ.
detect_level() {
    # probe supported levels via the dynamic loader, which enumerates the
    # highest x86-64-vN level the host CPU supports
    local _l
    _l="$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null || /lib64/ld-linux-x86-64.so.2 --help 2>/dev/null)"
    case "$_l" in
        *'x86-64-v4 (supported, searched)'*) echo 4 ;;
        *'x86-64-v3 (supported, searched)'*) echo 3 ;;
        *'x86-64-v2 (supported, searched)'*) echo 2 ;;
        *) echo 1 ;;
    esac
}

# Choose the x86_64 level to use: explicit -a wins; otherwise interact when on
# a TTY; otherwise auto-detect.
ask_level() {
    case "${requested_arch:-}" in
        v1|v2|v3|v4) echo "${requested_arch#v}"; return 0 ;;
        auto) detect_level; return 0 ;;
    esac
    if [ -t 0 ]; then
        printf "${C_BOLD}Select CachyOS x86-64 level${C_RESET} [%s]  " "${C_BOLD}auto${C_RESET}"
        read -r ans || :
        case "${ans:-auto}" in
            ""|auto) detect_level ;;
            1|v1) echo 1 ;;
            2|v2) echo 2 ;;
            3|v3) echo 3 ;;
            4|v4) echo 4 ;;
            *) printf "${C_DIM}invalid choice, using auto${C_RESET}\n"; detect_level ;;
        esac
    else
        detect_level
    fi
}

arch_level="$(ask_level)"
pacman_conf_name="pacman-v${arch_level}.conf"
if [ ! -f "$repo_root/$pacman_conf_name" ]; then
    die "missing $pacman_conf_name for x86-64-v$arch_level"
fi

info "detected/selected x86-64-v$arch_level -> using $pacman_conf_name"
header "Bootstrapping base system into '$target'"
mkdir -p "$target"
pacstrap -C "$repo_root/$pacman_conf_name" -K "$target" base sudo git

# marker so install-uber-min.sh knows it is running inside a rootfs and may run
# as root (it otherwise refuses to run as root on a normal host).
touch "$target/etc/.rstl-sway-rootfs"

# add the matching cachyos pacman.conf
cp -a "$repo_root/$pacman_conf_name" "$target/etc/pacman.conf"

# ---- 2. copy this repository into the rootfs ----
install_dir="$target/root/.config/rstl.sway"
info "copying dotfiles into '$install_dir'"
mkdir -p "$install_dir"
cp -a "$repo_root"/. "$install_dir"/
chmod +x "$install_dir"/install-uber-min.sh "$install_dir"/scripts/*.sh 2>/dev/null || true

# also add to /etc/skel
info "copying dotfiles into /etc/skel/.config/rstl.sway"
mkdir -p "/etc/skel/.config/rstl.sway"
cp -a "$repo_root"/. "/etc/skel/.config/rstl.sway"

# ---- 3. run install-uber-min.sh inside the rootfs ----
header "Entering rootfs to run install-uber-min.sh"
if ! mountpoint -q "$target"; then
    info "bind-mounting '$target' onto itself (pacman needs a root mountpoint)"
    mount --bind "$target" "$target"
    SELF_BIND=1
fi
arch-chroot "$target" /bin/sh /root/.config/rstl.sway/install-uber-min.sh

echo "simple-rootfs: done."
