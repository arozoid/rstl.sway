#!/bin/sh
# mkfrugal-rstl.sh - build a bootable FirstRib-style (frugal) rstl.sway
#
# Produces a self-contained frugal directory at --target:
#
#   <target>/
#     vmlinuz               kernel image (linux-cachyos, or the stock FirstRib
#                           huge kernel 'vdpup' 6.1.52 with --kernel vdpup)
#     initrd.gz             FirstRib initrd built by mkFRkernel (modules baked
#                           in); with --kernel vdpup the stock FirstRib initrd
#     00modules.sfs         zstd level 19 squashfs of the full module tree
#                           (with --kernel vdpup: the stock FirstRib modules sfs)
#     01firmware.sfs        huge-kernel firmware (FirstRib, zstd level 19)
#     07rootfs/             the CachyOS root filesystem (squashed by the ISO maker)
#     grub_config.txt       GRUB menu entry snippet (disk boot, UUID placeholder)
#     readme_kernel_version.txt
#
# The tree can be booted directly from a disk/USB (w_bootfrom=UUID=...) or
# turned into a bootable ISO with mkfrugal-iso.sh (w_bootfrom=LABEL=...).
#
# Usage:
#   ./mkfrugal-rstl.sh [target] [options]
#
#   target    directory the frugal is placed in (defaults to ./rstl.sway).
#
#   -a, --arch LEVEL        v1|v2|v3|v4|auto (default: auto when not a TTY)
#   -f, --flavor NAME       install | install-min | install-uber-min | rstl-inst
#                           (default: install-min)
#   -y, --yes               assume yes for the installer scripts
#   -K, --kernel PKG        kernel package, or 'vdpup' for the FirstRib huge
#                           kernel 6.1.52-vdpup (retro LTS, no pacman package;
#                           its stock vmlinuz + 00modules.sfs + initrd-latest.gz
#                           are fetched unmodified; default: linux-cachyos)
#       --firmware FILE     reuse an existing 01firmware.sfs instead of downloading
#       --modules-source DIR   build 00modules.sfs by reusing an existing
#                          modules tree verbatim (FirstRib huge-kernel style,
#                          incl. build/ + vdso/) instead of the rootfs tree.
#                          DIR = tree root (usr/lib/modules|lib/modules|kver)
#       --modules-build-dir DIR  copy DIR as usr/lib/modules/<ver>/build into
#                          00modules.sfs (kernel build tree for dkms/out-of-tree
#                          module compilation; gives size parity with the
#                          FirstRib huge-kernel 00modules which ships build/)
#       --cache DIR         download cache (default: ${TMPDIR:-/tmp}/rstl-frugal-cache)
#       --rstl-inst-bin FILE prebuilt rstl-inst binary (required for --flavor rstl-inst
#                           unless cargo + the rstl-inst submodule are available)
#       --password PASS     login password for root/rustle (default: rstl)
#       --force             rebuild into --target even if it is not empty
#   -h, --help
#
# Requires: root, pacstrap/arch-chroot (arch-install-scripts), squashfs-tools,
# wget (mkFRkernel), curl, and the mkFRkernel script next to this one.
#
# Flavors:
#   install        full install.sh desktop; greetd/tuigreet login as user 'rustle'
#                  (install.sh refuses to run as root, so it runs via su - rustle
#                  with a temporary NOPASSWD wheel sudo, exactly like the
#                  install_dotfiles() step in rstl-install.sh), root keeps config too
#   rstl-inst      same desktop, but boots straight into the rstl-inst TUI on tty1
#                  (install to disk / try-live sway / network / shell)
#   install-min    minimal desktop, install-min.sh runs as root
#   install-uber-min  uber-minimal desktop, install-uber-min.sh runs as root

set -eu

# ---------------------------------------------------------------------------
# colors / styling
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_RESET='\033[0m' C_BOLD='\033[1m' C_DIM='\033[2m'
    C_PURPLE='\033[95m' C_CYAN='\033[36m' C_RED='\033[31m' C_GREEN='\033[32m'
else
    C_RESET='' C_BOLD='' C_DIM='' C_PURPLE='' C_CYAN='' C_RED='' C_GREEN=''
fi

header() { printf "\n${C_BOLD}${C_PURPLE}== %s${C_RESET}\n" "$*"; }
info()   { printf "${C_PURPLE}:: %s${C_RESET}\n" "$*"; }
ok()     { printf "  ${C_GREEN}%s${C_RESET}\n" "$*"; }
die()    { printf "${C_RED}error: %s${C_RESET}\n" "$*" >&2; exit 1; }

usage() {
    sed -n '4,47p' "$0" | sed 's/^# //; s/^#//'
}

