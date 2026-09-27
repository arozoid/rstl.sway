#!/bin/sh
# mkfrugal-ventoy.sh - install a mkfrugal-rstl.sh frugal onto a Ventoy stick's
# data partition and add a custom menu entry (F6) to boot it directly.
#
# Ventoy cannot boot the rstl ISO itself (see mkfrugal-iso.sh; the initrd
# seeks LABEL=RSTLSW which under Ventoy is a file, not a block device).  The
# supported Ventoy path is the frugal-on-partition one KLV/Puppy use: place
# the frugal directory on the Ventoy data partition (label defaults to
# "Ventoy") and boot it with w_bootfrom pointing at that partition's label
# or UUID.  The data partition IS a real labeled block device, so the initrd
# finds it normally.
#
# Usage:
#   ./mkfrugal-ventoy.sh -d <frugal-dir> [-m <ventoy-mount>] [-n NAME]
#                         [-l LABEL] [-u UUID] [--dry-run]
#
#   -d, --dir DIR      frugal directory produced by mkfrugal-rstl.sh
#   -m, --mount MNT    mount point of the Ventoy DATA partition (the big one,
#                      default label "Ventoy"). Auto-detected when omitted.
#   -n, --name NAME    subdirectory the frugal lands in on the partition
#                      (default: basename of DIR)
#   -l, --label LABEL  partition label for w_bootfrom (default: detected)
#   -u, --uuid UUID    partition UUID for w_bootfrom (used only when no label is
#                      found, or explicitly to force UUID-based boot)
#   -L, --label-search use GRUB search by LABEL instead of search by file
#                      (default search by file: more robust across filesystems)
#       --dry-run      print the planned actions and the menu entry, change
#                      nothing
#   -h, --help
#
# Requires: check for tools per action (mksquashfs/unsquashfs, findmnt/lsblk).
#
# Ensures: 07rootfs/ is squashed to 07rootfs.sfs (zstd 19) so the target tree
# carries no symlinks - the Ventoy data partition is exFAT by default, which
# has no symlink support and would break a copied Arch rootfs directory.

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
warn()  { printf "${C_RED}! %s${C_RESET}\n" "$*" >&2; }

usage() {
    sed -n '4,31p' "$0" | sed 's/^# //; s/^#//'
}

# ---------------------------------------------------------------------------
# arguments
# ---------------------------------------------------------------------------
dir=""
mnt=""
name=""
label=""
uuid=""
label_search=0
dry_run=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -d|--dir) [ "$#" -ge 2 ] || die "--dir requires a directory"
            dir="$2"; shift 2 ;;
        --dir=*)   dir="${1#*=}"; shift ;;
        -m|--mount) [ "$#" -ge 2 ] || die "--mount requires a directory"
            mnt="$2"; shift 2 ;;
        --mount=*) mnt="${1#*=}"; shift ;;
        -n|--name) [ "$#" -ge 2 ] || die "--name requires a value"
            name="$2"; shift 2 ;;
        --name=*)  name="${1#*=}"; shift ;;
        -l|--label) [ "$#" -ge 2 ] || die "--label requires a value"
            label="$2"; shift 2 ;;
        --label=*) label="${1#*=}"; shift ;;
        -u|--uuid) [ "$#" -ge 2 ] || die "--uuid requires a value"
            uuid="$2"; shift 2 ;;
        --uuid=*)  uuid="${1#*=}"; shift ;;
        -L|--label-search) label_search=1; shift ;;
        --dry-run) dry_run=1; shift ;;
        -*) die "unknown option: $1" ;;
        *) die "unexpected argument: $1" ;;
    esac
done

