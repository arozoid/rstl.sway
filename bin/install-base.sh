#!/bin/sh
# rstl.sway dotfiles installer (base / bare minimum)
#
# Bare-minimum sway desktop: no audio/video codecs, no TUIs (rstl-pick,
# bluetui, clipse, wiremix, latuicon), no swayidle/swaylock, no Bluetooth,
# no NetworkManager (uses wpa_cli/wpa_supplicant). Keeps the
# sway/tuigreet/yambar/rofi/foot/mako base.
#
# Usage:
#   bin/install-base.sh                  run every step, confirming each one
#   bin/install-base.sh --yes            run every step without asking
#   bin/install-base.sh --no-cleanup     every step except the last one (cleanup)
#   bin/install-base.sh --firefox        bundle the firefox browser
#   bin/install-base.sh --root           root install (installs into /root)
#   bin/install-base.sh --runit          manage services with runit instead of systemd
#   bin/install-base.sh --systemd        manage services with systemd (default off Void)
#   bin/install-base.sh --help           show this help
#
# The base variant carries no program configuration: the vim/mouse editions are
# install/install-min only, so --program is accepted and ignored here.
# RSTL_FIREFOX=1 / --firefox bundles the firefox browser on top of the base
# desktop.
#
# The distribution is detected from the package manager (arch, fedora, void) and
# recorded in ../.rstl-edition. On Void, runit is the default init system;
# --systemd overrides that, and --runit asks for runit anywhere it is installed.
# Artix is not supported yet: --runit on a system without /etc/sv fails early.
#
# The package list lives next to the repository root, in
# ../packages-install-base.txt, and the edition this run installed is recorded in
# ../.rstl-edition. bin/update.sh re-runs this installer to bring an existing
# installation up to date.

set -u

if [ -n "${RSTL_TRACE:-}" ]; then
    set -x
    export PS4='+[install-base:$LINENO] '
fi

RSTL_FIREFOX="${RSTL_FIREFOX:-0}"
# kept only so the build can pass it to every flavor; the base desktop has no
# program configuration and never reads it
RSTL_PROGRAM="${RSTL_PROGRAM:-none}"
RSTL_ROOT="${RSTL_ROOT:-0}"

ASSUME_YES=0
SKIP_CLEANUP=0
INIT_GIVEN=0
RUNIT=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes|-y)     ASSUME_YES=1; shift ;;
        --no-cleanup) SKIP_CLEANUP=1; shift ;;
        --program)    [ "$#" -ge 2 ] || { echo "--program needs a value" >&2; exit 2; }
                      shift 2 ;;                 # accepted and ignored (see above)
        --program=*)  shift ;;
        --firefox)    RSTL_FIREFOX=1; shift ;;
        --no-firefox) RSTL_FIREFOX=0; shift ;;
        --root)       RSTL_ROOT=1; shift ;;
        --runit)      RUNIT=1; INIT_GIVEN=1; shift ;;
        --systemd)    RUNIT=0; INIT_GIVEN=1; shift ;;
        --help|-h)    sed -n '2,$ { /^#/!q; s/^#[[:space:]]\{0,1\}//p; }' "$0"; exit 0 ;;
        *)            echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
done
case "$RSTL_FIREFOX" in
    0|1) ;;
    *) echo "RSTL_FIREFOX must be 0 or 1, got: $RSTL_FIREFOX" >&2; exit 2 ;;
esac
case "$RSTL_ROOT" in
    0|1) ;;
    *) echo "RSTL_ROOT must be 0 or 1, got: $RSTL_ROOT" >&2; exit 2 ;;
esac
if [ "$RSTL_ROOT" -eq 1 ] && [ "$(id -u)" -ne 0 ]; then
    echo "--root requires running as root (run this script with sudo)" >&2
    exit 1
fi

# Which distribution this is. The package manager is the reliable signal: a
# chroot/rootfs has no /etc/os-release of its own, but it does have the package
# manager the build installed. Same order as step_2 (xbps, dnf, pacman).
detect_distro() {
    if command -v xbps-install >/dev/null 2>&1; then
        echo void
    elif command -v dnf >/dev/null 2>&1; then
        echo fedora
    elif command -v pacman >/dev/null 2>&1; then
        echo arch
    else
        echo unknown
    fi
}
DISTRO="$(detect_distro)"

# Void runs runit, so that is the default there. --runit asks for it anywhere;
# Artix support is planned but not implemented, so be explicit when /etc/sv is
# missing instead of silently calling systemctl on a system that has no systemd.
if [ "$DISTRO" = "void" ] && [ "$INIT_GIVEN" -eq 0 ]; then
    RUNIT=1
fi
if [ "$RUNIT" -eq 1 ] && [ ! -d /etc/sv ]; then
    echo "--runit needs runit (/etc/sv is missing); Artix support is not implemented yet" >&2
    exit 1
fi

# Which flavor this installer is, and which package list it reads. Both are
# recorded in the edition indicator, so bin/update.sh can re-apply exactly this
# flavor later.
EDITION="install-base"
EDITION_PROGRAM="none"   # the base edition carries no program configuration
PKG_LIST="packages-install-base.txt"
INIT_NAME=systemd
[ "$RUNIT" -eq 1 ] && INIT_NAME=runit
# the step that strips build artifacts; skipped with --no-cleanup
CLEANUP_STEP="step_8"

# The scripts live in bin/ and the package lists sit next to that, in the
# repository root, so REPO_DIR is the checkout this script was started from.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOTFILES_DIR="${HOME}/.config/rstl.sway"

# temp dir for the generated package lists (removed on exit)
GCDIR="$(mktemp -d)"
trap 'rm -rf "$GCDIR"' EXIT

cd "$REPO_DIR"

if [ -t 1 ]; then
    C_RESET='\033[0m' C_BOLD='\033[1m'
    C_PURPLE='\033[95m' C_GREEN='\033[32m'
