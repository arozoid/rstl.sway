#!/bin/sh
# build-iso.sh - build rstl.sway Archiso live/install media.
#
# Builds one or more ISOs, one per x86_64 CachyOS microarchitecture level.
# Each variant (v1..v4) uses its matching pacman-vN.conf as the archiso
# profile pacman.conf, so the airootfs is installed against CachyOS repos for
# that CPU level (v1/v2 -> generic [cachyos], v3/v4 -> [cachyos-v3/-v4]).
#
# Usage:
#   ./build-iso.sh                  build v1, v2, v3 and v4 ISOs in parallel
#   ./build-iso.sh v1 v3            build only v1 and v3
#   ./build-iso.sh -w DIR -o DIR    set work/output root dirs
#   ./build-iso.sh -h               show this help
#
# Output: <out>/rstlsway-v<N>-<version>-x86_64.iso for each variant built.
#
# Must be run as root (mkarchiso needs it). Requires 'mkarchiso', 'rust'
# (for the rstl-inst TUI) and network access to fetch CachyOS mirrors.

set -eu

REPO="$(cd "$(dirname "$0")" && pwd)"
PROFILE="$REPO/archiso"
ARCH="$PROFILE/airootfs/root"
AIROOT="$PROFILE/airootfs"

WORK="$REPO/build_work"
OUT="$REPO/build_output"
WANT_VARIANTS=""
DEBUG=0

RSTL_REPO_CONF='
# rstl.sway custom repository (rstlpk, dssd, yambar, googledot-black, ...)
[rstl-repo]
SigLevel = Optional TrustAll
Server = https://arozoid.github.io/rstl.repo
'

usage() {
    cat <<EOF
build-iso.sh - build rstl.sway Archiso live/install media

Usage:
  ./build-iso.sh [v1|v2|v3|v4 ...]
  ./build-iso.sh [-w <workdir>] [-o <outdir>] [v1|v2|v3|v4 ...]

  v1..v4      which CachyOS microarchitecture variants to build.
              If none given, builds all of: v1 v2 v3 v4 (each in its own
              background job, in parallel).
  -w <dir>    work root (each variant gets <dir>/v<N>, default: ./build_work)
  -o <dir>    output root (ISOs land in <dir>, default: ./build_output)
  -d, --debug keep the work tree and print pacstrap hints if a build fails
  -h, --help  show this help

Must be run as root. Requires 'mkarchiso', 'rust' (rstl-inst TUI) and the
profile at ./archiso.
EOF
}

# ---- color / status (light purple headers, red errors) ----
C_RESET='' C_BOLD='' C_PURPLE='' C_RED=''
if [ -t 1 ]; then
    C_RESET='\033[0m' C_BOLD='\033[1m' C_PURPLE='\033[95m' C_RED='\033[31m'
fi
header() { printf "\n${C_BOLD}${C_PURPLE}== %s${C_RESET}\n" "$*"; }
info()   { printf "${C_PURPLE}:: %s${C_RESET}\n" "$*"; }
die()    { printf "${C_RED}error: %s${C_RESET}\n" "$*" >&2; exit 1; }

# ---- parse arguments ----
while [ "$#" -gt 0 ]; do
    case "$1" in
        -w) WORK="$2"; shift 2 ;;
        -o) OUT="$2"; shift 2 ;;
        -d|--debug) DEBUG=1; shift ;;
        -h|--help) usage; exit 0 ;;
        v1|v2|v3|v4) WANT_VARIANTS="$WANT_VARIANTS $1"; shift ;;
        *) echo "build-iso: unknown argument: $1" >&2; usage; exit 1 ;;
    esac
done
# dedupe + canonical order; default to all four when none requested
if [ -z "$WANT_VARIANTS" ]; then
    VARIANTS="v1 v2 v3 v4"
else
    VARIANTS="$(printf '%s\n' $WANT_VARIANTS | sort -u | tr '\n' ' ' | sed 's/ *$//')"
fi

if [ "$(id -u)" -ne 0 ]; then
    die "must be run as root (mkarchiso needs it)"