[ -n "$dir" ] || die "no frugal directory given (-d)"
[ -d "$dir" ] || die "frugal directory not found: $dir"
[ -n "$name" ] || name="$(basename "$dir")"
[ -n "$name" ] || die "could not derive a subdirectory name"
case "$name" in
    */*|*' '*|".."|".") die "invalid name: '$name' (must be a plain directory name without slashes or spaces)" ;;
esac

# ---------------------------------------------------------------------------
# find the Ventoy data partition mount point (auto-detect when omitted)
# ---------------------------------------------------------------------------
find_ventoy_mnt() { # echoes first mounted partition labeled Ventoy
    if command -v findmnt >/dev/null 2>&1; then
        findmnt -n -r -o TARGET -S LABEL=Ventoy 2>/dev/null | head -1
    fi
}

if [ -z "$mnt" ]; then
    mnt="$(find_ventoy_mnt)"
    [ -n "$mnt" ] || die "could not find a mounted Ventoy data partition; mount it and pass -m"
    info "detected Ventoy data partition at '$mnt'"
fi
[ -d "$mnt" ] || die "Ventoy data partition mount point not found: $mnt"
[ -w "$mnt" ] || die "not writable: $mnt (mount the Ventoy data partition writable)"

# derive label / UUID from the mounted filesystem. findmnt's LABEL/UUID columns
# may need to open the device; fall back to lsblk (sysfs-backed, unprivileged).
dev="$(findmnt -n -r -o SOURCE -T "$mnt" 2>/dev/null | head -1 || true)"
fs_label="$(findmnt -n -r -o LABEL -T "$mnt" 2>/dev/null | head -1 || true)"
fs_uuid="$(findmnt -n -r -o UUID -T "$mnt" 2>/dev/null | head -1 || true)"
if command -v lsblk >/dev/null 2>&1 && [ -n "$dev" ]; then
    [ -z "$fs_label" ] && fs_label="$(lsblk -no LABEL "$dev" 2>/dev/null | head -1 || true)"
    [ -z "$fs_uuid" ] && fs_uuid="$(lsblk -no UUID "$dev" 2>/dev/null | head -1 || true)"
fi
if [ -z "$label" ]; then
    label="$fs_label"
fi
if [ -z "$uuid" ]; then
    uuid="$fs_uuid"
fi

ident=""
if [ -n "$label" ]; then
    ident="LABEL=$label"
elif [ -n "$uuid" ]; then
    ident="UUID=$uuid"
else
    die "could not determine a label or UUID for '$mnt'; pass -l LABEL or -u UUID"
fi

# ---------------------------------------------------------------------------
# validate the frugal and plan the copy
# ---------------------------------------------------------------------------
need() { [ -e "$1" ] || die "frugal is missing $1"; }
need "$dir/vmlinuz"
need "$dir/initrd.gz"
[ -d "$dir/07rootfs" ] || [ -e "$dir/07rootfs.sfs" ] \
    || die "frugal is missing 07rootfs.sfs or the 07rootfs/ directory"

rootfs_is_dir=0
if [ -d "$dir/07rootfs" ]; then rootfs_is_dir=1; fi

target="$mnt/$name"

if [ "$dry_run" -eq 1 ]; then
    info "dry-run - no changes will be made"
    printf '\n'
    info "would copy to:      $target"
    if [ "$rootfs_is_dir" -eq 1 ]; then
        info "  - vmlinuz, initrd.gz, *.sfs files (copied)"
        info "  - 07rootfs/ squashed to 07rootfs.sfs (zstd 19; exFAT has no symlinks)"
    else
        info "  - 07rootfs.sfs present; copied as-is"
    fi
    info "  - menu entry registered in $mnt/ventoy/ventoy_grub.cfg (Ventoy F6)"
    printf '\n'
    ok "dry-run complete - no changes made"
    exit 0
fi

# ---------------------------------------------------------------------------
# tools needed for the copy
# ---------------------------------------------------------------------------
for cmd in findmnt; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found"
done
if [ "$rootfs_is_dir" -eq 1 ]; then
    command -v mksquashfs >/dev/null 2>&1 || die "'mksquashfs' not found (needed to squash 07rootfs/)"
fi

# ---------------------------------------------------------------------------
# copy the frugal to the Ventoy data partition
# ---------------------------------------------------------------------------
# Stage into a hidden dir on the same filesystem, then atomically move it into
# place so an interrupted run never leaves a half-copied frugal.
stage="$(mktemp -d "$mnt/.rstl-ventoy.XXXXXX")"
trap 'rm -rf "$stage"' EXIT HUP INT TERM

info "copying frugal '$dir' -> '$target'"
cp -a "$dir"/vmlinuz "$dir"/initrd.gz "$stage/"
for s in "$dir"/*.sfs; do
    [ -e "$s" ] || continue
    cp -a "$s" "$stage/"
done

if [ "$rootfs_is_dir" -eq 1 ]; then
    info "squashing 07rootfs/ -> 07rootfs.sfs (zstd level 19)"
    rm -f "$stage/07rootfs.sfs" # stale archive would duplicate the NN=07 layer
    mksquashfs "$dir/07rootfs" "$stage/07rootfs.sfs" \
        -noappend -comp zstd -Xcompression-level 19 -no-progress >/dev/null
    ok "07rootfs.sfs -> $(du -h "$stage/07rootfs.sfs" | cut -f1)"
fi

rm -rf "$target"
mkdir -p "$(dirname "$target")"
mv "$stage" "$target"
trap - EXIT HUP INT TERM
ok "frugal installed at '$target'"

# ---------------------------------------------------------------------------
# register the boot entry in the Ventoy custom menu (F6)
#
# ventoy_grub.cfg must live at /ventoy/ventoy_grub.cfg on the DATA partition
# (all lowercase). Ventoy loads it when F6 is pressed in its boot menu. The
# entry is appended only if this frugal is not registered yet, so pre-existing
# custom entries are left untouched.
# ---------------------------------------------------------------------------
ventoy_dir="$mnt/ventoy"
ventoy_cfg="$ventoy_dir/ventoy_grub.cfg"
marker="rstl.sway ($name)"

search_line='search --no-floppy --set=root --file /'$name'/vmlinuz'
if [ "$label_search" -eq 1 ]; then
    [ -n "$label" ] || die "--label-search needs a partition label (none found for '$mnt')"
    search_line="search --no-floppy --set=root --label $label"
fi

entry="menuentry \"rstl.sway (frugal) $name\" {
    $search_line
    linux   /$name/vmlinuz w_bootfrom=$ident=/$name w_changes=RAM2 logo.nologo
    initrd  /$name/initrd.gz
}"

mkdir -p "$ventoy_dir"
if [ -f "$ventoy_cfg" ] && grep -qF "rstl.sway ($name)" "$ventoy_cfg"; then
    ok "'$ventoy_cfg' already registers $name; leaving it untouched"
else
    {
        printf '\n# --- %s (added by mkfrugal-ventoy.sh) ---\n' "$marker"
        printf '%s\n' "$entry"
    } >> "$ventoy_cfg"
    ok "menu entry added to '$ventoy_cfg'"
fi

# ---------------------------------------------------------------------------
# summary / next steps
# ---------------------------------------------------------------------------
printf '\n'
header() { printf "\n${C_BOLD}== %s${C_RESET}\n" "$*"; }
header "ventoy install complete"
printf '  boot:  insert the stick, boot Ventoy, press %s\n' "F6"
printf '         and select "rstl.sway (frugal) %s"\n' "$name"
printf '  entry: %s\n' "$ventoy_cfg"
printf '  boot identifier: %s (matches the w_bootfrom kernel line)\n' "$ident"
printf '\n'
printf '  NOTE: changes are RAM-only (w_changes=RAM2). For persistence create a\n'
printf '        changes dir and pass w_changes=%s/... on the kernel line.\n' \
    "$( [ -n "$label" ] && printf 'LABEL=%s' "$label" || printf 'UUID=%s' "$uuid" )"
printf '  NOTE: the rstl ISO itself still cannot be booted by Ventoy; dd it to\n'
printf '        a USB stick for the ISO experience (see mkfrugal-iso.sh).\n'
exit 0