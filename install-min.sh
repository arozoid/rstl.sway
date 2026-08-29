#!/bin/sh
# rstl.sway dotfiles installer for Arch Linux (minimal)
#
# Usage:
#   ./install-min.sh            run every step, confirming each one
#   ./install-min.sh --yes      run every step without asking
#   ./install-min.sh --help     show this help

set -u

ASSUME_YES=0
[ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ] && ASSUME_YES=1
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,5p' "$0"
  exit 0
fi

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="${HOME}/.config/rstl.sway"

# Operate from the dotfiles repo regardless of how/where the script was
# invoked (e.g. when run from a chroot as /root/rstl.sway/install-min.sh).
cd "$SOURCE_DIR"

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
    echo "== sudo privileges =="
    sudo -n true 2>/dev/null || sudo -v
}

step_1() {
    echo "== copy dotfiles =="
    git submodule update --init
    mkdir -p "$DOTFILES_DIR"
    if [ "$SOURCE_DIR" != "$DOTFILES_DIR" ]; then
        cp -a "$SOURCE_DIR"/. "$DOTFILES_DIR"/
        chmod +x "$DOTFILES_DIR"/scripts/*.sh 2>/dev/null || true
        echo "copied dotfiles to $DOTFILES_DIR"
    else
        echo "dotfiles already at $DOTFILES_DIR"
    fi
}

step_2() {
    echo "== install packages =="
    command -v pacman >/dev/null 2>&1 || {
        echo "pacman not found, skipping (requires Arch Linux)"
        return 1
    }

    conf="/etc/pacman.conf"
    if ! grep -qF "[rstl-repo]" "$conf" 2>/dev/null; then
        printf '\n[rstl-repo]\nSigLevel = Optional TrustAll\nServer = https://arozoid.github.io/rstl.repo\n' \
            | run_sudo tee -a "$conf" >/dev/null
        run_sudo pacman -Sy --noconfirm
    fi

    run_sudo pacman -S --needed --noconfirm \
        sway swaybg rofi mako swaylock swayidle \
        grim slurp wl-clipboard cliphist \
        playerctl brightnessctl \
        networkmanager bluez bluez-utils \
        pipewire wireplumber pipewire-pulse pipewire-alsa alsa-utils \
        libnotify sound-theme-freedesktop \
        greetd greetd-tuigreet \
        foot lf \
        neovim git curl wget unzip ripgrep fd \
        xorg-xwayland xdg-utils xdg-desktop-portal-wlr \
        cronie \
        flac mpg123 opus libvorbis speex speexdsp sbc \
        dav1d libvpx openh264 \
        mesa vulkan-icd-loader \
        ttf-jetbrains-mono-nerd-min papirus-icon-theme-dark-only googledot-black \
        rstlpk dssd xdg-desktop-portal-termfilechooser yambar

    echo "packages installed"
}

step_3() {
    echo "== symlink dotfiles =="

    link_file "$DOTFILES_DIR/sway"     "$HOME/.config/sway"
    link_file "$DOTFILES_DIR/swaylock" "$HOME/.config/swaylock"
    link_file "$DOTFILES_DIR/swayidle" "$HOME/.config/swayidle"
    link_file "$DOTFILES_DIR/yambar"   "$HOME/.config/yambar"
    link_file "$DOTFILES_DIR/rofi"     "$HOME/.config/rofi"
    link_file "$DOTFILES_DIR/foot"     "$HOME/.config/foot"
    link_file "$DOTFILES_DIR/nvim"     "$HOME/.config/nvim"
    link_file "$DOTFILES_DIR/mako"     "$HOME/.config/mako"
    link_file "$DOTFILES_DIR/lf"       "$HOME/.config/lf"
    link_file "$DOTFILES_DIR/greetd"   "/etc/greetd" yes

    copy_contents "$DOTFILES_DIR/portal" \
        "$HOME/.config/xdg-desktop-portal-termfilechooser"
    chmod +x "$HOME/.config/xdg-desktop-portal-termfilechooser/lf-wrapper.sh"

    write_file_once "$HOME/.config/xdg-desktop-portal/portals.conf" \
        '[preferred]
org.freedesktop.impl.portal.FileChooser=termfilechooser'
    echo "configured file chooser portal"
}

step_4() {
    echo "== greetd + tuigreet =="
    [ -e /etc/greetd/config.toml ] || { echo "/etc/greetd/config.toml missing"; return 1; }

    if ! id greeter >/dev/null 2>&1; then
        run_sudo useradd -r -M -G video -d /var/lib/greetd -s /usr/sbin/nologin greeter
        run_sudo mkdir -p /var/lib/greetd
        run_sudo chown greeter:greeter /var/lib/greetd
    else
        run_sudo usermod -aG video greeter
    fi

    run_sudo chmod -R go+r /etc/greetd
    run_sudo systemctl enable greetd.service
    run_sudo systemctl mask getty@tty1.service >/dev/null 2>&1 || true
    echo "greetd configured"
}

step_5() {
    echo "== wallpaper =="
    wp_dir="$HOME/Pictures/Wallpapers"
    wp_conf="$DOTFILES_DIR/wallpaper"
    wp_file="$wp_dir/wallpaper.jpg"

    write_file_once "$wp_conf" "~/Pictures/Wallpapers/wallpaper.jpg"
    if [ ! -f "$wp_file" ] && [ -f "$DOTFILES_DIR/wallpapers/Kiki's Delievery Service.jpg" ]; then
        cp "$DOTFILES_DIR/wallpapers/Kiki's Delievery Service.jpg" "$wp_file"
    fi
    echo "wallpaper set up"
}

step_6() {
    echo "== battery alerts =="
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
    echo "== final preferences =="
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
    echo "== cleanup =="
    remove_path \
        "$DOTFILES_DIR/wallpapers" \
        "$DOTFILES_DIR/depsize" \
        "$DOTFILES_DIR/nvim/.git" \
        "$DOTFILES_DIR/ranger/.git" \
        "$DOTFILES_DIR/waybar" \
        "$DOTFILES_DIR/packages.txt" \
        "$DOTFILES_DIR/README.md" \
        "$DOTFILES_DIR/MANUAL_INSTALL.md" \
        "$DOTFILES_DIR/install.sh" \
        "$DOTFILES_DIR/install-min.sh" \
        "$DOTFILES_DIR/.git" \
        "$DOTFILES_DIR/.gitmodules" \
        "$DOTFILES_DIR/fastfetch" \
        "$DOTFILES_DIR/fish"

    find "$DOTFILES_DIR" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

    run_sudo pacman -Rns --noconfirm $(pacman -Qdtq 2>/dev/null) >/dev/null 2>&1 || true
    run_sudo pacman -Scc --noconfirm >/dev/null 2>&1 || true
    run_sudo rm -rf /var/cache/pacman/pkg/* 2>/dev/null || true
    echo "cleaned up"
}

# ===========================================================================

if [ "$(id -u)" -eq 0 ] && [ ! -e /etc/.rstl-sway-rootfs ]; then
    echo "Error: do not run as root. Run as your normal user (sudo is used when needed)." >&2
    exit 1
fi

while IFS='|' read -r num label question func <&3; do
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