fi
if ! command -v mkarchiso >/dev/null 2>&1; then
    die "mkarchiso not found (install 'archiso')"
fi
if [ ! -f "$PROFILE/profiledef.sh" ]; then
    die "profile not found at $PROFILE"
fi

# ---- git submodules (nvim, ranger, rstlpk, rstl-inst) ----
git submodule update --init --recursive

# ---- build the rstl-inst submodule into the airootfs ----
build_rstl_inst() {
    BIN="$AIROOT/usr/local/bin/rstl-inst"
    if [ -x "$BIN" ]; then
        echo "build-iso: using pre-injected $BIN"
        return 0
    fi
    echo "build-iso: building rstl-inst"
    if command -v cargo >/dev/null 2>&1 && [ -d "$REPO/rstl-inst" ]; then
        (
            cd "$REPO/rstl-inst"
            cargo build --release
        ) && {
            mkdir -p "$(dirname "$BIN")"
            cp "$REPO/rstl-inst/target/release/rstl-inst" "$BIN"
            chmod 755 "$BIN"
            echo "build-iso: injected $BIN"
        }
    else
        echo "build-iso: WARN cargo unavailable or no rstl-inst checkout; skipping TUI build" >&2
    fi
}
build_rstl_inst

# ---- stage the dotfiles into the profile airootfs (shared by all variants) ----
CFG="$ARCH/.config/rstl.sway"
echo "build-iso: staging dotfiles into $CFG"
rm -rf "$CFG"
mkdir -p "$CFG"
tar \
    -C "$REPO" \
    --exclude=.git \
    --exclude=archiso \
    --exclude=build_work \
    --exclude=build_output \
    --exclude=rstl-inst/target \
    -cf - . \
  | tar -C "$CFG" -xf -

copy_repo_cleanup() {
    echo "build-iso: cleaning staged dotfiles"
    rm -rf "$CFG"
}
# In --debug, leave everything (staged dotfiles, work trees) intact for
# inspection instead of tearing it down on exit.
if [ "$DEBUG" -eq 0 ]; then
    trap copy_repo_cleanup EXIT
else
    trap 'echo "build-iso: [debug] leaving work tree (+ staged dotfiles) in place"' EXIT
fi

