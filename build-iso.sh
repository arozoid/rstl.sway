#!/bin/sh
# build-iso.sh - build a rstl.sway Archiso live/install medium.
#
# Usage:
#   ./build-iso.sh                 build with defaults
#   ./build-iso.sh -w <work>       set the mkarchiso work directory
#   ./build-iso.sh -o <out>        set the output directory (ISO lands here)
#   ./build-iso.sh --help          show usage
#
# The build stages this dotfiles repo into the profile's airootfs
# (root/.config/rstl.sway) so the live image boots straight into the
# rstl.sway environment, then runs mkarchiso.

set -eu

REPO="$(cd "$(dirname "$0")" && pwd)"
PROFILE="$REPO/archiso"
ARCH="$REPO/archiso/airootfs/root"

WORK="$REPO/build_work"
OUT="$REPO/build_output"

usage() {
    cat <<'EOF'
build-iso.sh - build a rstl.sway Archiso live/install medium

Usage:
  ./build-iso.sh [-w <workdir>] [-o <outdir>]

  -w <workdir>  mkarchiso work directory (default: ./build_work)
  -o <outdir>   output directory for the ISO (default: ./build_output)
  -h, --help    show this help

Must be run as root (mkarchiso needs it). Requires 'mkarchiso' and the
profile at ./archiso.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -w) WORK="$2"; shift 2 ;;
        -o) OUT="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "build-iso: unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "build-iso: must be run as root (mkarchiso needs it)" >&2
    exit 1
fi

if ! command -v mkarchiso >/dev/null 2>&1; then
    echo "build-iso: mkarchiso not found (install 'archiso')" >&2
    exit 1
fi

if [ ! -f "$PROFILE/profiledef.sh" ]; then
    echo "build-iso: profile not found at $PROFILE" >&2
    exit 1
fi

CFG="$ARCH/.config/rstl.sway"

# ---- stage the dotfiles into the profile airootfs ----
echo "build-iso: staging dotfiles into $CFG"
mkdir -p "$CFG"
rm -rf "$CFG"
# copy this repo, minus anything generated during the build
# (keeps install.sh / install-min.sh / simple-rootfs.sh available in the live
# image so one can install to disk straight from the ISO)
tar \
    -C "$REPO" \
    --exclude=.git \
    --exclude=archiso \
    --exclude=build_work \
    --exclude=build_output \
    -cf - . \
  | tar -C "$ARCH" -xf -

cleanup() {
    echo "build-iso: cleaning staged dotfiles"
    rm -rf "$CFG"
}
trap cleanup EXIT

mkdir -p "$WORK" "$OUT"

echo "build-iso: running mkarchiso"
echo "  profile: $PROFILE"
echo "  work:    $WORK"
echo "  out:     $OUT"

mkarchiso -w "$WORK" -o "$OUT" "$PROFILE"

echo
echo "build-iso: done."
ls -lh "$OUT"/*.iso 2>/dev/null || true