# ---------------------------------------------------------------------------
# arguments
# ---------------------------------------------------------------------------
target=""
requested_arch=""
flavor="install-min"
assume_yes=0
kernel_pkg="linux-cachyos"
kernel_vdpup=0
opt_firmware=""
opt_modules_build=""
opt_modules_source=""
cache="${TMPDIR:-/tmp}/rstl-frugal-cache"
rstl_inst_bin=""
password="${RSTL_FRUGAL_PASSWORD:-rstl}"
force=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        -a|--arch) [ "$#" -ge 2 ] || die "--arch requires v1|v2|v3|v4|auto"
            requested_arch="$2"; shift 2 ;;
        --arch=*) requested_arch="${1#*=}"; shift ;;
        -f|--flavor) [ "$#" -ge 2 ] || die "--flavor requires install|install-min|install-uber-min|rstl-inst"
            flavor="$2"; shift 2 ;;
        --flavor=*) flavor="${1#*=}"; shift ;;
        -y|--yes) assume_yes=1; shift ;;
        -K|--kernel) [ "$#" -ge 2 ] || die "--kernel requires a package name (or 'vdpup')"
            kernel_pkg="$2"; shift 2 ;;
        --kernel=*) kernel_pkg="${1#*=}"; shift ;;
        --firmware) [ "$#" -ge 2 ] || die "--firmware requires a file"
            opt_firmware="$2"; shift 2 ;;
        --firmware=*) opt_firmware="${1#*=}"; shift ;;
        --modules-build-dir) [ "$#" -ge 2 ] || die "--modules-build-dir requires a directory"
            opt_modules_build="$2"; shift 2 ;;
        --modules-build-dir=*) opt_modules_build="${1#*=}"; shift ;;
        --modules-source) [ "$#" -ge 2 ] || die "--modules-source requires a directory"
            opt_modules_source="$2"; shift 2 ;;
        --modules-source=*) opt_modules_source="${1#*=}"; shift ;;
        --cache) [ "$#" -ge 2 ] || die "--cache requires a directory"
            cache="$2"; shift 2 ;;
        --cache=*) cache="${1#*=}"; shift ;;
        --rstl-inst-bin) [ "$#" -ge 2 ] || die "--rstl-inst-bin requires a file"
            rstl_inst_bin="$2"; shift 2 ;;
        --rstl-inst-bin=*) rstl_inst_bin="${1#*=}"; shift ;;
        --password) [ "$#" -ge 2 ] || die "--password requires a value"
            password="$2"; shift 2 ;;
        --password=*) password="${1#*=}"; shift ;;
        --force) force=1; shift ;;
        -*) die "unknown option: $1" ;;
        *) target="$1"; shift ;;
    esac
done

case "$kernel_pkg" in
    vdpup) kernel_vdpup=1 ;;
esac

case "$flavor" in
    install|install-min|install-uber-min|rstl-inst) ;;
    *) die "unknown flavor: $flavor (use install, install-min, install-uber-min or rstl-inst)" ;;
esac

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "must be run as root (pacstrap / mksquashfs need it)"
for cmd in pacstrap arch-chroot mksquashfs unsquashfs; do
    command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found (install arch-install-scripts + squashfs-tools)"
done
command -v wget >/dev/null 2>&1 || die "'wget' not found (mkFRkernel needs it to fetch the skeleton initrd)"
REPO="$(cd "$(dirname "$0")" && pwd)"
[ -x "$REPO/mkFRkernel" ] || die "missing mkFRkernel next to this script"

if [ -z "$target" ]; then
    printf 'Enter frugal target directory [rstl.frugal]: '
    read -r ans || :
    target="${ans:-rstl.frugal}"
