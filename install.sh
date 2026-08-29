#!/bin/sh
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
[ "${1:-}" = "--yes" ] || [ "${1:-}" = "-y" ] && ASSUME_YES=1
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,7p' "$0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Colors / styling
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_MAGENTA='\033[35m'
  C_CYAN='\033[36m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_MAGENTA='' C_CYAN=''
fi

COLS="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
BOX_W=$(( COLS > 74 ? 74 : COLS ))

# ---------------------------------------------------------------------------
# Locations
# ---------------------------------------------------------------------------
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_DIR="${HOME}/.config/rstl.sway"

# ---------------------------------------------------------------------------
# temp dir for the ASCII art (kept outside the loop so data survives)
# ---------------------------------------------------------------------------
GCDIR="$(mktemp -d)"
trap 'rm -rf "$GCDIR"' EXIT
ASCII_FILE="$GCDIR/ascii"

# ASCII art (sourced from nvim/init.lua's dashboard header)
if [ -f "$SOURCE_DIR/nvim/init.lua" ]; then
  sed -n "/local header_ascii = {/,/^      }$/p" "$SOURCE_DIR/nvim/init.lua" \
    | sed -E "/local header_ascii = \{/d; /^ *}$/d; s/^ *'(.*)',?$/\1/" \
    > "$ASCII_FILE"
fi

rule() {
  printf "${1:-$C_CYAN}%*s${C_RESET}\n" "$BOX_W" "" | tr ' ' '='
}

