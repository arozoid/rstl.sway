#!/usr/bin/env bash
# rstl.sway dotfiles installer for Arch Linux
#
# Usage:
#   ./install.sh            run every step, confirming each one
#   ./install.sh --yes      run every step without asking
#   ./install.sh --help     show this help
#
# Every step can be cancelled with 'n' and the script keeps going.

set -u

ASSUME_YES=0
[[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]] && ASSUME_YES=1
[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && {
  sed -n '2,7p' "$0"
  exit 0
}

# ---------------------------------------------------------------------------
# Locations
# ---------------------------------------------------------------------------
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${HOME}/.config/rstl.sway"

if [[ "${EUID}" -eq 0 ]]; then
  echo "Error: do not run as root. Run as your normal user (sudo will be used when needed)." >&2
  exit 1
fi

SUDO_OK=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo -e "\n==> $*"; }
ok()    { echo "    done: $*"; }
warn()  { echo "    ! $*" >&2; }
fail()  { echo "    failed: $*" >&2; }

confirm_step() {
  local step_name="$1"
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi
  local ans
  printf "Run step %s? [Y/n] " "$step_name"
  read -r ans
  case "${ans,,}" in
    ""|y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

have_sudo() {
  sudo -v >/dev/null 2>&1 && sudo -n true 2>/dev/null
}

run_sudo() {
  # keeps the cached sudo timestamp fresh and runs "$@"
  sudo -v
  sudo "$@"
}

# ---------------------------------------------------------------------------
# Step 0: ensure sudo privileges
# ---------------------------------------------------------------------------
step_0() {
  info "Step 0: ensuring sudo privileges"
  if sudo -n true 2>/dev/null; then
    SUDO_OK=1
    ok "sudo already available"
    return 0
  fi
  echo "    sudo needs a password — you may be prompted once."
  if sudo -v; then
    SUDO_OK=1
    ok "sudo privileges confirmed"
  else
    warn "could not obtain sudo. Steps that need root will fail."
  fi
}

# ---------------------------------------------------------------------------
# Step 1: copy dotfiles into ~/.config/rstl.sway
# ---------------------------------------------------------------------------
step_1() {
  info "Step 1: copying dotfiles to ${DOTFILES_DIR}"
  mkdir -p "${DOTFILES_DIR}"
  if [[ "$SOURCE_DIR" == "$DOTFILES_DIR" ]]; then
    ok "dotfiles are already at ${DOTFILES_DIR}"
    return 0
  fi
  cp -a "$SOURCE_DIR"/. "$DOTFILES_DIR"/
  ok "copied dotfiles from ${SOURCE_DIR}"
  chmod +x "$DOTFILES_DIR"/scripts/*.sh 2>/dev/null || true
  ok "scripts are executable"
}

# ---------------------------------------------------------------------------
# Step 2: install required packages
# ---------------------------------------------------------------------------
step_2() {
  info "Step 2: installing required packages"

  if [[ ! -x /usr/bin/pacman ]]; then
    warn "pacman not found — skipping (this script targets Arch Linux)."
    return 1
  fi

  local packages=(
    # window manager / bar / launcher / notifications
    sway swaybg waybar rofi mako wlogout

    # screenshots / clipboard history
    grim slurp wl-clipboard cliphist

    # wallpaper daemon + image tooling for the generated default wallpaper
    awww imagemagick

    # hardware / media keys
    playerctl brightnessctl light acpi

    # network + bluetooth
    networkmanager bluez bluez-utils

    # audio (pipewire stack + alsa tools used by rofi applets)
    pipewire wireplumber pipewire-pulse pipewire-alsa alsa-utils pulseaudio-utils pavucontrol

    # notifications + polkit
    libnotify polkit

    # login manager
    greetd greetd-tuigreet

    # terminal + shell
    ghostty fish fastfetch bat eza zoxide jq

    # editor
    neovim git curl wget unzip ripgrep fd make gcc

    # fonts (JetBrainsMono Nerd Font used in the rice)
    ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji

    # wayland helpers
    xorg-xwayland xdg-utils xdg-desktop-portal-wlr

    # misc CLI referenced by the dotfiles
    hwinfo expac gnu-netcat grub

    # video / multimedia codec base for a minimal install
    ffmpeg gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav
    mesa vulkan-icd-loader
  )

  echo "    installing: ${packages[*]}"
  run_sudo pacman -S --needed --noconfirm "${packages[@]}"
  ok "packages installed"
}

# ---------------------------------------------------------------------------
# Step 3: symlink dotfile directories to their proper paths
# ---------------------------------------------------------------------------
link_dir() {
  local src="$1" dest="$2" use_sudo="${3:-no}"

  if [[ -L "$dest" ]] && [[ "$(readlink "$dest")" == "$src" ]]; then
    ok "already linked ${dest} -> ${src}"
    return 0
  fi

  if [[ -e "$dest" || -L "$dest" ]]; then
    local backup="${dest}.bak.$(date +%s)"
    if [[ "$use_sudo" == "yes" ]]; then
      run_sudo mv "$dest" "$backup"
    else
      mv "$dest" "$backup"
    fi
    warn "moved existing ${dest} to ${backup}"
  fi

  if [[ "$use_sudo" == "yes" ]]; then
    run_sudo ln -s "$src" "$dest"
  else
    ln -s "$src" "$dest"
  fi
  ok "linked ${dest} -> ${src}"
}

step_3() {
  info "Step 3: symlinking dotfile directories"

  link_dir "$DOTFILES_DIR/sway"     "$HOME/.config/sway"
  link_dir "$DOTFILES_DIR/waybar"   "$HOME/.config/waybar"
  link_dir "$DOTFILES_DIR/rofi"     "$HOME/.config/rofi"
  link_dir "$DOTFILES_DIR/fish"     "$HOME/.config/fish"
  link_dir "$DOTFILES_DIR/ghostty"  "$HOME/.config/ghostty"
  link_dir "$DOTFILES_DIR/nvim"     "$HOME/.config/nvim"
  link_dir "$DOTFILES_DIR/greetd"   "/etc/greetd" yes
}

# ---------------------------------------------------------------------------
# Step 4: greetd / tuirgeet setup
# ---------------------------------------------------------------------------
step_4() {
  info "Step 4: greetd + tuirgeet setup"

  if ! [[ -e /etc/greetd/config.toml ]]; then
    warn "/etc/greetd/config.toml missing — did step 3 run?"
    return 1
  fi

  if ! id greeter >/dev/null 2>&1; then
    echo "    creating 'greeter' system user"
    run_sudo useradd -r -M -G video -d /var/lib/greetd -s /usr/sbin/nologin greeter
    run_sudo mkdir -p /var/lib/greetd
    run_sudo chown greeter:greeter /var/lib/greetd
  else
    ok "greeter user exists"
    run_sudo usermod -aG video greeter
  fi

  run_sudo chmod -R go+r /etc/greetd

  echo "    enabling greetd.service"
  run_sudo systemctl enable greetd.service

  echo "    masking agetty on tty1 (greetd takes over the login screen)"
  run_sudo systemctl mask getty@tty1.service >/dev/null 2>&1 || true

  ok "greetd configured (tuigreet -> sway)"
}

# ---------------------------------------------------------------------------
# Step 5: fish as default shell + final preferences
# ---------------------------------------------------------------------------
step_5() {
  info "Step 5: fish as default shell + final preferences"

  if command -v fish >/dev/null 2>&1; then
    echo "    setting fish as the default shell for ${USER}"
    run_sudo chsh -s "$(command -v fish)" "$USER"
    ok "default shell is now fish"
  else
    warn "fish not installed — skipping shell change"
  fi

  # fish config sourced a CachyOS-only file; guard it so vanilla Arch works
  local fishconf="$HOME/.config/fish/config.fish"
  if [[ -f "$fishconf" ]] && ! grep -q 'if test -f /usr/share/cachyos-fish-config' "$fishconf"; then
    sed -i 's|^source /usr/share/cachyos-fish-config/conf.d/done.fish$|if test -f /usr/share/cachyos-fish-config/conf.d/done.fish\n    source /usr/share/cachyos-fish-config/conf.d/done.fish\nend|' "$fishconf"
    ok "guarded cachyos-fish-config source in ${fishconf}"
  fi

  # keep the user's own 'done' notifications working (already shipped in conf.d)

  echo "    enabling lingering + pipewire user services"
  run_sudo loginctl enable-linger "$USER"
  sudo -u "$USER" systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1 || \
    warn "could not enable pipewire user services (enable them after login if needed)"

  echo "    enabling system services (network, bluetooth)"
  run_sudo systemctl enable NetworkManager.service >/dev/null 2>&1
  run_sudo systemctl enable bluetooth.service >/dev/null 2>&1

  ok "final preferences applied"
}

# ---------------------------------------------------------------------------
# Step 6: wallpaper setup
# ---------------------------------------------------------------------------
setup_wallpaper() {
  local wp_dir="$HOME/Pictures/Wallpapers"
  local wp_conf="$DOTFILES_DIR/wallpaper"
  local wp_file="$wp_dir/wallpaper.jpg"

  mkdir -p "$wp_dir"

  if [[ ! -f "$wp_conf" ]]; then
    printf '%s\n' "~/Pictures/Wallpapers/wallpaper.jpg" > "$wp_conf"
    ok "wrote wallpaper config ${wp_conf}"
  else
    ok "wallpaper config already present: $(cat "$wp_conf")"
  fi

  if [[ ! -f "$wp_file" ]]; then
    local magick_bin=""
    if command -v magick >/dev/null 2>&1; then
      magick_bin=magick
    elif command -v convert >/dev/null 2>&1; then
      magick_bin=convert
    fi
    if [[ -n "$magick_bin" ]]; then
      echo "    generating a default wallpaper at ${wp_file}"
      "$magick_bin" -size 2560x1600 gradient:'#12161c'-'#263238' "$wp_file"
      ok "default wallpaper generated"
    else
      warn "imagemagick not available — no default wallpaper generated."
      warn "drop an image at ${wp_file} or edit ${wp_conf}."
    fi
  else
    ok "wallpaper already present: ${wp_file}"
  fi
}

step_6() {
  info "Step 6: wallpaper setup"
  setup_wallpaper
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
steps=(
  "0:ensure sudo privileges|step_0"
  "1:copy dotfiles to ~/.config/rstl.sway|step_1"
  "2:install required packages|step_2"
  "3:symlink dotfile directories|step_3"
  "4:greetd + tuirgeet setup|step_4"
  "5:fish default shell + final preferences|step_5"
  "6:wallpaper setup|step_6"
)

for entry in "${steps[@]}"; do
  name="${entry%%|*}"
  func="${entry##*|}"
  if confirm_step "$name"; then
    "$func"
  else
    echo "    skipped step ${name}"
  fi
  echo
done

echo "============================================================="
echo "Install finished."
echo "  - Reboot (or log out) to start the greetd -> sway session."
echo "  - Default shell changes apply to new shells."
echo
echo "Notes:"
echo "  - The wallpaper is set by scripts/wallpaper-restore.sh (started from"
echo "    sway). Its path is read from ~/.config/rstl.sway/wallpaper and a"
echo "    default one is generated at ~/Pictures/Wallpapers/wallpaper.jpg."
echo "  - 'nightlight.sh', wallpaper-restore.sh helpers, 'fsh' and the Bibata"
echo "    cursor theme are personal extras and are NOT installed by this script."
echo "  - 'light' (rofi brightness applet) needs a udev rule or setuid to"
echo "    run without root; sway keys already use brightnessctl."
echo "============================================================="