fi
case "$target" in
    /|*/*) ;;                # absolute path or contains '/' -> use as-is
    *) target="./$target" ;; # bare name -> current directory
esac
name="$(basename "$target")"
[ -n "$name" ] || die "invalid target directory: $target"

if [ -e "$target" ] && [ -n "$(ls -A "$target" 2>/dev/null)" ] && [ "$force" -eq 0 ]; then
    die "target '$target' is not empty (use --force to rebuild into it)"
fi

export FLAG_YES=""
if [ "$assume_yes" -eq 1 ]; then FLAG_YES="--yes"; fi

ROOTFS="$target/07rootfs"
mkdir -p "$target"

# ---------------------------------------------------------------------------
# x86-64 level detection (same heuristics as simple-rootfs.sh)
# ---------------------------------------------------------------------------
detect_level() {
    _l="$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null || /lib64/ld-linux-x86-64.so.2 --help 2>/dev/null)"
    case "$_l" in
        *'x86-64-v4 (supported, searched)'*) echo 4 ;;
        *'x86-64-v3 (supported, searched)'*) echo 3 ;;
        *'x86-64-v2 (supported, searched)'*) echo 2 ;;
        *) echo 1 ;;
    esac
}
ask_level() {
    case "${requested_arch:-}" in
        v1|v2|v3|v4) echo "${requested_arch#v}"; return 0 ;;
        auto|"") detect_level; return 0 ;;
    esac
    die "bad --arch value: ${requested_arch}"
}

arch_level="$(ask_level)"
pacman_conf_name="pacman-v${arch_level}.conf"
[ -f "$REPO/$pacman_conf_name" ] || die "missing $pacman_conf_name for x86-64-v$arch_level"
[ -f "$REPO/pacman-base.conf" ] || die "missing pacman-base.conf"
info "x86-64-v$arch_level -> $pacman_conf_name; flavor: $flavor; kernel: $kernel_pkg"

# ---------------------------------------------------------------------------
# 1. pacstrap a base rootfs (plain Arch repos; CachyOS comes next)
# ---------------------------------------------------------------------------
SELF_BIND=0
cleanup() {
    if [ "$SELF_BIND" -eq 1 ]; then
        umount "$ROOTFS" 2>/dev/null || true
    fi
}
trap cleanup EXIT

header "Bootstrapping base system into '$ROOTFS'"
mkdir -p "$ROOTFS"
pacstrap -C "$REPO/pacman-base.conf" -K "$ROOTFS" --noconfirm base sudo git

# marker so install-min.sh / install-uber-min.sh may run as root inside a rootfs
touch "$ROOTFS/etc/.rstl-sway-rootfs"

# make sure DNS works inside the chroot while pacman talks to the mirrors
if [ -s /etc/resolv.conf ]; then
    cp -a /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
fi
if [ ! -s "$ROOTFS/etc/resolv.conf" ]; then
    printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > "$ROOTFS/etc/resolv.conf"
fi

# a self bind-mount gives arch-chroot a clean root mountpoint for pacman
mount --bind "$ROOTFS" "$ROOTFS"
SELF_BIND=1

# ---------------------------------------------------------------------------
# 2. install the CachyOS keyring + mirrorlists, then swap in the pacman.conf
# ---------------------------------------------------------------------------
bootstrap_cachyos() {
    info "installing CachyOS keyring + mirrorlists into '$ROOTFS'"
    base="https://mirror.cachyos.org/repo/x86_64/cachyos"
    listing="$(curl -fsSL --connect-timeout 20 --max-time 120 --retry 3 --retry-delay 5 "$base/")" || die "cannot fetch $base/ (network up?)"
    pkgs=""
    for stem in cachyos-keyring cachyos-mirrorlist cachyos-v3-mirrorlist cachyos-v4-mirrorlist; do
        pkg="$(printf '%s\n' "$listing" | grep -oE "${stem}-[0-9]+[^\"<]*?-any\.pkg\.tar\.zst" | sort -V | tail -1)"
        [ -n "$pkg" ] || die "could not find $stem on CachyOS mirror"
        pkgs="$pkgs $base/$pkg"
    done
    arch-chroot "$ROOTFS" pacman-key --init
    arch-chroot "$ROOTFS" pacman-key --populate archlinux
    # bound the keyserver fetch so a flaky dirmngr cannot hang the build
    mkdir -p "$ROOTFS/root/.gnupg"
    printf 'keyserver timeout 30\n' > "$ROOTFS/root/.gnupg/dirmngr.conf"
    arch-chroot "$ROOTFS" pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
    arch-chroot "$ROOTFS" pacman-key --lsign-key F3B607488DB35A47
    arch-chroot "$ROOTFS" pacman -U --noconfirm $pkgs
    arch-chroot "$ROOTFS" pacman-key --populate cachyos 2>/dev/null || true
    ok "CachyOS keyring + mirrorlists installed"
}
bootstrap_cachyos

cp -a "$REPO/$pacman_conf_name" "$ROOTFS/etc/pacman.conf"

info "syncing + upgrading the rootfs (CachyOS repos)"
arch-chroot "$ROOTFS" pacman -Syu --noconfirm

# ---------------------------------------------------------------------------
# 3. kernel: linux-cachyos (default) OR the FirstRib huge kernel "vdpup"
#    (kernel 6.1.52-vdpup, a retro LTS build). vdpup has no pacman package:
#    its vmlinuz + full module tree come from FirstRib's kernel_usrmerge_default
#    00modules.sfs overlay, so the vanilla `linux` that base pulled in is
#    dropped and no arch kernel package is installed at all.
# ---------------------------------------------------------------------------
header "Installing kernel $kernel_pkg"
if [ "$kernel_vdpup" -eq 1 ]; then
    arch-chroot "$ROOTFS" pacman -Rns --noconfirm linux >/dev/null 2>&1 || true
    ok "vdpup: no pacman kernel; huge-kernel assets fetched below"
else
    arch-chroot "$ROOTFS" pacman -S --noconfirm "$kernel_pkg"
    kernelver="$(ls -1 "$ROOTFS/usr/lib/modules" | tail -1)"
    ok "kernel modules: $kernelver"
    if [ "$kernel_pkg" != "linux" ] && [ -d "$ROOTFS/usr/lib/modules" ]; then
        arch-chroot "$ROOTFS" pacman -Rns --noconfirm linux >/dev/null 2>&1 || true
    fi
fi

# --- FirstRib huge kernel "vdpup": fetch kernel + modules + initrd ----------
# Pure drop-in of the stock huge-kernel assets from the URLs in the original
# mkfrugal script - nothing is rebuilt, extracted or recompressed (no
# mkFRkernel, no re-squash): the three boot files are copied straight into the
# frugal in section 8, so the only cost is the (cached) download.
if [ "$kernel_vdpup" -eq 1 ]; then
    vdpup_base="https://gitlab.com/firstrib/firstrib/-/raw/master/latest/build_system/huge_kernels/kernel_usrmerge_default"
    vdpup_initrd_url="https://gitlab.com/firstrib/firstrib/-/raw/master/latest/build_system/initrd-latest.gz"
    mkdir -p "$cache"
    fetch_vdpup() {
        for spec in \
            "vmlinuz|$vdpup_base/vmlinuz" \
            "00modules.sfs|$vdpup_base/00modules.sfs" \
            "initrd.gz|$vdpup_initrd_url"; do
            f="${spec%%|*}"
            url="${spec#*|}"
            cached="$cache/vdpup-$f"
            [ -s "$cached" ] && continue
            if command -v curl >/dev/null 2>&1; then
                curl -fL --connect-timeout 30 --max-time 1200 --retry 3 --retry-delay 5 "$url" -o "$cached.part" || return 1
            else
                wget --timeout=30 --tries=3 -O "$cached.part" "$url" || return 1
            fi
            mv "$cached.part" "$cached"
        done
        return 0
    }
    if command -v flock >/dev/null 2>&1; then
        ( flock -x 9; fetch_vdpup ) 9>"$cache/.vdpup.lock"
    else
        fetch_vdpup
    fi
    [ -s "$cache/vdpup-vmlinuz" ] || die "vdpup kernel download failed"
    [ -s "$cache/vdpup-00modules.sfs" ] || die "vdpup module download failed"
    [ -s "$cache/vdpup-initrd.gz" ] || die "vdpup initrd download failed"
    kernelver="6.1.52-vdpup"
    ok "vdpup assets cached: $kernelver (stock FirstRib huge kernel)"
fi

# ---------------------------------------------------------------------------
# 4. basic system identity (hostname, locale, hosts)
# ---------------------------------------------------------------------------
header "Writing basic system identity"
printf 'rstl\n' > "$ROOTFS/etc/hostname"
printf '127.0.0.1   localhost\n::1         localhost\n' > "$ROOTFS/etc/hosts"
printf 'en_US.UTF-8 UTF-8\n' > "$ROOTFS/etc/locale.gen"
arch-chroot "$ROOTFS" locale-gen >/dev/null 2>&1 || true
printf 'LANG=en_US.UTF-8\n' > "$ROOTFS/etc/locale.conf"
ln -sfn /usr/share/zoneinfo/UTC "$ROOTFS/etc/localtime" 2>/dev/null || true
rm -f "$ROOTFS/etc/localtime.bak" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 5. stage the dotfiles repository (for root AND as the installer source)
# ---------------------------------------------------------------------------
copy_repo() {
    dest="$1"
    mkdir -p "$dest"
    # Exclude build/CI workspace artifacts, which can be GB in CI (cache
    # firmware, stage/ rootfs with pacman caches, dist/, build.log) — they must
    # never ship in staged dotfiles, and stage/ is also the tar *destination*,
    # so excluding it avoids tar streaming a tree it is writing into.
    tar --exclude='./build_work' \
        --exclude='./build_output' \
        --exclude='./archiso' \
        --exclude='./rstl-inst/target' \
        --exclude='./rstl-pick/target' \
        --exclude='./cache' \
        --exclude='./stage' \
        --exclude='./dist' \
        --exclude='./build.log' \
        --exclude='./.git' \
        --exclude='./.gitmodules' \
        --exclude='./.gitignore' \
        -C "$REPO" -cf - . | tar -C "$dest" -xf -
}

# trim_git_dirs PATH... - strip nested VCS metadata from staged dotfiles.
# Keeps the frugal (and therefore the ISO, which reuses this rootfs) free of
# the repo's .git tree so the built image stays lean.
trim_git_dirs() {
    for d in "$@"; do
        [ -e "$d" ] || continue
        find "$d" \( -type d -name .git -o -name .gitmodules -o -name .gitignore \) \
            -prune -exec rm -rf {} + 2>/dev/null || true
    done
}

info "staging dotfiles into /etc/skel/.config/rstl.sway (single copy)"
copy_repo "$ROOTFS/etc/skel/.config/rstl.sway"
trim_git_dirs "$ROOTFS/etc/skel"
chmod +x "$ROOTFS/etc/skel/.config/rstl.sway"/install*.sh \
         "$ROOTFS/etc/skel/.config/rstl.sway"/scripts/*.sh 2>/dev/null || true
# root does NOT get a second copy: /root/.config/rstl.sway is a link into the
# skel tree, so every root flow (install-min/uber-min run as root, the rustle
# scaffolding copies, the root desktop) reads/writes the ONE repo copy. New
# users pick it up through skel; rstl-first-login skips root at boot
# ($HOME != /root guard), so the skel template stays pristine.
mkdir -p "$ROOTFS/root/.config"
ln -sfn /etc/skel/.config/rstl.sway "$ROOTFS/root/.config/rstl.sway"

# --- first-login hook: one-shot per-user desktop setup on first login -------
# /etc/skel carries static dotfiles only; rstl-first-login does the wiring a
# skeleton cannot (config symlinks before sway starts, portals, wallpaper,
# user services). greetd/tuigreet launches sway through it, /etc/profile.d
# sources it for shell logins, and the sway autostart re-runs it idempotently.
install -Dm755 "$REPO/scripts/first-login.sh" "$ROOTFS/usr/local/bin/rstl-first-login"
cat > "$ROOTFS/etc/profile.d/rstl-first-login.sh" <<'EOF'
# rstl.sway first-login hook: runs once per user on their first (shell) login.
# The script itself guards on the per-user marker, so it is safe on every login.
[ -n "$HOME" ] || return 0
[ -x /usr/local/bin/rstl-first-login ] && /usr/local/bin/rstl-first-login
EOF
chmod 644 "$ROOTFS/etc/profile.d/rstl-first-login.sh"
ok "first-login hook installed (/usr/local/bin/rstl-first-login + profile.d)"

# ---------------------------------------------------------------------------
# helpers shared by the flavors
# ---------------------------------------------------------------------------
chr() {
    echo "  [chroot] $*" >&2
    # HOME must be /root inside the rootfs: a leaked host HOME (GitHub Actions
    # uses /github/home) makes every $HOME-relative operation land in a dead
    # path (wallpaper, crontab, skel copy) and has crashed useradd in CI.
    if arch-chroot "$ROOTFS" env HOME=/root "$@"; then
        echo "  [chr ok] $*" >&2
        return 0
    fi
    # always attribute a failing/crashing chroot call before set -e aborts
    rc=$?
    echo "  [chr FAILED rc=$rc] $*" >&2
    return $rc
}

# symlinked ~/.config dirs point INTO $src_cfg; replicate the standard links
replicate_symlinks() { # $1 = home dir whose $1/.config/rstl.sway is the source
    home="$1"
    cfg="$home/.config/rstl.sway"
    DEST="$home/.config"
    for d in sway swaylock swayidle yambar rofi fish foot nvim mako lf rovr fastfetch; do
        if [ -e "$cfg/$d" ] && [ ! -e "$DEST/$d" ]; then
            ln -s "$cfg/$d" "$DEST/$d"
        fi
    done
    if [ -d "$cfg/portal" ]; then
        mkdir -p "$DEST/xdg-desktop-portal-termfilechooser"
        cp -a "$cfg/portal/." "$DEST/xdg-desktop-portal-termfilechooser/" 2>/dev/null || true
        chmod +x "$DEST/xdg-desktop-portal-termfilechooser/"*.sh 2>/dev/null || true
    fi
    mkdir -p "$DEST/xdg-desktop-portal"
    [ -f "$DEST/xdg-desktop-portal/portals.conf" ] || \
        printf '[preferred]\norg.freedesktop.impl.portal.FileChooser=termfilechooser\n' \
            > "$DEST/xdg-desktop-portal/portals.conf"
}

ensure_rustle_user() {
    if grep -q '^rustle:' "$ROOTFS/etc/passwd"; then
        return 0
    fi
    if chr useradd -m -G wheel,video,audio,storage,input -s /usr/bin/bash rustle; then
        return 0
    fi
    # useradd died under some chroot envs (e.g. GitHub Actions workers); wire
    # the account natively so the build cannot be bricked by a shadow crash
    warn "useradd failed - creating rustle account natively"
    acc="$ROOTFS/tmp/mkuser.sh"
    cat > "$acc" <<'EOMKAN'
set -u
grep -q '^rustle:' /etc/passwd || printf 'rustle:x:1000:1000:rustle:/home/rustle:/usr/bin/bash\n' >> /etc/passwd
grep -q '^rustle:' /etc/shadow || printf 'rustle:x:0:0:99999:7:::\n' >> /etc/shadow
grep -q '^rustle:' /etc/group || printf 'rustle:x:1000:\n' >> /etc/group
for g in wheel video audio storage input; do
    if ! awk -F: -v g="$g" '$1==g && $4 ~ /(^|,)rustle(,|$)/ {f=1} END{exit !f}' /etc/group; then
        sed -i "s/^\($g:[^:]*:[0-9]*:\).*/\1rustle/" /etc/group
    fi