print_art() {
  color="$1"
  while IFS= read -r line; do
    if [ -n "$line" ]; then
      indent=$(( (COLS - ${#line}) / 2 ))
      [ "$indent" -lt 0 ] && indent=0
      printf "%b%*s%s%b\n" "$color" "$indent" "" "$line" "$C_RESET"
    else
      printf "%b\n" "$color"
    fi
  done < "$ASCII_FILE"
}

center() {
  text="$1" color="$2"
  indent=$(( (COLS - ${#text}) / 2 ))
  [ "$indent" -lt 0 ] && indent=0
  printf "%b%*s%s%b\n" "$color" "$indent" "" "$text" "$C_RESET"
}

banner_start() {
  print_art "$C_CYAN"
  center "rstl.sway · dotfiles installer for Arch Linux" "$C_BOLD$C_CYAN"
  center "minimal sway rice · zero margins · 1px borders · optimized for laptops" "$C_DIM"
  echo
}

banner_end() {
  print_art "$C_GREEN"
  center "rstl.sway successfully installed on your computer!  enjoy!" "$C_BOLD$C_GREEN"
  echo
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf "\n${C_BOLD}${C_CYAN}== %s${C_RESET}\n" "$*"; }
ok()    { printf "  ${C_GREEN}✓ %s${C_RESET}\n" "$*"; }
warn()  { printf "  ${C_YELLOW}! %s${C_RESET}\n" "$*" >&2; }
fail()  { printf "  ${C_RED}✗ %s${C_RESET}\n" "$*" >&2; }

run_sudo() {
  # keeps the cached sudo timestamp fresh and runs "$@"
  sudo -v
  sudo "$@"
}

# add rstl-repo to pacman.conf
add_rstl_repo() {
  conf="/etc/pacman.conf"
  repo_line="[rstl-repo]"
  sig_line="SigLevel = Optional TrustAll"
  server_line="Server = https://arozoid.github.io/rstl.repo"

  if grep -qF "$repo_line" "$conf" 2>/dev/null; then
    ok "rstl-repo already in ${conf}"
    return 0
  fi

  printf "  ${C_DIM}adding rstl-repo to ${conf}${C_RESET}\n"
  printf '\n%s\n%s\n%s\n' "$repo_line" "$sig_line" "$server_line" | run_sudo tee -a "$conf" >/dev/null
  run_sudo pacman -Sy --noconfirm
  ok "rstl-repo added and synced"
}

# combined step header + confirmation prompt
ask_step() {
  idx="$1" label="$2" question="$3"
  ans=""
  rule "$C_MAGENTA"
  printf "  ${C_BOLD}${C_CYAN}STEP %s · ${C_CYAN}%s${C_RESET}\n" "$idx" "$label"
  if [ "$ASSUME_YES" -eq 1 ]; then
    printf "  ${C_BOLD}%s${C_RESET}  ${C_DIM}[auto-yes]${C_RESET}\n" "$question"
    rule "$C_MAGENTA"
    printf "  ${C_GREEN}${C_BOLD}✓ proceeding${C_RESET}\n"
    return 0
  fi
  printf "  ${C_BOLD}%s${C_RESET}  ${C_DIM}[Y/n]${C_RESET}  " "$question"
  read -r ans
  [ -t 0 ] || printf "\n"
  rule "$C_MAGENTA"
  case "$ans" in
    ""|[yY]|[yY][eE][sS])
      printf "  ${C_GREEN}${C_BOLD}✓ proceeding${C_RESET}\n"
      return 0
      ;;
    *)
      printf "  ${C_YELLOW}${C_BOLD}✗ skipped${C_RESET}  ${C_DIM}continuing with the next step${C_RESET}\n"
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Step 0: ensure sudo privileges
# ---------------------------------------------------------------------------
step_0() {
  info "ensuring sudo privileges"
  if sudo -n true 2>/dev/null; then
    ok "sudo already available"
    return 0
  fi
  printf "  ${C_DIM}sudo needs a password — you may be prompted once.${C_RESET}\n"
  if sudo -v; then
    ok "sudo privileges confirmed"
  else
    warn "could not obtain sudo. Steps that need root will fail."
  fi
}

# ---------------------------------------------------------------------------
# Step 1: copy dotfiles into ~/.config/rstl.sway
# ---------------------------------------------------------------------------
step_1() {
  info "initializing nvim repo"
  git submodule update --init
  ok "nvim config updated"
  info "copying dotfiles to ${DOTFILES_DIR}"
  mkdir -p "${DOTFILES_DIR}"
  if [ "$SOURCE_DIR" = "$DOTFILES_DIR" ]; then
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
  info "installing required packages"

  if [ ! -x /usr/bin/pacman ]; then
    warn "pacman not found — skipping (this script targets Arch Linux)."
    return 1
  fi

  # add custom repo first
  add_rstl_repo

  { cat > "$GCDIR/packages" <<'PKGS'
sway
swaybg
rofi
mako
swaylock
swayidle
grim
slurp
wl-clipboard
cliphist
awww
playerctl
brightnessctl
acpi
networkmanager
bluez
bluez-utils
pipewire
wireplumber
pipewire-pulse
pipewire-alsa
alsa-utils
libnotify
sound-theme-freedesktop
greetd
greetd-tuigreet
foot
fish
bat
eza
zoxide
jq
lf
fastfetch
neovim
git
curl
wget
unzip
ripgrep
fd
noto-fonts-emoji
xorg-xwayland
xdg-utils
xdg-desktop-portal-wlr
cronie
flac
mpg123
opus
libvorbis
speex
speexdsp
sbc
dav1d
libvpx
openh264
mesa
vulkan-icd-loader
ttf-jetbrains-mono-nerd-min
papirus-icon-theme-dark-only
googledot-black
rstlpk
dssd
xdg-desktop-portal-termfilechooser
yambar
PKGS
} > /dev/null

  printf "  ${C_DIM}installing: %s${C_RESET}\n" "$(tr '\n' ' ' < "$GCDIR/packages")"
  run_sudo pacman -S --needed --noconfirm $(cat "$GCDIR/packages")

  ok "packages installed"
}

# ---------------------------------------------------------------------------
# Step 3: symlink dotfile directories to their proper paths
# ---------------------------------------------------------------------------
link_dir() {
  src="$1" dest="$2" use_sudo="${3:-no}"

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    ok "already linked ${dest} -> ${src}"
    return 0
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup="${dest}.bak.$(date +%s)"
    if [ "$use_sudo" = "yes" ]; then
      run_sudo mv "$dest" "$backup"
    else
      mv "$dest" "$backup"
    fi
    warn "moved existing ${dest} to ${backup}"
  fi

  if [ "$use_sudo" = "yes" ]; then
    run_sudo ln -s "$src" "$dest"
  else
    ln -s "$src" "$dest"
  fi
  ok "linked ${dest} -> ${src}"
}

step_3() {
  info "symlinking dotfile directories"

  link_dir "$DOTFILES_DIR/sway"      "$HOME/.config/sway"
  link_dir "$DOTFILES_DIR/swaylock"  "$HOME/.config/swaylock"
  link_dir "$DOTFILES_DIR/swayidle"  "$HOME/.config/swayidle"
  link_dir "$DOTFILES_DIR/yambar"    "$HOME/.config/yambar"
  link_dir "$DOTFILES_DIR/rofi"      "$HOME/.config/rofi"
  link_dir "$DOTFILES_DIR/fish"      "$HOME/.config/fish"
  link_dir "$DOTFILES_DIR/foot"      "$HOME/.config/foot"
  link_dir "$DOTFILES_DIR/nvim"      "$HOME/.config/nvim"
  link_dir "$DOTFILES_DIR/mako"      "$HOME/.config/mako"
  link_dir "$DOTFILES_DIR/lf"        "$HOME/.config/lf"
  link_dir "$DOTFILES_DIR/fastfetch" "$HOME/.config/fastfetch"
  link_dir "$DOTFILES_DIR/greetd"    "/etc/greetd" yes

  # xdg-desktop-portal-termfilechooser: prefer it for file pickers
  portal_dir="$HOME/.config/xdg-desktop-portal-termfilechooser"
  mkdir -p "$portal_dir"
  if [ -e "$portal_dir/config" ] && ! diff -q "$DOTFILES_DIR/portal/config" "$portal_dir/config" >/dev/null 2>&1; then
    mv "$portal_dir/config" "$portal_dir/config.bak"
    warn "moved existing ${portal_dir}/config to config.bak"
  fi
  cp -a "$DOTFILES_DIR/portal/config" "$portal_dir/config"
  cp -a "$DOTFILES_DIR/portal/lf-wrapper.sh" "$portal_dir/lf-wrapper.sh"
  chmod +x "$portal_dir/lf-wrapper.sh"
  ok "configured ${portal_dir}/config (lf file chooser)"

  portals_conf="$HOME/.config/xdg-desktop-portal/portals.conf"
  mkdir -p "$(dirname "$portals_conf")"
  if [ ! -f "$portals_conf" ]; then
    printf '%s\n' \
      '[preferred]' \
      'org.freedesktop.impl.portal.FileChooser=termfilechooser' > "$portals_conf"
    ok "preferred termfilechooser in ${portals_conf}"
  else
    ok "portals.conf already present: ${portals_conf}"
  fi
}

# ---------------------------------------------------------------------------
# Step 4: greetd / tuigreet setup
# ---------------------------------------------------------------------------
step_4() {
  info "greetd + tuigreet setup"

  if [ ! -e /etc/greetd/config.toml ]; then
    warn "/etc/greetd/config.toml missing — did step 3 run?"
    return 1
  fi

  if ! id greeter >/dev/null 2>&1; then
    printf "  ${C_DIM}creating 'greeter' system user${C_RESET}\n"
    run_sudo useradd -r -M -G video -d /var/lib/greetd -s /usr/sbin/nologin greeter
    run_sudo mkdir -p /var/lib/greetd
    run_sudo chown greeter:greeter /var/lib/greetd
  else
    ok "greeter user exists"
    run_sudo usermod -aG video greeter
  fi

  run_sudo chmod -R go+r /etc/greetd

  printf "  ${C_DIM}enabling greetd.service${C_RESET}\n"
  run_sudo systemctl enable greetd.service

  printf "  ${C_DIM}masking agetty on tty1 (greetd takes over the login screen)${C_RESET}\n"
  run_sudo systemctl mask getty@tty1.service >/dev/null 2>&1 || true

  ok "greetd configured (tuigreet -> sway)"
}

# ---------------------------------------------------------------------------
# Step 5: wallpaper setup
# ---------------------------------------------------------------------------
setup_wallpaper() {
  wp_dir="$HOME/Pictures/Wallpapers"
  wp_conf="$DOTFILES_DIR/wallpaper"
  wp_file="$wp_dir/wallpaper.jpg"

  mkdir -p "$wp_dir"

  # copy bundled wallpapers from the dotfiles repo, if any
  if [ -d "$DOTFILES_DIR/wallpapers" ] && [ -n "$(ls -A "$DOTFILES_DIR/wallpapers" 2>/dev/null)" ]; then
    cp -a "$DOTFILES_DIR"/wallpapers/. "$wp_dir"/
    ok "copied wallpapers from ${DOTFILES_DIR}/wallpapers to ${wp_dir}"
  fi

  if [ ! -f "$wp_conf" ]; then
    printf '%s\n' "~/Pictures/Wallpapers/wallpaper.jpg" > "$wp_conf"
    ok "wrote wallpaper config ${wp_conf}"
  else
    ok "wallpaper config already present: $(cat "$wp_conf")"
  fi

  if [ ! -f "$wp_file" ]; then
    src_wallpaper="$DOTFILES_DIR/wallpapers/Kiki's Delievery Service.jpg"
    if [ -f "$src_wallpaper" ]; then
      cp "$src_wallpaper" "$wp_file"
      ok "default wallpaper installed (Kiki's Delivery Service)"
    else
      warn "no default wallpaper found — drop an image at ${wp_file} or edit ${wp_conf}."
    fi
  else
    ok "wallpaper already present: ${wp_file}"
  fi
}

step_5() {
  info "wallpaper setup"
  setup_wallpaper
}

# ---------------------------------------------------------------------------
# Step 6: battery alerts (scripts/batt.sh) via cronie / crontab
# ---------------------------------------------------------------------------
install_cron_entry() {
    pattern="$1"; cron="$2"
    existing="$(crontab -l 2>/dev/null || true)"
    merged="$(printf '%s\n' "$existing" | grep -vE "$pattern" || true)"
    printf '%s\n%s' "$merged" "$cron" | crontab -
}

step_6() {
  info "battery alerts setup (40% / 80%)"

  # remove the old systemd timer config, if any
  if systemctl --user is-enabled batt.timer >/dev/null 2>&1; then
    systemctl --user disable --now batt.timer >/dev/null 2>&1 || true
  fi
  rm -f "$HOME/.config/systemd/user/batt.service" "$HOME/.config/systemd/user/batt.timer"
  systemctl --user daemon-reload >/dev/null 2>&1 || true

  if ! command -v crontab >/dev/null 2>&1; then
    warn "crontab not found — install cronie (step 2) and re-run this step."
    return 1
  fi

  # make sure cronie is running
  run_sudo systemctl enable --now cronie.service >/dev/null 2>&1 || \
    warn "could not enable cronie.service — start it manually (systemctl enable --now cronie)"

  uid="$(id -u)"

  cron_content="# rstl.sway battery alerts (40% / 80%)
SHELL=/bin/bash
XDG_RUNTIME_DIR=/run/user/${uid}
DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/${uid}/bus

* * * * * ${DOTFILES_DIR}/scripts/batt.sh >/dev/null 2>&1
"

  install_cron_entry 'batt\.sh' "$cron"

  ok "battery alerts enabled in crontab (every minute, notify at ≤40% and ≥80%)"
}

# ---------------------------------------------------------------------------
# Step 7: fish as default shell
# ---------------------------------------------------------------------------
step_7() {
  info "fish default shell"

  if command -v fish >/dev/null 2>&1; then
    printf "  ${C_DIM}setting fish as the default shell for ${USER}${C_RESET}\n"
    run_sudo chsh -s "$(command -v fish)" "$USER"
    ok "default shell is now fish"
  else
    warn "fish not installed — skipping shell change"
  fi

  # fish config sourced a CachyOS-only file; guard it so vanilla Arch works
  fishconf="$HOME/.config/fish/config.fish"
  if [ -f "$fishconf" ] && ! grep -q 'if test -f /usr/share/cachyos-fish-config' "$fishconf"; then
    sed -i 's|^source /usr/share/cachyos-fish-config/conf.d/done.fish$|if test -f /usr/share/cachyos-fish-config/conf.d/done.fish\n    source /usr/share/cachyos-fish-config/conf.d/done.fish\nend|' "$fishconf"
    ok "guarded cachyos-fish-config source in ${fishconf}"
  fi
}

# ---------------------------------------------------------------------------
# Step 8: final preferences
# ---------------------------------------------------------------------------
step_8() {
  info "final preferences"

  printf "  ${C_DIM}enabling lingering + pipewire user services${C_RESET}\n"
  run_sudo loginctl enable-linger "$USER"
  sudo -u "$USER" systemctl --user enable pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1 || \
    warn "could not enable pipewire user services (enable them after login if needed)"

  printf "  ${C_DIM}enabling system services (network, bluetooth)${C_RESET}\n"
  run_sudo systemctl enable NetworkManager.service >/dev/null 2>&1
  run_sudo systemctl enable bluetooth.service >/dev/null 2>&1

  ok "final preferences applied"

  cron="# foot --server standby killer
* * * * * ${DOTFILES_DIR}/scripts/foot-idle.sh >/dev/null 2>&1
  "
  install_cron_entry 'foot-idle\.sh' "$cron"
  ok "foot-idle.sh enabled"
}

# ---------------------------------------------------------------------------
# Step 9: cleanup
# ---------------------------------------------------------------------------
step_9() {
  info "cleanup"

  removed=0

  # directories that are no longer needed after install
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    full="$DOTFILES_DIR/$d"
    if [ -e "$full" ] || [ -L "$full" ]; then
      rm -rf "$full"
      ok "removed ${d}"
      removed=1
    fi
  done <<EOF
wallpapers
depsize
nvim/.git
ranger/.git
waybar
EOF

  # files that are no longer needed after install
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    full="$DOTFILES_DIR/$f"
    if [ -e "$full" ] || [ -L "$full" ]; then
      rm -f "$full"
      ok "removed ${f}"
      removed=1
    fi
  done <<EOF
packages.txt
README.md
MANUAL_INSTALL.md
install.sh
install-min.sh
.git
.gitmodules
EOF

  # python bytecache
  if find "$DOTFILES_DIR" -type d -name '__pycache__' -print -quit 2>/dev/null | grep -q .; then
    find "$DOTFILES_DIR" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null
    removed=1
  fi

  # remove orphaned make dependencies
  printf "  ${C_DIM}removing orphaned packages...${C_RESET}\n"
  run_sudo pacman -Rns --noconfirm $(pacman -Qdtq 2>/dev/null) 2>/dev/null || true

  # clear pacman cache
  printf "  ${C_DIM}clearing pacman cache...${C_RESET}\n"
  run_sudo pacman -Scc --noconfirm 2>/dev/null || true
  run_sudo rm -rf /var/cache/pacman/pkg/* 2>/dev/null || true

  if [ "$removed" -eq 1 ]; then ok "cleaned up"; else ok "nothing to clean"; fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
if [ "${EUID:-}" -eq 0 ]; then
  printf "${C_RED}${C_BOLD}Error:${C_RESET} ${C_BOLD}do not run as root.${C_RESET}\n" >&2
  printf "${C_DIM}Run as your normal user (sudo is used when needed).${C_RESET}\n" >&2
  exit 1
fi

banner_start

while IFS='|' read -r idx label question func <&3; do
  if ask_step "$idx" "$label" "$question"; then
    "$func"
  fi
  echo
done 3<<'EOF'
0|ensure sudo privileges|Ensure sudo privileges for a smooth installation?|step_0
1|copy dotfiles to ~/.config/rstl.sway|Copy dotfiles into ~/.config/rstl.sway?|step_1
2|install required packages|Install all required packages?|step_2
3|symlink dotfile directories|Symlink dotfile directories to their proper paths?|step_3
4|greetd + tuigreet setup|Set up greetd + tuigreet as the login manager?|step_4
5|wallpaper setup|Set up the wallpaper?|step_5
6|battery alerts (40% / 80%)|Set up the 40% / 80% battery alerts (batt.sh)?|step_6
7|fish default shell|Set fish as the default shell?|step_7
8|final preferences|Enable lingering, pipewire, network, bluetooth?|step_8
9|cleanup|Remove build artifacts and caches from the dotfiles?|step_9
EOF

banner_end

rule "$C_GREEN"
printf "  ${C_BOLD}Next steps${C_RESET}\n"
printf "  ${C_DIM}• Reboot (or log out) to start the greetd → sway session.${C_RESET}\n"
printf "  ${C_DIM}• The default shell change applies to new shells.${C_RESET}\n"
printf "  ${C_DIM}• Edit ~/.config/rstl.sway/wallpaper to point at your own image.${C_RESET}\n"
printf "  ${C_DIM}• Battery alerts fire via cronie (crontab) every minute.${C_RESET}\n"
rule "$C_GREEN"
echo