else
    C_RESET='' C_BOLD='' C_PURPLE='' C_GREEN=''
fi

header() { printf "\n${C_BOLD}${C_PURPLE}== %s${C_RESET}\n" "$*"; }

# The same dashboard art every installer uses. Plain text in assets/ so nvim and
# the shell scripts do not have to parse each other's files.
print_header() {
    art="$REPO_DIR/assets/rstl-header.txt"
    [ -f "$art" ] || return 0
    cols="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
    while IFS= read -r line; do
        indent=$(( (cols - ${#line}) / 2 ))
        [ "$indent" -lt 0 ] && indent=0
        printf "%*s%s\n" "$indent" "" "$line"
    done < "$art"
    echo
}

# ===========================================================================
# helpers
# ===========================================================================
link_file() {
    src="$1"; dest="$2"; use_sudo="${3:-no}"
    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        echo "already linked $dest"
        return 0
    fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        bak="${dest}.bak.$(date +%s)"
        if [ "$use_sudo" = "yes" ]; then run_sudo mv "$dest" "$bak"; else mv "$dest" "$bak"; fi
        echo "moved existing $dest to $bak"
    fi
    if [ "$use_sudo" = "yes" ]; then run_sudo ln -s "$src" "$dest"; else ln -s "$src" "$dest"; fi
    echo "linked $dest -> $src"
}

write_file_once() {
    path="$1"; content="$2"
    mkdir -p "$(dirname "$path")"
    [ -f "$path" ] || printf '%s\n' "$content" > "$path"
}

copy_contents() {
    src="$1"; dst="$2"
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/ 2>/dev/null || true
}

install_cron_entry() {
    pattern="$1"; cron="$2"
    existing="$(crontab -l 2>/dev/null || true)"
    merged="$(printf '%s\n' "$existing" | grep -vE "$pattern" || true)"
    printf '%s\n%s' "$merged" "$cron" | crontab -
}

# cronie's systemd unit is cronie.service on Arch/Void but crond.service on
# Fedora/RHEL, so ask systemd which one this machine has instead of hardcoding
# a name that does not exist on the other distribution. Under runit the service
# lives in /etc/sv; Void's cronie package calls it cronie.
cron_service() {
    if [ "$RUNIT" -eq 1 ]; then
        for svc in cronie crond cron; do
            if [ -d "/etc/sv/$svc" ]; then
                echo "$svc"
                return 0
            fi
        done
        echo cronie
        return 0
    fi
    for unit in cronie.service crond.service cron.service; do
        if systemctl cat "$unit" >/dev/null 2>&1; then
            echo "$unit"
            return 0
        fi
    done
    echo cronie.service
}

remove_path() {
    for p in "$@"; do
        if [ -e "$p" ] || [ -L "$p" ]; then
            rm -rf "$p"
        fi
    done
}

run_sudo() {
    # root installs (--root / rootfs builds) run directly; normal installs use sudo.
    if [ "$(id -u)" -eq 0 ] || [ "$RSTL_ROOT" -eq 1 ]; then
        "$@"
    else
        sudo -v
        sudo "$@"
    fi
}

# ---------------------------------------------------------------------------
# services: systemd (Arch/Fedora) or runit (Void, and --runit elsewhere)
# ---------------------------------------------------------------------------
runit_service() {
    case "$1" in
        greetd.service|greetd)              echo greetd ;;
        NetworkManager.service)             echo NetworkManager ;;
        bluetooth.service|bluetoothd)       echo bluetoothd ;;
        cronie.service|crond.service|cron.service|cronie) echo cronie ;;
        dbus.service|dbus)                  echo dbus ;;
        wpa_supplicant.service)             echo wpa_supplicant ;;
        *)                                  echo "${1%.service}" ;;
    esac
}

service_enable() {
    if [ "$RUNIT" -eq 1 ]; then
        svc="$(runit_service "$1")"
        if [ ! -d "/etc/sv/$svc" ]; then
            echo "  runit service ${svc} not found in /etc/sv" >&2
            return 1
        fi
        run_sudo mkdir -p /var/service
        run_sudo ln -sfn "/etc/sv/$svc" "/var/service/$svc"
    else
        run_sudo systemctl enable "$1"
    fi
}

service_enable_now() {
    if [ "$RUNIT" -eq 1 ]; then
        service_enable "$1" || return 1
        svc="$(runit_service "$1")"
        run_sudo sv up "$svc" >/dev/null 2>&1 ||
            echo "  could not start runit service ${svc} (try: sudo sv up ${svc})" >&2
    else
        run_sudo systemctl enable --now "$1"
    fi
}

service_disable_now() {
    if [ "$RUNIT" -eq 1 ]; then
        svc="$(runit_service "$1")"
        run_sudo sv down "$svc" >/dev/null 2>&1 || true
        [ -e "/var/service/$svc" ] && run_sudo rm -f "/var/service/$svc"
    else
        run_sudo systemctl disable --now "$1" >/dev/null 2>&1 || true
    fi
}

pac_retry() {
    attempt=0
    until run_sudo pacman "$@"; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 3 ]; then
            echo "  pacman $* failed after ${attempt} attempts" >&2
            return 1
        fi
        echo "  pacman $* failed, retrying (${attempt}/3)" >&2
        sleep 2
    done
}

install_or_fallback() {
    pkg="$1"; fallback="$2"
    if run_sudo pacman -Ssq "^${pkg}$" 2>/dev/null | grep -qx "$pkg"; then
        pac_retry -S --needed --noconfirm "$pkg"
    else
        echo "  ${pkg} not found in repos, using ${fallback}"
        pac_retry -S --needed --noconfirm "$fallback"
    fi
}