done
mkdir -p /home/rustle
[ -e /home/rustle/.config ] || cp -a /etc/skel/. /home/rustle/ 2>/dev/null || true
chown -R rustle:rustle /home/rustle 2>/dev/null || true
EOMKAN
    chr /bin/sh /tmp/mkuser.sh || warn "native account creation also failed (continuing)"
    rm -f "$acc"
}

# rustle can run install.sh through sudo; grant wheel NOPASSWD only for the
# duration of the installer, then restore normal password sudo (like the
# install_dotfiles() function in rstl-install.sh).
install_as_rustle() {
    info "running ${1} as user 'rustle' (NOPASSWD wheel, restored afterwards)"
    chr useradd -m -G wheel,video,audio,storage,input -s /usr/bin/bash rustle
    as_rustle_dir="$ROOTFS/home/rustle/.config/rstl.sway"
    rm -rf "$as_rustle_dir"
    mkdir -p "$ROOTFS/home/rustle/.config"
    cp -a "$ROOTFS/root/.config/rstl.sway" "$as_rustle_dir"
    chr chown -R rustle:rustle /home/rustle/.config
    printf '%%wheel ALL=(ALL:ALL) NOPASSWD: ALL\n' > "$ROOTFS/etc/sudoers.d/10-installer"
    chmod 440 "$ROOTFS/etc/sudoers.d/10-installer"
    if ! chr /bin/su - rustle -c "cd \$HOME/.config/rstl.sway && ./${1} ${FLAG_YES}" \
            1>"$target/installer.log" 2>&1; then
        tail -40 "$target/installer.log" >&2 || true
        die "${1} failed while running as rustle"
    fi
    printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$ROOTFS/etc/sudoers.d/10-installer"
    chmod 440 "$ROOTFS/etc/sudoers.d/10-installer"
    ok "${1} finished"
}

