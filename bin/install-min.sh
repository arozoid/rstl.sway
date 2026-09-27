#!/bin/sh
# rstl.sway dotfiles installer for Arch Linux (minimal)
#
# Usage:
#   bin/install-min.sh                  run every step, confirming each one
#   bin/install-min.sh --yes            run every step without asking
#   bin/install-min.sh --no-cleanup     every step except the last one (cleanup)
#   bin/install-min.sh --program mouse  pick the program's file manager
#   bin/install-min.sh --firefox        bundle the firefox browser
#   bin/install-min.sh --help           show this help
#
# The package list lives next to the repository root, in
# ../packages-install-min.txt, and the edition this run installed is recorded in
# ../.rstl-edition. bin/update.sh re-runs this installer to bring an existing
# installation up to date.

set -u

if [ -n "${RSTL_TRACE:-}" ]; then
    set -x
    export PS4='+[install-min:$LINENO] '
fi

# Program configuration. The ISO build picks it through the environment
# (mkfrugal-rstl.sh --program), a person installing it with --program. The
# minimal variant keeps ONLY the program's file manager (no editor bundle):
#   vim   = superfile (spf)
#   mouse = rovr
# RSTL_FIREFOX=1 / --firefox bundles the firefox browser on top.
RSTL_PROGRAM="${RSTL_PROGRAM:-vim}"
RSTL_FIREFOX="${RSTL_FIREFOX:-0}"

ASSUME_YES=0
SKIP_CLEANUP=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes|-y)     ASSUME_YES=1; shift ;;
        --no-cleanup) SKIP_CLEANUP=1; shift ;;
        --program)    [ "$#" -ge 2 ] || { echo "--program needs a value" >&2; exit 2; }
                      RSTL_PROGRAM="$2"; shift 2 ;;
        --program=*)  RSTL_PROGRAM="${1#*=}"; shift ;;
        --firefox)    RSTL_FIREFOX=1; shift ;;
        --no-firefox) RSTL_FIREFOX=0; shift ;;
        --help|-h)    sed -n '2,15p' "$0"; exit 0 ;;
        *)            echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
done
case "$RSTL_PROGRAM" in
    vim|mouse) ;;
    *) echo "unknown program: $RSTL_PROGRAM (vim, mouse)" >&2; exit 2 ;;
esac
case "$RSTL_FIREFOX" in
    0|1) ;;
    *) echo "RSTL_FIREFOX must be 0 or 1, got: $RSTL_FIREFOX" >&2; exit 2 ;;
esac

# Which flavor this installer is, and which package list it reads. Both are
# recorded in the edition indicator, so bin/update.sh can re-apply exactly this
# flavor later.
EDITION="install-min"
EDITION_PROGRAM="$RSTL_PROGRAM"
PKG_LIST="packages-install-min.txt"
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

# Operate from the dotfiles repo regardless of how/where the script was
# invoked (e.g. from a chroot as /root/.config/rstl.sway/bin/install-min.sh).
cd "$REPO_DIR"

if [ -t 1 ]; then
    C_RESET='\033[0m' C_BOLD='\033[1m'
    C_PURPLE='\033[95m' C_GREEN='\033[32m'
else
    C_RESET='' C_BOLD='' C_PURPLE='' C_GREEN=''
fi

header() { printf "\n${C_BOLD}${C_PURPLE}== %s${C_RESET}\n" "$*"; }

# ===========================================================================
# helpers
# ===========================================================================

# symlink src -> dest; back up anything already at dest. $3 = "yes" for sudo.
link_file() {
    src="$1"; dest="$2"; use_sudo="${3:-no}"

    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        echo "already linked $dest"
        return 0
    fi
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        bak="${dest}.bak.$(date +%s)"
        if [ "$use_sudo" = "yes" ]; then sudo mv "$dest" "$bak"; else mv "$dest" "$bak"; fi
        echo "moved existing $dest to $bak"
    fi
    if [ "$use_sudo" = "yes" ]; then sudo ln -s "$src" "$dest"; else ln -s "$src" "$dest"; fi
    echo "linked $dest -> $src"
}

# write $2 to $1 only if $1 does not yet exist
write_file_once() {
    path="$1"; content="$2"
    mkdir -p "$(dirname "$path")"
    [ -f "$path" ] || printf '%s\n' "$content" > "$path"
}

# copy the contents of $1 into $2 (creating $2 if needed)
copy_contents() {
    src="$1"; dst="$2"
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/ 2>/dev/null || true
}

# append $2 (a crontab entry) into the user crontab, removing any old one
# matching $1 (a grep pattern used to strip stale lines)
install_cron_entry() {
    pattern="$1"; cron="$2"
    existing="$(crontab -l 2>/dev/null || true)"
    merged="$(printf '%s\n' "$existing" | grep -vE "$pattern" || true)"
    printf '%s\n%s' "$merged" "$cron" | crontab -
}