# add rstl.repo to dnf (fedora/ endpoint)
add_fedora_repo() {
    conf="/etc/yum.repos.d/rstl.repo"
    repo_line="baseurl=https://arozoid.github.io/rstl.repo/fedora/"
    expected="$(printf '[rstl-repo]\n%s\nenabled=1\ngpgcheck=0\n' "$repo_line")"

    # Rewrite the whole file when it differs, so an old [rstl] section, a
    # missing trailing slash or a stale x86_64/ URL is repaired too.
    if [ -f "$conf" ] && [ "$(cat "$conf")" = "$expected" ]; then
        return 0
    fi

    printf '%s\n' "$expected" | run_sudo tee "$conf" >/dev/null
    run_sudo dnf makecache --quiet 2>/dev/null || true
}

# Arch package name -> Fedora package name (only where the names differ).
# dnf has no --needed option and its repoquery reports names, not provides,
# so these renames have to be explicit.
dnf_map_pkg() {
    case "$1" in
        networkmanager)    echo NetworkManager ;;
        bluez-utils)       echo bluez ;;
        pipewire-pulse)    echo pipewire-pulseaudio ;;
        greetd-tuigreet)   echo tuigreet ;;
        xorg-xwayland)     echo xorg-x11-server-Xwayland ;;
        vulkan-icd-loader) echo vulkan-loader ;;
        noto-fonts-emoji)  echo google-noto-color-emoji-fonts ;;
        adwaita-cursors)   echo adwaita-cursor-theme ;;
        mesa)              echo mesa-dri-drivers ;;
        openh264)          echo noopenh264 ;;
        wget)              echo wget2-wget ;;
        *)                 echo "$1" ;;
    esac
}

# dnf4 spells "assume yes" --noconfirm, but dnf5 (Fedora 41+) dropped that flag
# and keeps only the global -y/--assumeyes. -y works on both, so use it.
DNF_YES="-y"

# Cache of the names the enabled repositories offer, filled by step_2. Every
# dnf invocation reloads the repo metadata (about a second on a normal Fedora
# box), so the list is queried once and every lookup greps it.
DNF_REPO_PKGS=""

# Print the name of every package in the enabled repositories, one per line.
# dnf5's --queryformat does not append a newline to each field, so the \n has to
# be part of the format string, otherwise the whole list comes back as one long
# line and nothing ever matches. dnf4 honours the same escape. dnf4 without
# dnf-plugins-core has no repoquery, so fall back to `dnf list`, whose first
# column is name.arch (the section headers have no dot, hence the awk filter).
dnf_repo_names() {
    if dnf repoquery --available --queryformat '%{name}\n' 2>/dev/null; then
        return 0
    fi
    dnf list --quiet 2>/dev/null \
        | awk '$1 ~ /\./ { sub(/\..*/, "", $1); print $1 }' | sort -u
}

# is $1 a package name the enabled repositories provide?
dnf_has_pkg() {
    if [ -n "${DNF_REPO_PKGS:-}" ] && [ -s "$DNF_REPO_PKGS" ]; then
        grep -qxF "$1" "$DNF_REPO_PKGS"
    else
        dnf_repo_names | grep -qxF "$1"
    fi
}

# dnf variant of install_or_fallback
install_or_fallback_dnf() {
    pkg=$(dnf_map_pkg "$1"); fallback=$(dnf_map_pkg "$2")
    if dnf_has_pkg "$pkg"; then
        run_sudo dnf install "$DNF_YES" --allowerasing "$pkg"
    else
        echo "  $1 not found in repos, using $2"
        run_sudo dnf install "$DNF_YES" --allowerasing "$fallback"
    fi
}

# Arch package name -> Void package name (only where the names differ)
xbps_map_pkg() {
    case "$1" in
        networkmanager)    echo NetworkManager ;;
        bluez-utils)       echo bluez ;;
        pipewire-pulse)    echo pipewire ;;
        pipewire-alsa)     echo alsa-pipewire ;;
        greetd-tuigreet)   echo tuigreet ;;
        xorg-xwayland)     echo xorg-server-xwayland ;;
        vulkan-icd-loader) echo vulkan-loader ;;
        *)                 echo "$1" ;;
    esac
}

# add rstl.repo to xbps (void/ endpoint)
add_void_repo() {
    conf="/etc/xbps.d/0-rstl.conf"
    repo_line="repository=https://arozoid.github.io/rstl.repo/void"
    if [ -f "$conf" ] && grep -qxF "$repo_line" "$conf"; then
        printf 'y\n' | run_sudo xbps-install -S -y >/dev/null 2>&1 || true
        return 0
    fi
    run_sudo mkdir -p /etc/xbps.d
    printf '%s\n' "$repo_line" | run_sudo tee "$conf" >/dev/null
    # the first sync imports the repository signing key; xbps asks on stdin
    printf 'y\n' | run_sudo xbps-install -S -y >/dev/null 2>&1 || true
}

# xbps variant of install_or_fallback
install_or_fallback_xbps() {
    pkg="$1"; fallback="$2"
    if run_sudo xbps-query -R -p pkgver "$pkg" >/dev/null 2>&1; then
        run_sudo xbps-install -y "$pkg"
    else
        echo "  ${pkg} not found in repos, using ${fallback}"
        run_sudo xbps-install -y "$fallback"
    fi
}

# install the package list $1 in ONE transaction, minus the names the repos do
# not have. pacman resolves every target before installing anything, so a single
# unresolvable name (Arch ships the fd binary as fd-find, CachyOS as fd) aborts
# the whole transaction and silently strips the base layer that every ISO flavor
# is then built on. $2 = core packages that must resolve or the install stops:
# the step runner only warns on failure, so a return code alone would still ship
# a broken image.
pac_install_filtered() {
    list="$1"; core="$2"
    avail="$(mktemp)"
    run_sudo pacman -Ssq > "$avail" 2>/dev/null || : > "$avail"
    wanted=""
    missing=""
    for pkg in $list; do
        if grep -qxF "$pkg" "$avail"; then
            wanted="$wanted $pkg"
        else
            missing="$missing $pkg"
        fi
    done
    rm -f "$avail"
    wanted="${wanted# }"
    missing="${missing# }"
    for pkg in $core; do
        case " $missing " in
            *" $pkg "*)
                echo "  required package '$pkg' is in no enabled repo (stale sync db? try: sudo pacman -Sy)" >&2
                exit 1
                ;;
        esac
    done
    if [ -n "$missing" ]; then
        echo "  not in any enabled repo, skipped:$missing" >&2
    fi
    [ -n "$wanted" ] || return 0
    echo "  installing: $wanted"
    pac_retry -S --needed --noconfirm $wanted
}

