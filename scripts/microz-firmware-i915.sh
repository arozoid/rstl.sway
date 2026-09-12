#!/bin/bash
# ---------------------------------------------------------------------------
# scripts/microz-firmware-i915.sh
#
# Prepare the ozsouth ("microz") huge-kernel firmware sfs (Puppy fdrv) for the
# usrmerge frugal rootfs and fill the gaps in its Intel i915 DMC (Display Micro
# Code) firmware set, then re-squash it at zstd level 19 so it matches the
# other frugal sfs layers.
#
# The i915 driver in kernel 6.1.96 loads one DMC blob per supported platform
# (drivers/gpu/drm/i915/display/intel_dmc.c DMC_PATH macros), one per display
# generation:
#   display ver 9:   skl_dmc_ver1_27.bin, kbl_dmc_ver1_04.bin,
#                    bxt_dmc_ver1_07.bin, glk_dmc_ver1_04.bin
#   display ver 11:  icl_dmc_ver1_09.bin (also jsl/ehl)
#   display ver 12:  tgl_dmc_ver2_12.bin, rkl_dmc_ver2_03.bin,
#                    dg1_dmc_ver2_02.bin, adls_dmc_ver2_01.bin, adlp_dmc_ver2_16.bin
#   display ver 13:  dg2_dmc_ver2_07.bin
# The fdrv only ships the ver-9 set; the gen-2 blobs (display ver >= 12) are
# fetched from linux-firmware.  cnl_dmc_ver1_07.bin is not loaded by this
# kernel but is kept when present (the 4.16-4.19 kernels load it).
# pre-gen9 hsw/bdw DMC was never published by Intel and no kernel loads it, so
# it is not part of the set.  A blob that cannot be obtained upstream is a
# warning, not a fatal error, and --source-dir always wins for any blob.
#
# Blob source precedence per file:
#   1. an existing file in --source-dir (exact name, then newest <family>_dmc_ver*.bin)
#   2. download from linux-firmware on git.kernel.org (canonical i915/ path)
#   3. skip with a warning
#
# Layout: the Puppy fdrv is non-usrmerge (lib/firmware/...).  The script
# converts it to usrmerge (usr/lib/firmware/...) when needed so the layer
# overlays the usrmerge rootfs cleanly (a plain /lib dir at the top of a
# lower overlay layer would shadow the rootfs's lib -> usr/lib symlink).
#
# Usage:
#   scripts/microz-firmware-i915.sh [--sfs FILE] [-o FILE] [-S DIR]
#     --sfs FILE    input firmware sfs (default: ./microz-firmware.sfs)
#     -o, --output FILE  output sfs (default: overwrite the input in place)
#     -S, --source-dir DIR  optional local i915 firmware dir (e.g.
#                   /usr/lib/firmware/i915 or a staged linux-firmware tree)
# ---------------------------------------------------------------------------
set -uo pipefail

base_url="https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/plain/i915"

# canonical name -> human platform label
# Completes the i915 DMC table of kernel 6.1.96 (skl..dg2).  Blobs that only
# legacy kernels load (cnl, loaded by 4.16-4.19) are kept if the fdrv ships
# them; gen-2 DMC (tgl/rkl/dg1/adls/adlp/dg2) is fetched from linux-firmware.
required_blobs="skl_dmc_ver1_27.bin:skylake
kbl_dmc_ver1_04.bin:kabylake/coffeelake/cometlake
bxt_dmc_ver1_07.bin:broxton
glk_dmc_ver1_04.bin:geminilake
cnl_dmc_ver1_07.bin:cannonlake (legacy, 4.16-4.19)
icl_dmc_ver1_09.bin:icelake + jasperlake/elkhartlake (display ver 11)
tgl_dmc_ver2_12.bin:tigerlake (display ver 12)
rkl_dmc_ver2_03.bin:rocketlake (display ver 12)
dg1_dmc_ver2_02.bin:dg1 (display ver 12)
adls_dmc_ver2_01.bin:alderlake-s (display ver 12)
adlp_dmc_ver2_16.bin:alderlake-p (display ver 12)
dg2_dmc_ver2_07.bin:dg2 (display ver 13)"

in=""
out=""
srcdir=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --sfs) in="$2"; shift 2 ;;
        -o|--output) out="$2"; shift 2 ;;
        -S|--source-dir) srcdir="$2"; shift 2 ;;
        -h|--help) sed -n '1,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) in="$1"; shift ;;
    esac
done

[ -n "$in" ] || { echo "error: no firmware sfs given (use --sfs FILE)" >&2; exit 1; }
[ -f "$in" ] || { echo "error: sfs not found: $in" >&2; exit 1; }
command -v unsquashfs >/dev/null 2>&1 || { echo "error: unsquashfs (squashfs-tools) required" >&2; exit 1; }
command -v mksquashfs >/dev/null 2>&1 || { echo "error: mksquashfs (squashfs-tools) required" >&2; exit 1; }
{ command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; } \
    || { echo "error: curl or wget required for blobs not in --source-dir" >&2; exit 1; }
