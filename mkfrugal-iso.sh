#!/bin/sh
# mkfrugal-iso.sh - turn a mkfrugal-rstl.sh frugal directory into a bootable
# grub2 ISO (BIOS + UEFI hybrid), for use with w_bootfrom=LABEL=<vol>=/<name>.
#
# Usage:
#   ./mkfrugal-iso.sh -d <frugal-dir> [-o <out.iso>] [-l LABEL] [-n NAME]
#                     [--source-root <iso-tree>]
#
#   -d, --dir DIR      frugal directory produced by mkfrugal-rstl.sh
#   -o, --output FILE  output ISO (default: <name>.iso next to the frugal dir)
#   -l, --label LABEL  ISO volume label (default: RSTLSW; <=32 chars, upper)
#   -n, --name NAME    subdirectory the frugal lands in on the ISO
#                      (default: basename of DIR)
#   -S, --source-root DIR
#                      DIR is already an ISO tree containing ./<name> (the
#                      frugal was built inside it). Skips copying the frugal
#                      into a staging tree; only boot/grub/grub.cfg is added.
#                      NOTE: by default the frugal's 07rootfs/ dir is squashed
#                      to 07rootfs.sfs in place; --no-squash-rootfs leaves it.
#       --no-squash-rootfs  keep the rootfs uncompressed (07rootfs/ dir stays
#                      a plain directory in the ISO instead of 07rootfs.sfs)
#   --force            proceed even if an sfs layer is not zstd level 19
#   -h, --help
#
# Requires: grub-mkrescue (grub), xorriso, squashfs-tools (unsquashfs).

set -eu

# ---------------------------------------------------------------------------
# colors / styling
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_RESET='\033[0m' C_BOLD='\033[1m' C_DIM='\033[2m'
    C_RED='\033[31m' C_GREEN='\033[32m' C_CYAN='\033[36m'
else
    C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_CYAN=''
fi

info()  { printf "${C_CYAN}:: %s${C_RESET}\n" "$*"; }
ok()    { printf "  ${C_GREEN}%s${C_RESET}\n" "$*"; }
die()   { printf "${C_RED}error: %s${C_RESET}\n" "$*" >&2; exit 1; }

usage() {
    sed -n '4,25p' "$0" | sed 's/^# //; s/^#//'
}

# ---------------------------------------------------------------------------
# arguments
# ---------------------------------------------------------------------------
dir=""
out=""
label="RSTLSW"
name=""
source_root=""
force=0
no_squash_rootfs=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -d|--dir)  [ "$#" -ge 2 ] || die "--dir requires a directory"
            dir="$2"; shift 2 ;;
        --dir=*)   dir="${1#*=}"; shift ;;
        -o|--output) [ "$#" -ge 2 ] || die "--output requires a file"
            out="$2"; shift 2 ;;
        --output=*) out="${1#*=}"; shift ;;
        -l|--label) [ "$#" -ge 2 ] || die "--label requires a value"
            label="$2"; shift 2 ;;
        --label=*) label="${1#*=}"; shift ;;
        -n|--name) [ "$#" -ge 2 ] || die "--name requires a value"
            name="$2"; shift 2 ;;
        --name=*)  name="${1#*=}"; shift ;;
        -S|--source-root) [ "$#" -ge 2 ] || die "--source-root requires a directory"
            source_root="$2"; shift 2 ;;
        --source-root=*) source_root="${1#*=}"; shift ;;
        --force) force=1; shift ;;
        --no-squash-rootfs) no_squash_rootfs=1; shift ;;
        -*) die "unknown option: $1" ;;
        *) die "unexpected argument: $1" ;;
    esac
done

for cmd in grub-mkrescue xorriso unsquashfs; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found ($cmd is needed)"
done

[ -n "$dir" ] || die "no frugal directory given (-d)"
[ -d "$dir" ] || die "frugal directory not found: $dir"
if [ -z "$name" ]; then name="$(basename "$dir")"; fi
[ -n "$name" ] || die "could not derive an ISO subdirectory name"
case "$label" in
    [A-Z0-9_]* ) ;;
    *) die "volume label must be letters/digits/underscore: '$label'" ;;
esac
if [ "${#label}" -gt 32 ]; then die "volume label must be <= 32 characters"; fi
if [ -z "$out" ]; then out="${dir%/}.iso"; fi

# ---------------------------------------------------------------------------
# verify the squashfs layers are zstd level 19 (the frugal builder guarantees
# 00modules; 01firmware is shipped as fetched from FirstRib; 07rootfs.sfs is
# produced below, so it is only checked once it has been created)
# ---------------------------------------------------------------------------
need() { [ -e "$1" ] || die "frugal is missing $1"; }
need "$dir/vmlinuz"
need "$dir/initrd.gz"
[ -e "$dir/07rootfs.sfs" ] || [ -d "$dir/07rootfs" ] \
    || die "frugal is missing 07rootfs.sfs or the 07rootfs/ directory"