confirm() {
    if [ "$ASSUME_YES" -eq 1 ]; then
        echo "  [auto-yes] $1"
        return 0
    fi
    printf "  %s [Y/n] " "$1"
    read ans
    case "$ans" in
        ""|[yY]|[yY][eE][sS]) return 0 ;;
        *) echo "  skipped" ; return 1 ;;
    esac
}

# prefix any line of the sway config file $1 (relative to sway/) holding
# literal $2 with "# [base] " (idempotent)
sway_comment() {
    cfg="$DOTFILES_DIR/sway/$1"
    lit="$2"
    [ -f "$cfg" ] || { echo "sway config missing: $cfg" >&2; return 1; }
    rm -f "$cfg.new"
    while IFS= read -r line; do
        case "$line" in
            \#*) printf '%s\n' "$line" ;;
            *"$lit"*) printf '# [base] %s\n' "$line" ;;
            *) printf '%s\n' "$line" ;;
        esac
    done < "$cfg" > "$cfg.new"
    mv -f "$cfg.new" "$cfg"
    echo "commented sway/$1: $lit"
}

# ---------------------------------------------------------------------------
# Package list (../packages-install-base.txt)
# ---------------------------------------------------------------------------
# The list is data, not code, so it lives in a plain text file next to the
# repository root: reviewing a package change is a one-file diff, and
# bin/update.sh reads the same file. Sections:
#   #@core             one atomic transaction (a name that does not resolve is
#                      reported and left out, never voids the transaction)
#   #@optional         one package at a time (rstl-repo extras)
#   #@program:<name>   the RSTL_PROGRAM / --program configuration
#   #@firefox          RSTL_FIREFOX=1 / --firefox
list_core() {
  awk '
    /^#@/ { sect = substr($0, 3); next }
    /^#/  { next }
    NF == 0 { next }
    sect == "core" { print }
  ' "$REPO_DIR/$PKG_LIST"
}

# Everything that is installed one package at a time: the optional tier plus
# the program and firefox sections. A name that does not resolve here skips
# only itself.
# NOTE: the parentheses are required. In awk, concatenation binds looser than
# ==, so "sect == \"program:\" program" parses as "(sect == \"program:\") program"
# and would match every section instead of just the program one.
list_each() {
  awk -v program="$RSTL_PROGRAM" -v firefox="$RSTL_FIREFOX" '
    /^#@/ { sect = substr($0, 3); next }
    /^#/  { next }
    NF == 0 { next }
    sect == "optional"                  { print }
    sect == ("program:" program)        { print }
    sect == "firefox" && firefox == "1" { print }
  ' "$REPO_DIR/$PKG_LIST"
}

# ===========================================================================
# Copying the repository into ~/.config/rstl.sway
# ===========================================================================
# Two rules, and they are the reason this is not just `cp -a`:
#
#   1. .git is never copied. A checkout's history belongs to the machine that
#      made it: bin/update.sh installs from a fresh `git clone --depth 1`, and
#      copying its .git over a real checkout would replace the user's history
#      (and, with */.git, their submodule registrations) with a shallow copy of
#      someone else's. The ISO/rootfs builds purge .git the same way, see
#      copy_repo in mkfrugal-rstl.sh.
#
#   2. The paths the installers own are purged BEFORE the copy, so the result is
#      exactly the repository instead of the repository plus whatever an earlier
#      version left behind. That matters most for sway/config.d (the user's
#      settings: a file deleted from the repository must not keep applying), for
#      sway/config plus the package lists and the edition indicator, and for the
#      sway config lines this installer patches in place - without the purge,
#      switching back to a bigger edition would leave the "# [base] " comments
#      behind forever.
#
# Only the paths below are purged. Everything else in the dotfiles directory is
# left alone, so anything you drop in there survives an install.
copy_dotfiles() {
    dest="$DOTFILES_DIR"
    mkdir -p "$dest"
    for owned in sway/config sway/config.d bin ratl \
                 packages-install.txt packages-install-min.txt packages-install-base.txt \
                 .rstl-edition; do
        [ -e "$dest/$owned" ] || continue
        # say it out loud: anything of yours in these paths is replaced by the
        # repository's version, on purpose
        echo "purging $dest/$owned (replaced by the repository copy)"
        rm -rf "${dest:?}/$owned"
    done
    # tar rather than cp: it is always present, it is what the ISO build uses,
    # and it can leave .git behind with a pattern.
    tar -C "$REPO_DIR" --exclude=./.git --exclude='*/.git' -cf - . \
        | tar -C "$dest" -xf - || {
        echo "copying the dotfiles from $REPO_DIR failed" >&2
        return 1
    }
}

# Edition indicator (~/.config/rstl.sway/.rstl-edition)
# ---------------------------------------------------------------------------
# Which flavor installed this dotfiles directory, with which program, so
# bin/update.sh knows what to re-apply. Rewritten from scratch on every run
# (never merged with whatever was there) and git-ignored: it describes the
# machine, not the repository.
write_edition() {
  target="$DOTFILES_DIR/.rstl-edition"
  if ! {
    printf '# written by bin/install-base.sh, read by bin/update.sh - do not edit\n'
    printf 'edition=%s\n'   "$EDITION"
    printf 'program=%s\n'   "$EDITION_PROGRAM"
    printf 'firefox=%s\n'   "$RSTL_FIREFOX"
    printf 'distro=%s\n'    "$DISTRO"
    printf 'init=%s\n'      "$INIT_NAME"
    printf 'dotfiles=%s\n'  "$DOTFILES_DIR"
    printf 'packages=%s\n'  "$PKG_LIST"
    printf 'installed=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)"
  } > "$target" 2>/dev/null; then
    echo "  could not write the edition indicator ${target}" >&2
    return 1
  fi
  echo "  edition recorded in ${target} (${EDITION}, ${DISTRO}/${INIT_NAME}, program ${EDITION_PROGRAM})"
}