set_passwords() {
    info "setting login passwords (root + any desktop user) to '$password'"
    chr bash -c "printf 'root:%q\n' \"\$0\" | chpasswd" "$password"
    if grep -q '^rustle:' "$ROOTFS/etc/passwd"; then
        chr bash -c "printf 'rustle:%q\n' \"\$0\" | chpasswd" "$password"
    fi
    printf 'WLR_ALLOW_ROOT=1\n' >> "$ROOTFS/etc/environment" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 6. flavor install
# ---------------------------------------------------------------------------
header "Installing flavor: $flavor"
case "$flavor" in
    install-min)
        chr /bin/sh /root/.config/rstl.sway/install-min.sh $FLAG_YES
        ensure_rustle_user
        # surface the root-staged desktop config for the rustle login too
        home="$ROOTFS/home/rustle"
        rm -rf "$home/.config/rstl.sway"
        cp -a "$ROOTFS/root/.config/rstl.sway" "$home/.config/rstl.sway"
        replicate_symlinks "$ROOTFS/home/rustle"
        chr chown -R rustle:rustle /home/rustle/.config
        printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$ROOTFS/etc/sudoers.d/10-installer"
        chmod 440 "$ROOTFS/etc/sudoers.d/10-installer"
        set_passwords
        ;;

    install-uber-min)
        chr /bin/sh /root/.config/rstl.sway/install-uber-min.sh $FLAG_YES
        ensure_rustle_user
        home="$ROOTFS/home/rustle"
        rm -rf "$home/.config/rstl.sway"
        cp -a "$ROOTFS/root/.config/rstl.sway" "$home/.config/rstl.sway"
        replicate_symlinks "$ROOTFS/home/rustle"
        chr chown -R rustle:rustle /home/rustle/.config
        printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$ROOTFS/etc/sudoers.d/10-installer"
        chmod 440 "$ROOTFS/etc/sudoers.d/10-installer"
        set_passwords
        ;;

    install)
        # install.sh refuses to run as root -> run it as rustle, exactly like
        # rstl-install.sh's install_dotfiles() (NOPASSWD wheel, then restore)
        install_as_rustle install.sh
        set_passwords
        # root's config stays the skel copy (single repo): re-point the link in
        # case the as-rustle flow ever replaced it, then wire the root symlinks
        root_cfg="$ROOTFS/root/.config/rstl.sway"
        rm -f "$root_cfg"
        ln -sfn /etc/skel/.config/rstl.sway "$root_cfg"
        replicate_symlinks "$ROOTFS/root"
        ;;

    rstl-inst)
        install_as_rustle install.sh
        # root's path to the full staged repo (via the skel link; install.sh +
        # rstl-install.sh intact) so the TUI's "Install" ->
        # ~/.config/rstl.sway/rstl-install.sh works
        replicate_symlinks "$ROOTFS/root"
        set_passwords
        ;;
