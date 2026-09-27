#!/bin/sh
# rstl.sway dotfiles installer for Arch Linux
#
# Usage:
#   bin/install.sh                  run every step, confirming each one
#   bin/install.sh --yes            run every step without asking
#   bin/install.sh --no-cleanup     every step except the last one (cleanup)
#   bin/install.sh --program mouse  pick the program configuration
#   bin/install.sh --firefox        bundle the firefox browser
#   bin/install.sh --help           show this help
#
# Every step can be cancelled with 'n' and the script keeps going. The package
# list lives next to this script, in ../packages-install.txt, and the edition
# this run installed is recorded in ../.rstl-edition. bin/update.sh re-runs this
# installer to bring an existing installation up to date.

set -u

# Program configuration. The ISO build picks it through the environment
# (mkfrugal-rstl.sh --program), a person installing it with --program:
#   vim   = nvim editor + superfile (spf) file manager
#   mouse = micro editor (settings vendored in ./micro) + rovr file manager
# RSTL_FIREFOX=1 / --firefox bundles the firefox browser on top of either.
RSTL_PROGRAM="${RSTL_PROGRAM:-vim}"
RSTL_FIREFOX="${RSTL_FIREFOX:-0}"

ASSUME_YES=0
SKIP_CLEANUP=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --yes|-y)         ASSUME_YES=1; shift ;;
    --no-cleanup)     SKIP_CLEANUP=1; shift ;;
    --program)        [ "$#" -ge 2 ] || { echo "--program needs a value" >&2; exit 2; }
                      RSTL_PROGRAM="$2"; shift 2 ;;
    --program=*)      RSTL_PROGRAM="${1#*=}"; shift ;;
    --firefox)        RSTL_FIREFOX=1; shift ;;
    --no-firefox)     RSTL_FIREFOX=0; shift ;;
    --help|-h)        sed -n '2,15p' "$0"; exit 0 ;;
    *)                echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
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
EDITION="install"
EDITION_PROGRAM="$RSTL_PROGRAM"
PKG_LIST="packages-install.txt"
# the step that strips build artifacts; skipped with --no-cleanup
CLEANUP_STEP="step_9"

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
  C_PURPLE='\033[95m'
  C_CYAN='\033[36m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_MAGENTA='' C_PURPLE='' C_CYAN=''
fi

COLS="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
BOX_W=$(( COLS > 74 ? 74 : COLS ))

# ---------------------------------------------------------------------------
# Locations
# ---------------------------------------------------------------------------
# The scripts live in bin/ and the package lists sit next to that, in the
# repository root, so REPO_DIR is the checkout this script was started from.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOTFILES_DIR="${HOME}/.config/rstl.sway"

# ---------------------------------------------------------------------------
# temp dir for the ASCII art (kept outside the loop so data survives)
# ---------------------------------------------------------------------------
GCDIR="$(mktemp -d)"
trap 'rm -rf "$GCDIR"' EXIT
ASCII_FILE="$GCDIR/ascii"

# ASCII art (sourced from nvim/init.lua's dashboard header)
if [ -f "$REPO_DIR/nvim/init.lua" ]; then
  sed -n "/local header_ascii = {/,/^      }$/p" "$REPO_DIR/nvim/init.lua" \
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
info()  { printf "\n${C_BOLD}${C_PURPLE}== %s${C_RESET}\n" "$*"; }
ok()    { printf "  ${C_GREEN}✓ %s${C_RESET}\n" "$*"; }
warn()  { printf "  ${C_YELLOW}! %s${C_RESET}\n" "$*" >&2; }
fail()  { printf "  ${C_RED}✗ %s${C_RESET}\n" "$*" >&2; }

run_sudo() {
  # keeps the cached sudo timestamp fresh and runs "$@"
  sudo -v
  sudo "$@"
}

# retry a pacman transaction a few times against transient download failures
# (GitHub Pages mirrors occasionally drop a mid-flight response)
pac_retry() {
  attempt=0
  until run_sudo pacman "$@"; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 3 ]; then
      fail "pacman $* failed after ${attempt} attempts"
      return 1
    fi
    warn "pacman $* failed, retrying (${attempt}/3)"
    sleep 2
  done
}