# ===========================================================================
# steps
# ===========================================================================
step_0() {
    header "sudo privileges"
    if [ "$(id -u)" -eq 0 ] || [ "$RSTL_ROOT" -eq 1 ]; then
        echo "running as root; sudo not needed"
        return 0
    fi
    sudo -n true 2>/dev/null || sudo -v
}

step_1() {
    header "copy dotfiles"
    # true when invoked from $DOTFILES_DIR (or a path that resolves to it, e.g.
    # /root/.config/rstl.sway symlinked into /etc/skel) - nothing to copy then
    if [ "$(readlink -f "$REPO_DIR" 2>/dev/null)" != "$(readlink -f "$DOTFILES_DIR" 2>/dev/null)" ]; then
        copy_dotfiles || return 1
        echo "copied dotfiles to $DOTFILES_DIR"
    else
        echo "dotfiles already at $DOTFILES_DIR"
    fi
    mkdir -p "$DOTFILES_DIR"
    chmod +x "$DOTFILES_DIR"/scripts/*.sh "$DOTFILES_DIR"/bin/*.sh \
        "$DOTFILES_DIR"/ratl/rstl-* 2>/dev/null || true

    # record which flavor (and program) owns this dotfiles dir; bin/update.sh
    # reads it back to know what to re-apply
    write_edition

    if [ -f "$DOTFILES_DIR/scripts/first-login.sh" ]; then
        run_sudo install -Dm755 "$DOTFILES_DIR/scripts/first-login.sh" /usr/local/bin/rstl-first-login
        run_sudo tee /etc/profile.d/rstl-first-login.sh >/dev/null <<'EOF'
# rstl.sway first-login hook: runs once per user on their first (shell) login.
# The script itself guards on the per-user marker, so it is safe on every login.
[ -n "$HOME" ] || return 0
[ -x /usr/local/bin/rstl-first-login ] && /usr/local/bin/rstl-first-login
EOF
        run_sudo chmod 644 /etc/profile.d/rstl-first-login.sh
        echo "installed rstl-first-login + profile.d hook"
    fi

    # the `rstl` wrapper: run any script in bin/ or ratl/ by name
    # (rstl install.sh --yes, rstl rstl-settings). Installed system-wide so it
    # works from any directory.
    if [ -f "$DOTFILES_DIR/bin/rstl" ]; then
        run_sudo install -Dm755 "$DOTFILES_DIR/bin/rstl" /usr/local/bin/rstl
        echo "installed the rstl wrapper (/usr/local/bin/rstl)"
    fi
}

step_2() {
    header "install packages"

    # DISTRO was detected from the package manager at startup and recorded in
    # .rstl-edition. xbps (Void) and dnf (Fedora) win over pacman if more than
    # one happens to exist.
    case "$DISTRO" in
    void)
        add_void_repo
        PKG_MGR=xbps
        ;;
    fedora)
        add_fedora_repo
        PKG_MGR=dnf
        ;;
    arch)
        conf="/etc/pacman.conf"
        if ! grep -qF "[rstl-repo]" "$conf" 2>/dev/null; then
            printf '\n[rstl-repo]\nSigLevel = Optional TrustAll\nServer = https://arozoid.github.io/rstl.repo/arch/\n' \
                | run_sudo tee -a "$conf" >/dev/null
            pac_retry -Sy --noconfirm
        fi

        # 32 bit libraries, so lib32-* packages can be installed. A pacman.conf
        # that already has an active [multilib] is left alone. Otherwise the
        # block is appended: the mirrorlist when pacman-mirrorlist is installed,
        # the official geo mirror when it is not, because an [multilib] whose
        # Include file is missing has no mirror at all and every install from it
        # fails with a confusing "target not found".
        if ! grep -q '^\[multilib\]' "$conf" 2>/dev/null; then
            if [ -f /etc/pacman.d/mirrorlist ]; then
                mirror="Include = /etc/pacman.d/mirrorlist"
            else
                mirror='Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch'
            fi
            printf '\n[multilib]\n%s\n' "$mirror" | run_sudo tee -a "$conf" >/dev/null
            pac_retry -Sy --noconfirm
            echo "multilib enabled in $conf"
        else
            echo "multilib already enabled in $conf"
        fi
        PKG_MGR=pacman
        if [ -f "$REPO_DIR/scripts/pacman-cachyos.sh" ]; then
            sh "$REPO_DIR/scripts/pacman-cachyos.sh" ||
                echo "could not apply the CachyOS pacman output options" >&2
        fi
        ;;
    *)
        echo "neither xbps, pacman nor dnf found, skipping package installation" >&2
        return 1
        ;;
    esac

    # the package list is data: ../packages-install-base.txt, next to the
    # repository root. #@core goes in one atomic transaction, everything else
    # one package at a time. See list_core()/list_each() for the section format.
    if [ ! -f "$REPO_DIR/$PKG_LIST" ]; then
        echo "package list $REPO_DIR/$PKG_LIST is missing" >&2
        return 1
    fi
    list_core > "$GCDIR/packages"
    list_each > "$GCDIR/packages-extra"

    # dssd is one provider of org.freedesktop.secrets. If another one is already
    # installed or running, installing dssd would make two providers fight over
    # the same D-Bus name (and usually the same service file), so leave it out.
    if [ -f "$REPO_DIR/scripts/secret-service-present.sh" ] &&
       sh "$REPO_DIR/scripts/secret-service-present.sh" >/dev/null 2>&1; then
        for list in "$GCDIR/packages" "$GCDIR/packages-extra"; do
            awk '$0 != "dssd"' "$list" > "$list.tmp" && mv "$list.tmp" "$list"
        done
        printf "  %s\n" "freedesktop secret service already present; skipping dssd"
    fi

    printf "  %s: %s core, %s per-package\n" \
        "$PKG_LIST" \
        "$(wc -l < "$GCDIR/packages" | tr -d ' ')" \
        "$(wc -l < "$GCDIR/packages-extra" | tr -d ' ')"

    if [ "$PKG_MGR" = "dnf" ]; then
        # dnf resolves every target before installing anything, so filter the
        # list against the repos first. The repository names are queried once
        # and cached, because each dnf call reloads the metadata.
        DNF_REPO_PKGS="$GCDIR/dnf-repo-pkgs"
        if ! dnf_repo_names > "$DNF_REPO_PKGS" || [ ! -s "$DNF_REPO_PKGS" ]; then
            echo "  failed to query enabled repositories with dnf (try: sudo dnf makecache)" >&2
            DNF_REPO_PKGS=""
            return 1
        fi
        wanted=""
        missing=""
        for pkg in $(cat "$GCDIR/packages"); do
            name=$(dnf_map_pkg "$pkg")
            if dnf_has_pkg "$name"; then
                wanted="$wanted $name"
            else
                missing="$missing $name"
            fi
        done
        # bluez and bluez-utils both map to bluez, so drop the duplicates
        wanted=$(printf '%s\n' $wanted | sort -u | tr '\n' ' ')
        wanted="${wanted% }"
        missing="${missing# }"

        for pkg in sway greetd tuigreet foot mako rofi; do
            case " $missing " in
                *" $pkg "*)
                    echo "  required package '$pkg' is in no enabled repo (stale sync db? try: sudo dnf makecache)" >&2
                    exit 1
                    ;;
            esac
        done

        if [ -n "$missing" ]; then
            echo "  not in any enabled repo, skipped:$missing" >&2
        fi

        if [ -n "$wanted" ]; then
            echo "  installing: $wanted"
            # shellcheck disable=SC2086  # $wanted is a list of names on purpose
            run_sudo dnf install "$DNF_YES" --allowerasing $wanted
        fi

        for pm in $(cat "$GCDIR/packages-extra"); do
            name=$(dnf_map_pkg "$pm")
            if dnf_has_pkg "$name"; then
                run_sudo dnf install "$DNF_YES" --allowerasing "$name"
            else
                printf "  %s not found in repos, skipping\n" "$pm"
            fi
        done

        install_or_fallback_dnf notwaita-cursors-grey adwaita-cursors
    elif [ "$PKG_MGR" = "xbps" ]; then
        # void path: xbps has no cheap "list every repo package" query, so test
        # each name individually. Arch names are mapped to Void names first and
        # deduplicated (pipewire + pipewire-pulse, bluez + bluez-utils).
        while IFS= read -r pkg; do
            [ -n "$pkg" ] || continue
            xbps_map_pkg "$pkg"
        done < "$GCDIR/packages" | sort -u > "$GCDIR/packages-xbps"

        wanted=""
        missing=""
        while IFS= read -r name; do
            [ -n "$name" ] || continue
            if run_sudo xbps-query -R -p pkgver "$name" >/dev/null 2>&1; then
                wanted="$wanted $name"
            else
                missing="$missing $name"
            fi
        done < "$GCDIR/packages-xbps"

        for pkg in sway greetd tuigreet foot mako rofi; do
            case " $missing " in
                *" $pkg "*)
                    echo "  required package '$pkg' is in no enabled repo (stale sync db? try: sudo xbps-install -S)" >&2
                    exit 1
                    ;;
            esac
        done

        if [ -n "$missing" ]; then
            echo "  not in any enabled repo, skipped:$missing" >&2
        fi

        [ -n "$wanted" ] || return 0
        echo "  installing: $wanted"
        run_sudo xbps-install -y $wanted

        for pm in $(cat "$GCDIR/packages-extra"); do
            name=$(xbps_map_pkg "$pm")
            if run_sudo xbps-query -R -p pkgver "$name" >/dev/null 2>&1; then
                run_sudo xbps-install -y "$name"
            else
                printf "  %s not found in repos, skipping\n" "$pm"
            fi
        done

        install_or_fallback_xbps notwaita-cursors-grey xcursor-themes
    else
        pac_install_filtered "$(cat "$GCDIR/packages")" \
            "sway greetd greetd-tuigreet foot mako rofi"

        # base has no program config; an optional firefox bundle is still honored
        # and installed one at a time so a missing package skips instead of aborting
        for pm in $(cat "$GCDIR/packages-extra"); do
            if run_sudo pacman -Ssq "^${pm}$" 2>/dev/null | grep -qx "$pm"; then
                pac_retry -S --needed --noconfirm "$pm"
            else
                printf "  %s not found in repos, skipping\n" "$pm"
            fi
        done

        # note: intentionally omitted from the base variant: swaylock/swayidle,
        # networkmanager, bluez/bluez-utils (wpa_cli via wpa_supplicant instead),
        # all audio/video codecs (flac mpg123 opus libvorbis speex speexdsp sbc
        # dav1d libvpx openh264), and the TUIs (rstl-pick, bluetui, clipse,
        # wiremix, latuicon). cliphist replaces clipse as the clipboard store.

        install_or_fallback notwaita-cursors-grey adwaita-cursors
    fi

    echo "packages installed"
}

step_3() {
    header "symlink dotfiles"
    link_file "$DOTFILES_DIR/sway"     "$HOME/.config/sway"
    link_file "$DOTFILES_DIR/yambar"   "$HOME/.config/yambar"
    link_file "$DOTFILES_DIR/rofi"     "$HOME/.config/rofi"
    link_file "$DOTFILES_DIR/foot"     "$HOME/.config/foot"
    link_file "$DOTFILES_DIR/mako"     "$HOME/.config/mako"
    if [ "${PKG_MGR:-}" = "pacman" ]; then
        link_file "$DOTFILES_DIR/yay"  "$HOME/.config/yay"
    fi
    link_file "$DOTFILES_DIR/.zshrc"   "$HOME/.zshrc"
    link_file "$DOTFILES_DIR/greetd"   "/etc/greetd" yes

    copy_contents "$DOTFILES_DIR/portal" \
        "$HOME/.config/xdg-desktop-portal-termfilechooser"
    chmod +x "$HOME/.config/xdg-desktop-portal-termfilechooser/fm-wrapper.sh"

    write_file_once "$HOME/.config/xdg-desktop-portal/portals.conf" \
        '[preferred]
org.freedesktop.impl.portal.FileChooser=termfilechooser'
    echo "configured file chooser portal"

    # base has no swayidle/swaylock -> patch the SHARED sway config (used by
    # every flavor) so the base desktop does not exec missing binaries. The
    # lock binding lives in sway/config, the daemons in config.d/40-autostart.
    echo "patching sway config for base (no idling/lock/clip daemon)"
    sway_comment "config" "scripts/lock.sh"
    sway_comment "config.d/40-autostart.conf" "scripts/swayidle.sh"
    # cliphist is an on-demand clipboard store (no boot daemon): drop the
    # clipse listener line from the shared config.
    sed -i '/exec --no-startup-id clipse -listen/d' \
        "$DOTFILES_DIR/sway/config.d/40-autostart.conf"
    echo "sway config patched for base"
}

step_4() {
    header "greetd + tuigreet"
    [ -e /etc/greetd/config.toml ] || { echo "/etc/greetd/config.toml missing"; return 1; }

    if ! id greeter >/dev/null 2>&1; then
        run_sudo useradd -r -M -G video -d /var/lib/greetd -s /usr/sbin/nologin greeter
        run_sudo mkdir -p /var/lib/greetd
        run_sudo chown greeter:greeter /var/lib/greetd
    else
        run_sudo usermod -aG video greeter
    fi

    run_sudo chmod -R go+r /etc/greetd
    run_sudo sed -i 's/^auth.*pam_securetty.so/# &/' /etc/pam.d/greetd

    # Ensure GNOME Keyring unlocks on login/session so secrets are available
    # even when gnome-keyring (instead of dssd) is the secret service backend.
    run_sudo sh -c 'grep -q "pam_gnome_keyring.so" /etc/pam.d/greetd || cat >> /etc/pam.d/greetd <<EOF

# GNOME Keyring integration
auth      optional  pam_gnome_keyring.so
session   optional  pam_gnome_keyring.so auto_start
EOF'
    service_enable_now greetd.service
    if [ "$RUNIT" -eq 1 ]; then
        run_sudo sv down agetty-tty1 >/dev/null 2>&1 || true
        [ -e /var/service/agetty-tty1 ] && run_sudo rm -f /var/service/agetty-tty1
    else
        run_sudo systemctl mask getty@tty1.service >/dev/null 2>&1 || true
    fi
    echo "greetd configured (${INIT_NAME})"
}

step_5() {
    header "wallpaper"
    wp_dir="$HOME/Pictures/Wallpapers"
    wp_conf="$DOTFILES_DIR/wallpaper"
    wp_file="$wp_dir/wallpaper.jpg"
    mkdir -p "$wp_dir"

    write_file_once "$wp_conf" "~/Pictures/Wallpapers/wallpaper.jpg"
    if [ ! -f "$wp_file" ] && [ -f "$DOTFILES_DIR/wallpapers/Kiki's Delievery Service.jpg" ]; then
        cp "$DOTFILES_DIR/wallpapers/Kiki's Delievery Service.jpg" "$wp_file"
    fi
    echo "wallpaper set up"
}

step_6() {
    header "battery alerts"
    command -v crontab >/dev/null 2>&1 || { echo "crontab not found, skipping"; return 1; }
    service_enable_now "$(cron_service)" >/dev/null 2>&1 || true

    uid="$(id -u)"
    cron="# rstl.sway battery alerts (40% / 80%)
SHELL=/bin/bash
XDG_RUNTIME_DIR=/run/user/${uid}
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus

* * * * * ${DOTFILES_DIR}/scripts/batt.sh >/dev/null 2>&1
"
    install_cron_entry 'batt\.sh' "$cron"
    echo "battery alerts enabled"
}

step_7() {
    header "final preferences"
    user="$(id -un)"
    if [ "$(id -u)" -ne 0 ]; then
        if [ "$RUNIT" -eq 1 ]; then
            echo "runit: per-user pipewire services are started from the sway session"
        else
            run_sudo loginctl enable-linger "$user"
            sudo -u "$user" systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1 || true
        fi
    else
        echo "running as root; skipping user linger and pipewire services"
    fi
    # base uses wpa_supplicant/wpa_cli instead of NetworkManager; no bluetooth
    if [ "$RUNIT" -eq 1 ]; then
        service_enable_now dbus.service
    fi
    service_enable_now wpa_supplicant.service >/dev/null 2>&1 || true
    setup_runit_audio
    echo "services enabled"
    cron="# foot --server standby killer
* * * * * ${DOTFILES_DIR}/scripts/foot-idle.sh >/dev/null 2>&1
    "
    install_cron_entry 'foot-idle\.sh' "$cron"
    echo "foot-idle.sh enabled"
}

# On runit there is no `systemctl --user`: pipewire has to be started by the
# session. WirePlumber and the PulseAudio interface are only loaded when their
# example configs are linked into pipewire's config.d, so do both and add one
# sway autostart line. Under systemd the generated file is removed again, so
# switching init systems does not leave two ways to start the same daemon.
setup_runit_audio() {
    autostart="$DOTFILES_DIR/sway/config.d/90-audio.conf"
    if [ "$RUNIT" -ne 1 ]; then
        [ -e "$autostart" ] && rm -f "$autostart"
        return 0
    fi

    conf_d="$HOME/.config/pipewire/pipewire.conf.d"
    mkdir -p "$conf_d"
    for link in \
        /usr/share/examples/wireplumber/10-wireplumber.conf \
        /usr/share/examples/pipewire/20-pipewire-pulse.conf
    do
        [ -f "$link" ] || continue
        ln -sfn "$link" "$conf_d/${link##*/}"
    done

    cat > "$autostart" <<'EOF'