esac

# ---------------------------------------------------------------------------
# 7. rstl-inst TUI (batch 4): boot tty1 straight into the installer TUI
# ---------------------------------------------------------------------------
if [ "$flavor" = "rstl-inst" ]; then
    header "Setting up rstl-inst TUI login"

    # the prebuilt binary, or build it from the submodule checkout
    if [ -n "$rstl_inst_bin" ]; then
        [ -f "$rstl_inst_bin" ] || die "--rstl-inst-bin file not found: $rstl_inst_bin"
        install -Dm755 "$rstl_inst_bin" "$ROOTFS/usr/local/bin/rstl-inst"
    elif [ -d "$REPO/rstl-inst" ] && command -v cargo >/dev/null 2>&1; then
        info "building rstl-inst TUI (rust)"
        ( cd "$REPO/rstl-inst" && cargo build --release )
        install -Dm755 "$REPO/rstl-inst/target/release/rstl-inst" "$ROOTFS/usr/local/bin/rstl-inst"
    else
        die "--flavor rstl-inst needs a binary: pass --rstl-inst-bin or install cargo"
    fi

    # readable fallback that fires up the live sway desktop
    if [ -x "$REPO/archiso/airootfs/usr/local/bin/rstl-live" ]; then
        install -Dm755 "$REPO/archiso/airootfs/usr/local/bin/rstl-live" \
            "$ROOTFS/usr/local/bin/rstl-live"
    fi

    cat > "$ROOTFS/root/.bash_profile" <<'EOPROF'