check_compression() {
    sfs="$1"
    [ -e "$sfs" ] || return 0
    sq="$(unsquashfs -s "$sfs" 2>/dev/null | grep -iE '^Compression|compression-level' | tr '\n' ' ' || true)"
    ok "$(basename "$sfs"): ${sq}"
    case "$sq" in
        *'compression-level 19'*) ;;
        *) [ "$force" -eq 1 ] || die "$(basename "$sfs") is not zstd level 19 ('$sq'); use --force to override" ;;
    esac
}
check_compression "$dir/00modules.sfs"
check_compression "$dir/01firmware.sfs"

# ---------------------------------------------------------------------------
# ISO tree: either build the frugal in place (--source-root) or stage a copy
# ---------------------------------------------------------------------------
grubcfg() { # $1 = boot dir root
    bootdir="$1"
    mkdir -p "$bootdir/boot/grub"
    cat > "$bootdir/boot/grub/grub.cfg" <<EOF
set timeout=5
set isovol=$label
search --no-floppy --set=root --label $label
linux  /$name/vmlinuz w_bootfrom=LABEL=$label=/$name w_changes=RAM2 logo.nologo
initrd /$name/initrd.gz
boot
EOF
    ok "wrote $bootdir/boot/grub/grub.cfg"
}

stage=""
if [ -n "$source_root" ]; then
    [ "$source_root/$name" = "$dir" ] || \
        die "--source-root expects the frugal to live at \$source_root/\$name (got '$dir')"
    stage="$source_root"
    info "building ISO in place from '$source_root'"
else
    stage="$(mktemp -d "${TMPDIR:-/tmp}/rstl-iso.XXXXXX")"
    trap 'rm -rf "$stage"' EXIT
    info "staging frugal '$dir' -> '$stage/$name'"
    mkdir -p "$stage/$name"
    tar -C "$dir" -cf - . | tar -C "$stage/$name" -xf -
fi

# ---------------------------------------------------------------------------
# squash the root filesystem into 07rootfs.sfs (zstd level 19)
#
# mkfrugal-rstl.sh leaves 07rootfs/ as a plain directory; for the ISO it is
# compressed by default so the image stays small. w_init's _addlayer() mounts
# a NN<sfs> as an overlay layer exactly like a NN directory, so the ISO boots
# the same either way. --no-squash-rootfs keeps the directory uncompressed.
# (In --source-root mode the default converts the 07rootfs/ dir in the frugal
# in place; in copy mode only the staged tree is changed.)
# ---------------------------------------------------------------------------
rootfs_dir="$stage/$name/07rootfs"
rootfs_sfs="$stage/$name/07rootfs.sfs"
if [ -d "$rootfs_dir" ]; then
    if [ "$no_squash_rootfs" -eq 1 ]; then
        rm -f "$rootfs_sfs" # stale archive would duplicate the NN=07 layer
        info "keeping 07rootfs/ uncompressed (--no-squash-rootfs)"
    else
        info "squashing 07rootfs/ -> 07rootfs.sfs (zstd level 19)"
        rm -f "$rootfs_sfs"
        mksquashfs "$rootfs_dir" "$rootfs_sfs" \
            -noappend -comp zstd -Xcompression-level 19 -no-progress >/dev/null
        rm -rf "$rootfs_dir"
        ok "07rootfs.sfs -> $(du -h "$rootfs_sfs" | cut -f1)"
        check_compression "$rootfs_sfs"
    fi
elif [ -e "$rootfs_sfs" ]; then
    ok "07rootfs.sfs already present - using as-is"
    check_compression "$rootfs_sfs"
else
    die "07rootfs is neither a directory nor an .sfs in '$stage/$name'"
fi

grubcfg "$stage"

# ---------------------------------------------------------------------------
# grub-mkrescue (hybrid BIOS + UEFI)
#
# grub-mkrescue takes the source tree as a positional argument; everything
# after '--' is passed to xorriso in NATIVE dialog dialect (so the volume
# metadata uses -volid / -application_id / -publisher, and the mkisofs-style
# -as mkisofs / -iso-level flags must not be used here). Rock Ridge + Joliet
# are on by default.
# ---------------------------------------------------------------------------
info "running grub-mkrescue -> $out"
mkdir -p "$(dirname "$out")"
grub-mkrescue \
    --output="$out" \
    "$stage" \
    -- -volid "$label" -application_id "rstl.sway frugal" -publisher "arozoid"

if ! xorriso -indev "$out" -toc 2>/dev/null | grep -qi "$label"; then
    warn() { printf "${C_RED}! %s${C_RESET}\n" "$*" >&2; }
    warn "volume id not found in $out (label may be $label or RSTLSW)"
fi

header() { printf "\n${C_BOLD}== %s${C_RESET}\n" "$*"; }
header "$(basename "$out") ready"
printf "  ld boot:  write to USB:  dd if=%s of=/dev/sdX bs=4M status=progress\n" "$out"
printf "  or burn  / write via Ventoy / any grub capable medium\n"