# generated by bin/install-base.sh --runit (and by the Void default): runit has
# no per-user service manager, so the session starts pipewire, which in turn
# loads wireplumber and pipewire-pulse from ~/.config/pipewire/pipewire.conf.d.
exec_always --no-startup-id sh -c 'command -v pipewire >/dev/null 2>&1 || exit 0; pgrep -x pipewire >/dev/null 2>&1 || pipewire >/dev/null 2>&1 &'
EOF
    echo "session audio autostart written to $autostart"
}

step_8() {
    header "cleanup"
    remove_path \
        "$DOTFILES_DIR/wallpapers" \
        "$DOTFILES_DIR/depsize" \
        "$DOTFILES_DIR/nvim" \
        "$DOTFILES_DIR/rstl-inst" \
        "$DOTFILES_DIR/rstl-pick" \
        "$DOTFILES_DIR/ranger/.git" \
        "$DOTFILES_DIR/waybar" \
        "$DOTFILES_DIR/packages.txt" \
        "$DOTFILES_DIR/README.md" \
        "$DOTFILES_DIR/MANUAL_INSTALL.md" \
        "$DOTFILES_DIR/.git" \
        "$DOTFILES_DIR/.gitmodules" \
        "$DOTFILES_DIR/fastfetch" \
        "$DOTFILES_DIR/fish"
    # deliberately NOT removed: bin/ (bin/update.sh re-runs this installer to
    # update the machine), packages-install*.txt (the lists the installers read)
    # and .rstl-edition (which flavor this machine runs).

    find "$DOTFILES_DIR" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

    if command -v pacman >/dev/null 2>&1; then
        run_sudo pacman -Rns --noconfirm $(pacman -Qdtq 2>/dev/null) >/dev/null 2>&1 || true
        run_sudo pacman -Scc --noconfirm >/dev/null 2>&1 || true
        run_sudo rm -rf /var/cache/pacman/pkg/* 2>/dev/null || true
    elif command -v xbps-remove >/dev/null 2>&1; then
        run_sudo xbps-remove -oy >/dev/null 2>&1 || true
        run_sudo xbps-remove -OO >/dev/null 2>&1 || true
    fi

    # ---- optional size purge (drops dev/tooling; keeps a working desktop) ----
    purge_trim() {
        rm -rf /usr/include 2>/dev/null || true
        find /usr/lib -type f -name "*.a" -delete 2>/dev/null || true
        rm -rf /usr/lib/pkgconfig /usr/lib/ldscripts /usr/share/pkgconfig 2>/dev/null || true
        rm -f /usr/lib/libasan.so* /usr/lib/libtsan.so* 2>/dev/null || true
        rm -rf /usr/lib/gprofng* 2>/dev/null || true
        rm -rf /usr/share/gir-1.0 /usr/share/gtk-doc /usr/share/vala /usr/share/licenses 2>/dev/null || true
        if command -v strip >/dev/null 2>&1 && [ ! -e /etc/.rstl-sway-rootfs ] && [ "$RSTL_ROOT" -ne 1 ]; then
            # Rootfs builds defer the ELF strip to mkfrugal-rstl.sh (host-side,
            # after the chroot teardown): stripping the chroot's *live*
            # interpreter/libraries in-place has been observed to segfault the
            # chrooted bash at exit under CI. Real installs (no rootfs marker)
            # keep stripping here.
            find /usr/bin /usr/lib -type f \( -executable -o -name "*.so*" \) \
                -exec strip --strip-unneeded {} + 2>/dev/null || true
        fi
    }
    run_sudo purge_trim

    echo "cleaned up"
}

# ===========================================================================
if [ "$(id -u)" -eq 0 ] && [ "$RSTL_ROOT" -ne 1 ] && [ ! -e /etc/.rstl-sway-rootfs ]; then
    echo "Error: do not run as root. Run as your normal user (sudo is used when needed)." >&2
    echo "For an intentional root install pass --root." >&2
    exit 1
fi

print_header

while IFS='|' read -r num label question func <&3; do
    if [ "$func" = "$CLEANUP_STEP" ] && [ "$SKIP_CLEANUP" -eq 1 ]; then
        # bin/update.sh re-runs the installer to refresh the dotfiles; the
        # cleanup step is a build-time size optimization (orphan removal, cache
        # purge, dev headers) and must not run against a live desktop.
        echo "  step $num ($label) skipped: --no-cleanup"
        echo
        continue
    fi
    if confirm "$question"; then
        "$func"
    fi
    echo
done 3<<'EOF'
0|ensure sudo privileges|Ensure sudo privileges?|step_0
1|copy dotfiles to ~/.config/rstl.sway|Copy dotfiles into ~/.config/rstl.sway?|step_1
2|install required packages|Install all required packages?|step_2
3|symlink dotfile directories|Symlink dotfile directories to their proper paths?|step_3
4|greetd + tuigreet setup|Set up greetd + tuigreet as the login manager?|step_4
5|wallpaper setup|Set up the wallpaper?|step_5
6|battery alerts (40% / 80%)|Set up the 40% / 80% battery alerts (batt.sh)?|step_6
7|final preferences|Enable lingering, pipewire, wpa_supplicant?|step_7
8|cleanup|Remove build artifacts and caches from the dotfiles?|step_8
EOF

echo
echo "Done. Next: reboot (or log out) to start greetd -> sway."