# ---- generate a per-variant archiso profile (symlinks + tailored pacman.conf) ----
# $1 = variant ("v1".."v4"), $2 = destination profile dir
gen_profile() {
    v="$1"; dst="$2"
    num="${v#v}"
    vcache="$WORK/$v/cache"
    mkdir -p "$dst" "$vcache"
    # symlink the heavy/directory resources that are identical across variants
    ln -sfn "$PROFILE/airootfs" "$dst/airootfs"
    ln -sfn "$PROFILE/grub"     "$dst/grub"
    ln -sfn "$PROFILE/syslinux" "$dst/syslinux"
    ln -sfn "$PROFILE/packages.x86_64" "$dst/packages.x86_64"
    # profiledef.sh, but with per-variant iso_name/iso_label (the date-of-build
    # logic and the rest of the line are preserved verbatim)
    sed -e "s/^iso_name=\"rstlsway\"/iso_name=\"rstlsway-$v\"/" \
        -e "s/^iso_label=\"RSTLSWAY_/iso_label=\"RSTLSWAY_${num}_/" \
        "$PROFILE/profiledef.sh" > "$dst/profiledef.sh"
    # Tailor the variant pacman.conf for the ISO build:
    #   o A per-variant CacheDir so parallel variant builds never race on the
    #     shared host /var/cache/pacman/pkg (a truncation race is what corrupts
    #     .db/.db.sig mid-sync and shows up as "GPGME error: No data").
    #   o [cachyos*] repos get SigLevel = Optional TrustAll (a deterministic
    #     fallback if the CachyOS key is not yet trusted) and an inline Server
    #     (so pacman-conf on the build HOST does not fail on a missing
    #     cachyos-mirrorlist Include).
    #   o [core]/[extra]/[multilib] keep Include=/etc/pacman.d/mirrorlist,
    #     which exists on the host via pacman-mirrorlist.
    #   o append the rstl.repo custom repo (absent from pacman-vN.conf), which
    #     provides rstlpk, dssd, yambar, googledot-black, ...
    awk -v cache="$vcache" '
        /^\[options\]/ { print; print "CacheDir = " cache; next }
        /^\[cachyos/ { print; print "SigLevel = Optional TrustAll"; inserver=1; next }
        inserver && /^Include = / && $3 ~ /cachyos/ { print "Server = https://mirror.cachyos.org/repo/x86_64/$repo"; inserver=0; next }
        { inserver=0; print }
    ' "$REPO/pacman-v${num}.conf" > "$dst/pacman.conf"
    printf '%b\n' "$RSTL_REPO_CONF" >> "$dst/pacman.conf"
    info "generated variant profile for $v -> $dst"
}

# ---- build a single variant (runs as a background job) ----
# $1 = variant ("v1".."v4")
build_variant() {
    v="$1"
    vwork="$WORK/$v/work"; vprof="$WORK/$v/profile"; vout="$WORK/$v/out"
    header "building $v ISO"
    mkdir -p "$vwork" "$vout"
    gen_profile "$v" "$vprof"
    mkarchiso -w "$vwork" -o "$vout" "$vprof"
    iso="$(ls "$vout"/*.iso 2>/dev/null | head -1)"
    if [ -n "$iso" ]; then
        mkdir -p "$OUT"
        cp -f "$iso" "$OUT/"
        echo "build-iso: $v -> $OUT/$(basename "$iso")"
    else
        echo "build-iso: WARN $v produced no ISO (see $vwork)" >&2
    fi
}

mkdir -p "$WORK" "$OUT"

# ---- seed the CachyOS admin key into the airootfs pacman keyring ----
# The chroot's pacman verifies the cachyos .db/.db.sig against
# /etc/pacman.d/gnupg during pacstrap. It starts with only the Arch key, so
# import + locally sign the CachyOS key here (best-effort; the generated
# configs also use SigLevel = Optional TrustAll as a fallback, so a failure
# here must not abort the build).
seed_cachyos_key() {
    gdir="$AIROOT/etc/pacman.d/gnupg"
    if [ -d "$gdir" ]; then
        echo "build-iso: cachyos key already seeded in $gdir"
        return 0
    fi
    if ! command -v gpg >/dev/null 2>&1; then
        echo "build-iso: WARN gpg absent; skipping cachyos key seed" >&2
        return 0
    fi
    echo "build-iso: seeding CachyOS admin key into $gdir"
    mkdir -p "$gdir" && chmod 700 "$gdir"
    if GNUPGHOME="$gdir" gpg --batch --keyserver keyserver.ubuntu.com --recv-keys F3B607488DB35A47 2>/dev/null \
        && GNUPGHOME="$gdir" gpg --batch --lsign-key F3B607488DB35A47 2>/dev/null; then
        echo "build-iso: cachyos key seeded"
    else
        echo "build-iso: WARN could not seed cachyos key (relying on SigLevel=Optional TrustAll)" >&2
        rm -rf "$gdir"
    fi
}
seed_cachyos_key

# ---- launch the requested variants in parallel ----
pids=""
for v in $VARIANTS; do
    build_variant "$v" &
    pids="$pids $!"
done

rc=0
for p in $pids; do
    wait "$p" || rc=1
done

if [ "$rc" -ne 0 ]; then
    if [ "$DEBUG" -eq 1 ]; then
        {
            echo "error: at least one variant build failed" >&2
            echo "The work tree is preserved for inspection:" >&2
            echo "  pacstrap chroots:  $WORK/v*/work/x86_64/airootfs" >&2
            echo "  per-variant log:   examine the failed variant's output above" >&2
            echo "To see which pacman hook failed, re-run that variant with the" >&2
            echo "full transcript (build-iso.sh already prints pacstrap output)." >&2
        }
    else
        die "at least one variant build failed"
    fi
    exit 1
fi
echo
echo "build-iso: done."
ls -lh "$OUT"/*.iso 2>/dev/null || true