# remove every path given (files, dirs, symlinks), quietly
remove_path() {
    for p in "$@"; do
        if [ -e "$p" ] || [ -L "$p" ]; then
            rm -rf "$p"
        fi
    done
}

# ---------------------------------------------------------------------------
# Package list (../packages-install-min.txt)
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
    for owned in sway/config sway/config.d bin \
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
    printf '# written by bin/install-min.sh, read by bin/update.sh - do not edit\n'
    printf 'edition=%s\n'   "$EDITION"
    printf 'program=%s\n'   "$EDITION_PROGRAM"
    printf 'firefox=%s\n'   "$RSTL_FIREFOX"
    printf 'dotfiles=%s\n'  "$DOTFILES_DIR"
    printf 'packages=%s\n'  "$PKG_LIST"
    printf 'installed=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)"
  } > "$target" 2>/dev/null; then
    echo "  could not write the edition indicator ${target}" >&2
    return 1
  fi
  echo "  edition recorded in ${target} (${EDITION}, program ${EDITION_PROGRAM})"
}

# ===========================================================================
# top-level steps (dishonest: may read globals / require sudo)
# ===========================================================================
run_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo -v
        sudo "$@"
    fi
}

# retry a pacman transaction against transient download failures
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

# install $1 if it exists in the (synced) repos, otherwise install the $2 fallback
install_or_fallback() {
    pkg="$1"; fallback="$2"
    if run_sudo pacman -Ssq "^${pkg}$" 2>/dev/null | grep -qx "$pkg"; then
        pac_retry -S --needed --noconfirm "$pkg"
    else
        echo "  ${pkg} not found in repos, using ${fallback}"
        pac_retry -S --needed --noconfirm "$fallback"
    fi
}

# install the package list $1 in ONE transaction, minus the names the repos do
# not have. pacman resolves every target before installing anything, so a single
# unresolvable name (Arch ships the fd binary as fd-find, CachyOS as fd) aborts
# the whole transaction and silently strips the desktop. $2 = core packages that
# must resolve or the install stops: the step runner only warns on failure, so a
# return code alone would still ship a broken image.
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