[ -n "$out" ] || out="$in"

unsquashfs -s "$in" >/dev/null 2>&1 || { echo "error: not a squashfs image: $in" >&2; exit 1; }

work="$(mktemp -d /tmp/microz-fw.XXXXXX)"
trap 'rm -rf "$work"' EXIT

echo "-> unpacking $in"
unsquashfs -q -d "$work/root" "$in" || { echo "error: unsquashfs failed" >&2; exit 1; }

fwroot=""
# prefer the usrmerge tree; fall back to lib/ for the classic non-usrmerge
# Puppy fdrv layout (which is then converted below)
for cand in "$work/root/usr/lib/firmware" "$work/root/lib/firmware"; do
    [ -d "$cand" ] && { fwroot="$cand"; break; }
done
[ -n "$fwroot" ] || { echo "error: no lib/firmware tree in sfs" >&2; exit 1; }

# convert non-usrmerge (lib/firmware) to usrmerge (usr/lib/firmware)
if [ "$fwroot" = "$work/root/lib/firmware" ] && [ ! -e "$work/root/usr/lib/firmware" ]; then
    mkdir -p "$work/root/usr/lib"
    mv "$work/root/lib/firmware" "$work/root/usr/lib/firmware"
    rmdir "$work/root/lib" 2>/dev/null || true
    fwroot="$work/root/usr/lib/firmware"
    echo "-> converted to usrmerge layout: lib/firmware -> usr/lib/firmware"
fi
echo "-> firmware tree: ${fwroot#$work/root}/"

fwdir="$fwroot/i915"
mkdir -p "$fwdir"

added=0
kept=0
skipped=0
notes=""

IFS=$'\n'
for spec in $required_blobs; do
    name="${spec%%:*}"
    plat="${spec#*:}"
    fname="${name%.bin}"
    fam="${fname%_*}"        # e.g. skl_dmc_ver1, icl_dmc_ver1, bdw_dmc_ver1
    if [ -s "$fwdir/$name" ]; then
        echo "   keep  $name ($plat)"
        kept=$((kept + 1))
        continue
    fi
    src=""
    if [ -n "$srcdir" ] && [ -d "$srcdir" ]; then
        if [ -s "$srcdir/$name" ]; then
            src="$srcdir/$name"
        else
            # newest matching <fam>_dmc_ver*.bin in the local tree
            match="$(ls -1 "$srcdir"/"$fam"_dmc_ver*.bin 2>/dev/null | sort -V | tail -1)"
            [ -n "$match" ] && src="$match"
        fi
    fi
    if [ -z "$src" ]; then
        url="$base_url/$name"
        tmp="$work/$name.part"
        echo "   fetch $name ($plat)"
        if command -v curl >/dev/null 2>&1; then
            curl -fsSL --connect-timeout 30 --max-time 300 --retry 3 --retry-delay 5 \
                "$url" -o "$tmp" 2>/dev/null || { echo "   warn  $name download failed ($plat)"; skipped=$((skipped + 1)); continue; }
        else
            wget --timeout=30 --tries=3 -O "$tmp" "$url" 2>/dev/null || { echo "   warn  $name download failed ($plat)"; skipped=$((skipped + 1)); continue; }
        fi
        [ -s "$tmp" ] || { echo "   warn  $name is empty"; rm -f "$tmp"; skipped=$((skipped + 1)); continue; }
        src="$tmp"
    else
        echo "   copy $name ($plat) from --source-dir"
    fi
    cp -a "$src" "$fwdir/$name"
    rm -f "$work/$name.part"
    added=$((added + 1))
done
unset IFS

echo "-> added $added, kept $kept, skipped $skipped blobs in $fwdir"

[ "$added" -eq 0 ] && [ "$kept" -gt 0 ] && echo "-> all required blobs already present; no repack needed" && exit 0

echo "-> re-squashing at zstd level 19"
out_tmp="${out}.tmp$$"
mksquashfs "$work/root" "$out_tmp" \
    -noappend -comp zstd -Xcompression-level 19 -no-progress >/dev/null \
    || { echo "error: mksquashfs failed" >&2; exit 1; }
mv -f "$out_tmp" "$out"

echo "-> i915 DMC blobs in $out:"
unsquashfs -ll "$out" 2>/dev/null | grep -o "$(basename "$fwdir")/[a-z0-9_.]*_dmc[a-z0-9_.]*\.bin" | sort
echo "-> size: $(du -h "$out" | cut -f1) (was $(du -h "$in" | cut -f1))"
printf '%b' "$notes" | sed 's/^/  note: /'
[ "$skipped" -gt 0 ] && exit 2
exit 0