# install $1 if it exists in the (synced) repos, otherwise install the $2 fallback
install_or_fallback() {
  pkg="$1"; fallback="$2"
  if run_sudo pacman -Ssq "^${pkg}$" 2>/dev/null | grep -qx "$pkg"; then
    pac_retry -S --needed --noconfirm "$pkg"
  else
    printf "  ${C_DIM}%s not found, using %s${C_RESET}\n" "$pkg" "$fallback"
    pac_retry -S --needed --noconfirm "$fallback"
  fi
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
  pac_retry -Sy --noconfirm
  ok "rstl-repo added and synced"
}

# ---------------------------------------------------------------------------
# Package list (../packages-install.txt)
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

# ---------------------------------------------------------------------------
# Copying the repository into ~/.config/rstl.sway
# ---------------------------------------------------------------------------
# Two rules, and they are the reason this is not just `cp -a`:
#
#   1. .git is never copied. A checkout's history belongs to the machine that
#      made it: bin/update.sh installs from a fresh `git clone --depth 1`, and
#      copying its .git over a real checkout would replace the user's history
#      (and, with */.git, their submodule registrations) with a shallow copy of
#      someone else's. Submodule .git markers are skipped for the same reason.
#      The ISO/rootfs builds already purge .git the same way, see copy_repo in
#      mkfrugal-rstl.sh.
#
#   2. The paths the installers own are purged BEFORE the copy, so the result is
#      exactly the repository instead of the repository plus whatever an earlier
#      version left behind. That matters most for sway/config.d (the user's
#      settings: a file deleted from the repository must not keep applying) and
#      for sway/config plus the edition files, which the base installer patches
#      in place - without the purge, going back to the full edition would leave
#      the "# [base] " comments behind forever.
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

# ---------------------------------------------------------------------------
# Edition indicator (~/.config/rstl.sway/.rstl-edition)
# ---------------------------------------------------------------------------
# Which flavor installed this dotfiles directory, with which program, so
# bin/update.sh knows what to re-apply. Rewritten from scratch on every run
# (never merged with whatever was there) and git-ignored: it describes the
# machine, not the repository.
write_edition() {
  target="$DOTFILES_DIR/.rstl-edition"
  if ! {
    printf '# written by bin/install.sh, read by bin/update.sh - do not edit\n'
    printf 'edition=%s\n'   "$EDITION"
    printf 'program=%s\n'   "$EDITION_PROGRAM"
    printf 'firefox=%s\n'   "$RSTL_FIREFOX"
    printf 'dotfiles=%s\n'  "$DOTFILES_DIR"
    printf 'packages=%s\n'  "$PKG_LIST"
    printf 'installed=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)"
  } > "$target" 2>/dev/null; then
    warn "could not write the edition indicator ${target}"
    return 1
  fi
  ok "edition recorded in ${target} (${EDITION}, program ${EDITION_PROGRAM})"
}