step_0() {
    header "sudo privileges"
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
    chmod +x "$DOTFILES_DIR"/scripts/*.sh "$DOTFILES_DIR"/bin/*.sh 2>/dev/null || true

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

    # the `rstl` wrapper: run any script in bin/ by name (rstl install.sh --yes,
    # rstl update.sh). Installed system-wide so it works from any directory.
    if [ -f "$DOTFILES_DIR/bin/rstl" ]; then
        run_sudo install -Dm755 "$DOTFILES_DIR/bin/rstl" /usr/local/bin/rstl
        echo "installed the rstl wrapper (/usr/local/bin/rstl)"
    fi
}

step_2() {
    header "install packages"
    command -v pacman >/dev/null 2>&1 || {
        echo "pacman not found, skipping (requires Arch Linux)"
        return 1
    }

    conf="/etc/pacman.conf"
    if ! grep -qF "[rstl-repo]" "$conf" 2>/dev/null; then
        printf '\n[rstl-repo]\nSigLevel = Optional TrustAll\nServer = https://arozoid.github.io/rstl.repo\n' \
            | run_sudo tee -a "$conf" >/dev/null
        pac_retry -Sy --noconfirm
    fi

    # the package list is data: ../packages-install-min.txt, next to the repository root.
    # #@core goes in one atomic transaction, everything else one package at a
    # time. See list_core()/list_each() for the section format.
    if [ ! -f "$REPO_DIR/$PKG_LIST" ]; then
        echo "package list $REPO_DIR/$PKG_LIST is missing" >&2
        return 1
    fi
    list_core > "$GCDIR/packages"
    list_each > "$GCDIR/packages-extra"
    printf "  %s: %s core, %s per-package (program: %s)\n" \
        "$PKG_LIST" \
        "$(wc -l < "$GCDIR/packages" | tr -d ' ')" \
        "$(wc -l < "$GCDIR/packages-extra" | tr -d ' ')" \
        "$RSTL_PROGRAM"

    pac_install_filtered "$(cat "$GCDIR/packages")" \
        "sway greetd greetd-tuigreet foot mako rofi"

    # the program file manager (vim = superfile, mouse = rovr) and firefox:
    # installed one at a time so a missing package skips instead of aborting
    for pm in $(cat "$GCDIR/packages-extra"); do
        if run_sudo pacman -Ssq "^${pm}$" 2>/dev/null | grep -qx "$pm"; then
            pac_retry -S --needed --noconfirm "$pm"
        else
            printf "  %s not found in repos, skipping\n" "$pm"
        fi
    done

    # note: latuicon (icon picker) is intentionally omitted from this
    # minimal variant; it is only installed by the full installer.

    # cursor package with optional fallback (kept separate so a missing AUR
    # package cannot fail the whole install)
    install_or_fallback notwaita-cursors-grey adwaita-cursors

    echo "packages installed"
}

step_3() {
    header "symlink dotfiles"

    link_file "$DOTFILES_DIR/sway"     "$HOME/.config/sway"
    link_file "$DOTFILES_DIR/swaylock" "$HOME/.config/swaylock"
    link_file "$DOTFILES_DIR/swayidle" "$HOME/.config/swayidle"
    link_file "$DOTFILES_DIR/yambar"   "$HOME/.config/yambar"
    link_file "$DOTFILES_DIR/rofi"     "$HOME/.config/rofi"
    link_file "$DOTFILES_DIR/foot"     "$HOME/.config/foot"
    link_file "$DOTFILES_DIR/mako"     "$HOME/.config/mako"
    if [ "$RSTL_PROGRAM" = "mouse" ]; then
        link_file "$DOTFILES_DIR/rovr" "$HOME/.config/rovr"
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

    # point the shell's editor at the installed one (mouse mode has no nvim)
    if [ "$RSTL_PROGRAM" = "mouse" ]; then
        sed -i 's/^export EDITOR=nvim$/export EDITOR=micro/' \
            "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc" 2>/dev/null || true
        sed -i "s/^alias vim='nvim'\$/alias vim='micro'/" \
            "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc" 2>/dev/null || true
    fi
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
    # Comments out pam_securetty.so so the greeter can authenticate outside a
    # physical secure tty (SSH / serial).
    run_sudo sed -i 's/^auth.*pam_securetty.so/# &/' /etc/pam.d/greetd
    run_sudo systemctl enable greetd.service
    run_sudo systemctl mask getty@tty1.service >/dev/null 2>&1 || true
    echo "greetd configured"
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
    run_sudo systemctl enable --now cronie.service >/dev/null 2>&1 || true

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
    user="${USER:-root}"
    run_sudo loginctl enable-linger "$user"
    sudo -u "$user" systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1 || true
    run_sudo systemctl enable NetworkManager.service >/dev/null 2>&1 || true
    run_sudo systemctl enable bluetooth.service >/dev/null 2>&1 || true
    echo "services enabled"
    cron="# foot --server standby killer
* * * * * ${DOTFILES_DIR}/scripts/foot-idle.sh >/dev/null 2>&1
    "
    install_cron_entry 'foot-idle\.sh' "$cron"
    echo "foot-idle.sh enabled"
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

    run_sudo pacman -Rns --noconfirm $(pacman -Qdtq 2>/dev/null) >/dev/null 2>&1 || true
    run_sudo pacman -Scc --noconfirm >/dev/null 2>&1 || true
    run_sudo rm -rf /var/cache/pacman/pkg/* 2>/dev/null || true

    # ---- optional size purge (drops dev/tooling; keeps a working desktop) ----
    # Safe because it runs after every package is installed and nothing is
    # compiled in this rootfs anymore.
    purge_trim() {
        # C/C++ headers (dev only)
        rm -rf /usr/include 2>/dev/null || true
        # static libraries (rarely needed at runtime)
        find /usr/lib -type f -name "*.a" -delete 2>/dev/null || true
        # pkg-config / linker data (dev only)
        rm -rf /usr/lib/pkgconfig /usr/lib/ldscripts /usr/share/pkgconfig 2>/dev/null || true
        # sanitizer libraries (dev/debug only)
        rm -f /usr/lib/libasan.so* /usr/lib/libtsan.so* 2>/dev/null || true
        # performance profiling tooling
        rm -rf /usr/lib/gprofng* 2>/dev/null || true
        # dev schemas/docs/licenses (functionally safe to drop)
        rm -rf /usr/share/gir-1.0 /usr/share/gtk-doc /usr/share/vala /usr/share/licenses 2>/dev/null || true
        # glibc i18n source; compiled en_US/C locales live in /usr/lib/locale
        #rm -rf /usr/share/i18n 2>/dev/null || true
        # strip debug/unused symbols from binaries and shared libs.
        # Rootfs builds defer the strip to mkfrugal-rstl.sh (host-side after
        # the chroot teardown): stripping the chroot's live interpreter/libs
        # has been observed to segfault the chrooted bash at exit under CI.
        if command -v strip >/dev/null 2>&1 && [ ! -e /etc/.rstl-sway-rootfs ]; then
            find /usr/bin /usr/lib -type f \( -executable -o -name "*.so*" \) \
                -exec strip --strip-unneeded {} + 2>/dev/null || true
        fi
    }
    run_sudo purge_trim

    echo "cleaned up"
}

# ===========================================================================

if [ "$(id -u)" -eq 0 ] && [ ! -e /etc/.rstl-sway-rootfs ]; then
    echo "Error: do not run as root. Run as your normal user (sudo is used when needed)." >&2
    exit 1
fi

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
7|final preferences|Enable lingering, pipewire, network, bluetooth?|step_7
8|cleanup|Remove build artifacts and caches from the dotfiles?|step_8
EOF

echo
echo "Done. Next: reboot (or log out) to start greetd -> sway."