# rstl-inst runs on tty1 instead of a login manager; "Try Live" starts sway.
if [ -n "$BASH_VERSION" ] && [ "$(tty)" = "/dev/tty1" ] && [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
    export WLR_ALLOW_ROOT=1
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    [ -d "$XDG_RUNTIME_DIR" ] || mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true
    if command -v rstl-inst >/dev/null 2>&1; then
        exec rstl-inst
    fi
    [ -x /usr/local/bin/rstl-live ] && exec /usr/local/bin/rstl-live
fi
EOPROF

    # getty on tty1 takes the console back from greetd
    chr systemctl disable greetd.service >/dev/null 2>&1 || true
    chr systemctl unmask getty@tty1.service >/dev/null 2>&1 || true
    mkdir -p "$ROOTFS/etc/systemd/system/getty@tty1.service.d"
    cat > "$ROOTFS/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin root --noclear %I $TERM
EOF
    ok "tty1 autologin root -> rstl-inst"
fi

# ---------------------------------------------------------------------------
# 8. assemble the frugal directory
# ---------------------------------------------------------------------------
header "Assembling frugal at '$target'"

# --- initrd ---------------------------------------------------------------
# cachyos: rebuild the FirstRib skeleton with this kernel's modules baked in
# (mkFRkernel). vdpup: FirstRib's own initrd-latest.gz is a complete huge-kernel
# initrd already, so it is used unmodified (no mkFRkernel on the vdpup assets).
if [ "$kernel_vdpup" -eq 1 ]; then
    cp -a "$cache/vdpup-initrd.gz" "$target/initrd.gz"
else
    info "building initrd.gz (mkFRkernel)"
    initrd_work="$target/.initrd"
    rm -rf "$initrd_work"
    mkdir -p "$initrd_work"
    (
        cd "$initrd_work"
        "$REPO/mkFRkernel" latest "$ROOTFS" gz >mkFRkernel.log 2>&1 || {
            cat mkFRkernel.log >&2
            exit 1
        }
    )
    mv "$initrd_work/initrd-latest.img" "$target/initrd.gz"
    rm -rf "$initrd_work"
    # Guard: a module-less initrd cannot mount the sfs layers (loop mounts fail
    # and the kernel panics on boot). Fail loudly instead of shipping a brick.
    if ! zcat "$target/initrd.gz" 2>/dev/null | cpio -it 2>/dev/null | grep -q 'block/loop\.ko$'; then
        die "initrd.gz contains no loop kernel module - the frugal would not boot (check mkFRkernel and \$ROOTFS/usr/lib/modules)"
    fi
    ok "initrd.gz carries the loop kernel module"
fi
ok "initrd.gz -> $(du -h "$target/initrd.gz" | cut -f1)"

# --- 00modules.sfs (full module tree) --------------------------------------
# vdpup: FirstRib's own 00modules.sfs is copied unmodified. cachyos: w_init
# mounts NN=00 as an overlay LAYER, so the archive must be laid out at
# usr/lib/modules/... (usrmerge), not at a bare modules/ top-level dir, and is
# squashed at zstd level 19.
if [ "$kernel_vdpup" -eq 1 ]; then
    cp -a "$cache/vdpup-00modules.sfs" "$target/00modules.sfs"
    ok "00modules.sfs (stock vdpup) -> $(du -h "$target/00modules.sfs" | cut -f1)"
    unsquashfs -s "$target/00modules.sfs" 2>/dev/null | grep -m1 Compression | sed 's/^/    /' || true
else
    info "building 00modules.sfs (zstd level 19)"
    modlayer="$target/.00mod"
    rm -rf "$modlayer"
    mkdir -p "$modlayer/usr/lib"
    if [ -n "$opt_modules_source" ]; then
        # --modules-source DIR: reuse a known-good modules tree verbatim (e.g. the
        # FirstRib huge-kernel 00modules dir). Accept as DIR a directory holding the
        # module tree as <DIR>/usr/lib/modules, <DIR>/lib/modules, or directly the
        # <kver> directories. Source must contain the kernel the frugal boots.
        src=""
        for cand in "$opt_modules_source"/usr/lib/modules "$opt_modules_source"/lib/modules "$opt_modules_source"; do
            if [ -d "$cand/$kernelver" ] && [ -n "$(find "$cand/$kernelver" -name '*.ko*' 2>/dev/null | head -1)" ]; then
                src="$cand"
                break
            fi
        done
        [ -n "$src" ] || die "--modules-source $opt_modules_source: no '$kernelver' module tree found (need usr/lib/modules, lib/modules or a bare <kver> dir)"
        cp -a "$src"/. "$modlayer/usr/lib/modules/"
        ok "00modules modules: $src/$kernelver (from --modules-source)"
    else
        cp -a "$ROOTFS/usr/lib/modules" "$modlayer/usr/lib/modules"
        ok "00modules modules: $ROOTFS/usr/lib/modules (from rootfs)"
    fi
    # Optional kernel build tree (build/ -> for dkms / out-of-tree module builds).
    # Auto-use it if present in the module source, or take it explicitly via --modules-build-dir.
    if [ -z "$opt_modules_source" ] || [ ! -d "$modlayer/usr/lib/modules/$kernelver/build" ]; then
        bdir_candidates="${opt_modules_build:-} $(echo "$ROOTFS"/usr/lib/modules/*/build 2>/dev/null) $modlayer/usr/lib/modules/$kernelver/build"
        for bd in $bdir_candidates; do
            [ -n "$bd" ] && [ -f "$bd/Makefile" ] || continue
            kver_build="$modlayer/usr/lib/modules/$kernelver/build"
            mkdir -p "$kver_build"
            cp -a "$bd"/. "$kver_build"/
            break
        done
    fi
    # source is "$modlayer" (NOT "$modlayer/usr"): mksquashfs puts the *contents*
    # of the source dir at the fs root, so squashing usr/ would drop the prefix
    # and produce lib/modules/... which the frugal cannot find under /usr/lib.
    mksquashfs "$modlayer" "$target/00modules.sfs" \
        -noappend -comp zstd -Xcompression-level 19 -no-progress >/dev/null
    rm -rf "$modlayer"
    ok "00modules.sfs -> $(du -h "$target/00modules.sfs" | cut -f1)"
    unsquashfs -s "$target/00modules.sfs" 2>/dev/null | grep -m1 Compression | sed 's/^/    /' || true
fi

# --- 01firmware.sfs (huge-kernel firmware from FirstRib, already zstd 19) --
if [ -n "$opt_firmware" ]; then
    [ -f "$opt_firmware" ] || die "--firmware file not found: $opt_firmware"
    cp -a "$opt_firmware" "$target/01firmware.sfs"
else
    mkdir -p "$cache"
    if [ ! -s "$cache/01firmware.sfs" ]; then
        info "fetching huge-kernel firmware (cached at $cache)"
        fw_url="https://gitlab.com/firstrib/firstrib/-/raw/master/latest/build_system/huge_kernels/kernel_usrmerge_default/01firmware.sfs"
        fetch_fw() {
            [ -s "$cache/01firmware.sfs" ] && return 0
            if command -v curl >/dev/null 2>&1; then
                curl -fL --connect-timeout 30 --max-time 1800 --retry 3 --retry-delay 5 "$fw_url" -o "$cache/01firmware.sfs.part" || return 1
            elif command -v wget >/dev/null 2>&1; then
                wget --timeout=30 --tries=3 -O "$cache/01firmware.sfs.part" "$fw_url" || return 1
            else
                die "need curl or wget to fetch 01firmware.sfs"
            fi
            mv "$cache/01firmware.sfs.part" "$cache/01firmware.sfs"
        }
        if command -v flock >/dev/null 2>&1; then
            ( flock -x 9; fetch_fw ) 9>"$cache/.firmware.lock"
        else
            fetch_fw
        fi
        [ -s "$cache/01firmware.sfs" ] || die "firmware download failed"
    fi
    cp -a "$cache/01firmware.sfs" "$target/01firmware.sfs"
fi
ok "01firmware.sfs -> $(du -h "$target/01firmware.sfs" | cut -f1)"

# --- kernel image ----------------------------------------------------------
if [ "$kernel_vdpup" -eq 1 ]; then
    cp -a "$cache/vdpup-vmlinuz" "$target/vmlinuz"
else
    cp -a "$ROOTFS/boot/vmlinuz-$kernel_pkg" "$target/vmlinuz" 2>/dev/null \
        || cp -a "$(ls -1 "$ROOTFS"/boot/vmlinuz-* 2>/dev/null | head -1)" "$target/vmlinuz"
fi
ok "vmlinuz -> $(du -h "$target/vmlinuz" | cut -f1)"
# modules + firmware ship via the sfs layers at runtime -> drop them from rootfs
rm -rf "$ROOTFS/boot"
rm -rf "$ROOTFS/usr/lib/modules" "$ROOTFS/usr/lib/firmware" 2>/dev/null || true
if [ -d "$ROOTFS/var/cache/pacman/pkg" ]; then rm -rf "$ROOTFS/var/cache/pacman/pkg"/*; fi
if [ -d "$ROOTFS/var/log" ]; then rm -rf "$ROOTFS/var/log"/*; fi

# --- 07rootfs stays as a plain (uncompressed) directory --------------------
# mkfrugal-iso.sh squashes it to 07rootfs.sfs when wrapping the ISO; on disk
# this frugal boots the directory form directly (w_init bind-mounts it).
ok "07rootfs/ kept as a plain directory (mkfrugal-iso.sh squashes it for the ISO)"

# --- GRUB entry snippet ----------------------------------------------------
cat > "$target/grub_config.txt" <<EOF
# rstl.sway frugal boot entry (disk / USB). Replace <ENTER_YOUR_BOOT_PARTITION_UUID>
# with the UUID of the partition that holds '$name' (blkid), and adjust the
# path below if the frugal sits somewhere other than /FRUGALS.
menuentry "rstl.sway (frugal) $name - $flavor" {
    search --no-floppy --fs-uuid --set=root <ENTER_YOUR_BOOT_PARTITION_UUID>
    linux   /FRUGALS/$name/vmlinuz w_bootfrom=UUID=<ENTER_YOUR_BOOT_PARTITION_UUID>=/FRUGALS/$name w_changes=RAM2 logo.nologo
    initrd  /FRUGALS/$name/initrd.gz
}

# Bootable ISO: mkfrugal-iso.sh writes this for you automatically:
#   menuentry "rstl.sway ISO" {
#     search --no-floppy --set=root --label RSTLSW
#     linux   /$name/vmlinuz w_bootfrom=LABEL=RSTLSW=/$name w_changes=RAM2 logo.nologo
#     initrd  /$name/initrd.gz
#   }
EOF
ok "grub_config.txt written"

printf '%s\n' \
    "name:   $name" \
    "flavor: $flavor" \
    "arch:   x86-64-v$arch_level" \
    "kernel: $kernel_pkg ($kernelver)" \
    "build:  $(date -u '+%Y-%m-%d %H:%M UTC')" \
    > "$target/readme_kernel_version.txt"

# ---------------------------------------------------------------------------
# 9. finish
# ---------------------------------------------------------------------------
header "Done"
echo
printf "${C_BOLD}frugal built:${C_RESET} %s\n" "$target"
echo
printf "  desktop logins  root / rustle  (password: ${C_BOLD}%s${C_RESET})\n" "$password"
printf "  changes         boot in RAM only (w_changes=RAM2)\n"
printf "  disk boot       edit and install grub_config.txt (fill in the UUID)\n"
printf "  ISO boot        ./mkfrugal-iso.sh -d '%s' -o rtlsway-%s.iso -l RSTLSW -n %s\n" \
    "$target" "$flavor" "$name"
echo
printf "  NOTE: the frugal was persisted with a well-known default password.\n"
    printf "  After boot, change it with: echo 'user:newpass' | chpasswd\n"

rm -f "$target/installer.log"
exit 0