# combined step header + confirmation prompt
ask_step() {
  idx="$1" label="$2" question="$3"
  ans=""
  rule "$C_PURPLE"
  printf "  ${C_BOLD}${C_PURPLE}STEP %s · ${C_PURPLE}%s${C_RESET}\n" "$idx" "$label"
  if [ "$ASSUME_YES" -eq 1 ]; then
    printf "  ${C_BOLD}%s${C_RESET}  ${C_DIM}[auto-yes]${C_RESET}\n" "$question"
    rule "$C_PURPLE"
    printf "  ${C_GREEN}${C_BOLD}✓ proceeding${C_RESET}\n"
    return 0
  fi
  printf "  ${C_BOLD}%s${C_RESET}  ${C_DIM}[Y/n]${C_RESET}  " "$question"
  read -r ans
  [ -t 0 ] || printf "\n"
  rule "$C_PURPLE"
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
  info "initializing config submodules"
  # The nvim config is a submodule. An installed system has no .git at all (the
  # ISO strips it to stay small) and already carries the files, so only a
  # checkout is updated. rstl-inst/rstl-pick are build artifacts and are left
  # alone.
  if [ -d "$REPO_DIR/.git" ] || [ -f "$REPO_DIR/.git" ]; then
    git -C "$REPO_DIR" submodule update --init --depth 1 nvim ||
        warn "submodule update failed"
  else
    info "no git checkout, skipping the submodule update"
  fi
  ok "config submodules updated"
  info "copying dotfiles to ${DOTFILES_DIR}"
  if [ "$REPO_DIR" = "$DOTFILES_DIR" ]; then
    ok "dotfiles are already at ${DOTFILES_DIR}"
  else
    copy_dotfiles || return 1
    ok "copied dotfiles from ${REPO_DIR}"
  fi
  mkdir -p "${DOTFILES_DIR}"
  chmod +x "$DOTFILES_DIR"/scripts/*.sh "$DOTFILES_DIR"/bin/*.sh 2>/dev/null || true
  ok "scripts are executable"

  # record which flavor (and program) owns this dotfiles dir; bin/update.sh
  # reads it back to know what to re-apply
  write_edition

  # first-login hook: greetd/tuigreet starts sway through rstl-first-login,
  # so install it system-wide (one-shot setup + session launch, see script).
  if [ -f "$DOTFILES_DIR/scripts/first-login.sh" ]; then
    run_sudo install -Dm755 "$DOTFILES_DIR/scripts/first-login.sh" /usr/local/bin/rstl-first-login
    run_sudo tee /etc/profile.d/rstl-first-login.sh >/dev/null <<'EOF'
# rstl.sway first-login hook: runs once per user on their first (shell) login.
# The script itself guards on the per-user marker, so it is safe on every login.
[ -n "$HOME" ] || return 0
[ -x /usr/local/bin/rstl-first-login ] && /usr/local/bin/rstl-first-login
EOF
    run_sudo chmod 644 /etc/profile.d/rstl-first-login.sh
    ok "installed rstl-first-login + profile.d hook"
  fi

  # the `rstl` wrapper: run any script in bin/ by name (rstl install.sh --yes,
  # rstl update.sh). Installed system-wide so it works from any directory.
  if [ -f "$DOTFILES_DIR/bin/rstl" ]; then
    run_sudo install -Dm755 "$DOTFILES_DIR/bin/rstl" /usr/local/bin/rstl
    ok "installed the rstl wrapper (/usr/local/bin/rstl)"
  fi
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

  # the package list is data: ../packages-install.txt, next to the repository
  # root. #@core goes in one atomic transaction, everything else one package at
  # a time. See list_core()/list_each() for the section format.
  if [ ! -f "$REPO_DIR/$PKG_LIST" ]; then
    fail "package list ${REPO_DIR}/${PKG_LIST} is missing"
    return 1
  fi
  list_core > "$GCDIR/packages"
  list_each > "$GCDIR/packages-extra"
  printf "  ${C_DIM}%s: %s core, %s per-package (program: %s)%s\n" \
    "$PKG_LIST" \
    "$(wc -l < "$GCDIR/packages" | tr -d ' ')" \
    "$(wc -l < "$GCDIR/packages-extra" | tr -d ' ')" \
    "$RSTL_PROGRAM" \
    "$C_RESET"

  # pacman resolves every target BEFORE installing anything, so one package that
  # does not exist under that exact name aborts the whole transaction and you
  # silently end up with none of them (this shipped an ISO without nvim, eza or
  # zsh-autosuggestions because Arch calls it fd-find and CachyOS calls it fd).
  # Filter the list against the repos first: install everything that resolves in
  # a single transaction, and report the names that do not. Distro-renamed
  # packages are added separately via install_or_fallback below.
  repo_pkgs="$(mktemp)"
  run_sudo pacman -Ssq > "$repo_pkgs" 2>/dev/null || : > "$repo_pkgs"
  wanted=""
  missing=""
  for pkg in $(cat "$GCDIR/packages"); do
    if grep -qxF "$pkg" "$repo_pkgs"; then
      wanted="$wanted $pkg"
    else
      missing="$missing $pkg"
    fi
  done
  rm -f "$repo_pkgs"
  wanted="${wanted# }"     # drop the leading space; keeps the lists symmetric
  missing="${missing# }"   # drop the leading space so membership tests are exact

  # a session without these cannot boot into the desktop at all: refuse to
  # continue (and let the rootfs/ISO build fail) instead of shipping a broken
  # image. A stale sync db can cause this too - the message says so.
  for pkg in sway greetd greetd-tuigreet foot mako rofi; do
    case " $missing " in
      *" $pkg "*)
        fail "required package '$pkg' is in no enabled repo (stale sync db? try: sudo pacman -Sy)"
        exit 1
        ;;
    esac
  done

  if [ -n "$missing" ]; then
    warn "not in any enabled repo, skipped:$missing"
  fi

  if [ -n "$wanted" ]; then
    printf "  ${C_DIM}installing: %s${C_RESET}\n" "$wanted"
    pac_retry -S --needed --noconfirm $wanted
  fi

  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    if run_sudo pacman -Ssq "^${pkg}$" 2>/dev/null | grep -qx "$pkg"; then
      pac_retry -S --needed --noconfirm "$pkg"
    else
      printf "  ${C_DIM}extra package %s not found in any repo, skipping${C_RESET}\n" "$pkg"
    fi
  done < "$GCDIR/packages-extra"

  # theme/cursor packages with official-repo fallbacks (kept separate so a
  # missing AUR package cannot fail the whole install). The base icon theme
  # is hicolor; papirus-dark supplies the themed set; adwaita-icon-theme
  # arrives with firefox when the browser bundle is enabled.
  pac_retry -S --needed --noconfirm hicolor-icon-theme
  install_or_fallback notwaita-cursors-grey adwaita-cursors
  install_or_fallback papirus-icon-theme-dark-only adwaita-icon-theme
  # fd: Arch ships the binary as package fd-find, CachyOS as fd (both provide
  # /usr/bin/fd). Kept out of the bulk list above for exactly that reason.
  install_or_fallback fd-find fd

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
# link_dir "$DOTFILES_DIR/fish"      "$HOME/.config/fish"
  link_dir "$DOTFILES_DIR/foot"      "$HOME/.config/foot"
  case "$RSTL_PROGRAM" in
    mouse)
      link_dir "$DOTFILES_DIR/rovr"   "$HOME/.config/rovr"
      link_dir "$DOTFILES_DIR/micro"  "$HOME/.config/micro"
      printf "  ${C_DIM}program config 'mouse': rovr file manager, micro editor${C_RESET}\n"
      ;;
    *)
      link_dir "$DOTFILES_DIR/nvim"  "$HOME/.config/nvim"
      printf "  ${C_DIM}program config 'vim': nvim editor, superfile file manager${C_RESET}\n"
      ;;
  esac
  link_dir "$DOTFILES_DIR/mako"      "$HOME/.config/mako"
  link_dir "$DOTFILES_DIR/lf"        "$HOME/.config/lf"
  link_dir "$DOTFILES_DIR/chawan"    "$HOME/.config/chawan"
  link_dir "$DOTFILES_DIR/fastfetch" "$HOME/.config/fastfetch"
  link_dir "$DOTFILES_DIR/.zshrc"    "$HOME/.zshrc"
  link_dir "$DOTFILES_DIR/greetd"    "/etc/greetd" yes

  # xdg-desktop-portal-termfilechooser: prefer it for file pickers
  portal_dir="$HOME/.config/xdg-desktop-portal-termfilechooser"
  mkdir -p "$portal_dir"
  if [ -e "$portal_dir/config" ] && ! diff -q "$DOTFILES_DIR/portal/config" "$portal_dir/config" >/dev/null 2>&1; then
    mv "$portal_dir/config" "$portal_dir/config.bak"
    warn "moved existing ${portal_dir}/config to config.bak"
  fi
  cp -a "$DOTFILES_DIR/portal/config" "$portal_dir/config"
  cp -a "$DOTFILES_DIR/portal/fm-wrapper.sh" "$portal_dir/fm-wrapper.sh"
  chmod +x "$portal_dir/fm-wrapper.sh"
  ok "configured ${portal_dir}/config (file chooser: superfile -> rovr -> lf)"

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

  # point the shell's editor at the installed one (mouse mode has no nvim)
  if [ "$RSTL_PROGRAM" = "mouse" ]; then
    sed -i 's/^export EDITOR=nvim$/export EDITOR=micro/' \
      "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc" 2>/dev/null || true
    sed -i "s/^alias vim='nvim'\$/alias vim='micro'/" \
      "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc" 2>/dev/null || true
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

  # Comments out pam_securetty.so in greetd's PAM config so the greeter can
  # authenticate outside of a physical secure tty (e.g. over SSH / serial).
  run_sudo sed -i 's/^auth.*pam_securetty.so/# &/' /etc/pam.d/greetd

  printf "  ${C_DIM}enabling greetd.service${C_RESET}\n"
  run_sudo systemctl enable greetd.service

  printf "  ${C_DIM}masking agetty on tty1 (greetd takes over the login screen)${C_RESET}\n"
  run_sudo systemctl mask getty@tty1.service >/dev/null 2>&1 || true

  ok "greetd configured (tuigreet -> rstl-first-login -> sway)"
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
  # if [ -d "$DOTFILES_DIR/wallpapers" ] && [ -n "$(ls -A "$DOTFILES_DIR/wallpapers" 2>/dev/null)" ]; then
  #   cp -a "$DOTFILES_DIR"/wallpapers/. "$wp_dir"/
  #   ok "copied wallpapers from ${DOTFILES_DIR}/wallpapers to ${wp_dir}"
  # fi

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

  install_cron_entry 'batt\.sh' "$cron_content"

  ok "battery alerts enabled in crontab (every minute, notify at ≤40% and ≥80%)"
}

# ---------------------------------------------------------------------------
# Step 7: zsh as default shell
# ---------------------------------------------------------------------------
step_7() {
  info "zsh default shell"

  if command -v zsh >/dev/null 2>&1; then
    printf "  ${C_DIM}setting zsh as the default shell for ${USER}${C_RESET}\n"
    run_sudo chsh -s "$(command -v zsh)" "$USER"
    ok "default shell is now zsh"
  else
    warn "zsh not installed — skipping shell change"
  fi

  # fish config sourced a CachyOS-only file; guard it so vanilla Arch works
  #fishconf="$HOME/.config/fish/config.fish"
  #if [ -f "$fishconf" ] && ! grep -q 'if test -f /usr/share/cachyos-fish-config' "$fishconf"; then
  #  sed -i 's|^source /usr/share/cachyos-fish-config/conf.d/done.fish$|if test -f /usr/share/cachyos-fish-config/conf.d/done.fish\n    source /usr/share/cachyos-fish-config/conf.d/done.fish\nend|' "$fishconf"
  #  ok "guarded cachyos-fish-config source in ${fishconf}"
  #fi
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
.git
.gitmodules
EOF
  # deliberately NOT removed: bin/ (bin/update.sh re-runs this installer to
  # update the machine), packages-install*.txt (the lists the installers read)
  # and .rstl-edition (which flavor this machine runs).

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
  if [ "$func" = "$CLEANUP_STEP" ] && [ "$SKIP_CLEANUP" -eq 1 ]; then
    # bin/update.sh re-runs the installer to refresh the dotfiles; the cleanup
    # step is a build-time size optimization (orphan removal, cache purge) and
    # must not run against a live desktop.
    printf "  ${C_DIM}step %s (%s) skipped: --no-cleanup${C_RESET}\n" "$idx" "$label"
    echo
    continue
  fi
  if ask_step "$idx" "$label" "$question"; then
    if ! "$func"; then
      warn "step $idx failed (exit $?) — continuing with the next step"
    fi
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
7|zsh default shell|Set zsh as the default shell?|step_7
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
