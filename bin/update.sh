#!/bin/sh
# rstl.sway updater - brings an existing installation up to date.
#
# Usage:
#   bin/update.sh                          update this machine
#   bin/update.sh --yes                    do not ask for confirmation
#   bin/update.sh --edition install-min    update a specific edition
#   bin/update.sh --help                   show this help
#
# Options:
#   --edition, --flavor <install|install-min|install-base>
#                     update this edition instead of the detected one
#   --program <vim|mouse>                 program configuration to keep
#   --firefox / --no-firefox              keep or drop the firefox bundle
#   --no-upgrade                          skip the `pacman -Syu` system upgrade
#   --yes, -y                             do not ask for confirmation
#   --dir PATH                            dotfiles directory (default ~/.config/rstl.sway)
#   --repo URL                            repository to fetch (default github.com/arozoid/rstl.sway)
#   --help, -h                            show this help
#
# What it does:
#   1. works out the edition, the program configuration and the firefox bundle
#      from ~/.config/rstl.sway/.rstl-edition (the installers rewrite it on every
#      run) and falls back to detecting them from the installed packages when
#      that file is missing
#   2. fetches the newest dotfiles: `git pull` when the directory still is a
#      checkout, otherwise a fresh shallow clone - an ISO-installed system has no
#      .git (the build strips it and the installers never copy one in), so
#      there is nothing to pull from
#   3. upgrades the system: sudo pacman -Syu
#   4. re-runs bin/install-<edition>.sh --yes --no-cleanup with the program
#      configuration and browser bundle this machine had, which re-applies the
#      dotfiles and makes sure every package in packages-<edition>.txt is
#      installed and current (pacman --needed after the -Syu upgrade)
#
# The cleanup step of the installer is skipped on purpose: it is a build-time
# size optimization (orphan removal, cache purge, dev headers) and must not run
# against a live desktop.

set -u

REPO_URL="${RSTL_REPO_URL:-https://github.com/arozoid/rstl.sway}"
DOTFILES_DIR="${RSTL_SWAY_DIR:-${HOME}/.config/rstl.sway}"
ASSUME_YES=0
DO_UPGRADE=1
EDITION=""
PROGRAM=""
FIREFOX=""
SOURCE_DIR=""
CLONE_DIR=""

# ---------------------------------------------------------------------------
# output
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    C_RESET='\033[0m' C_BOLD='\033[1m'
    C_PURPLE='\033[95m' C_GREEN='\033[32m' C_YELLOW='\033[33m' C_RED='\033[31m'
    C_DIM='\033[2m'
else
    C_RESET='' C_BOLD='' C_PURPLE='' C_GREEN='' C_YELLOW='' C_RED='' C_DIM=''
fi

header() { printf "\n${C_BOLD}${C_PURPLE}== %s${C_RESET}\n" "$*"; }
info()   { printf "  ${C_DIM}-> %s${C_RESET}\n" "$*"; }
ok()     { printf "  ${C_GREEN}ok${C_RESET}  %s\n" "$*"; }
warn()   { printf "  ${C_YELLOW}warning${C_RESET}  %s\n" "$*" >&2; }
fail()   { printf "  ${C_RED}error${C_RESET}  %s\n" "$*" >&2; }
die()    { fail "$*"; exit 1; }

confirm() {
    if [ "$ASSUME_YES" -eq 1 ]; then
        printf "  [auto-yes] %s\n" "$1"
        return 0
    fi
    printf "  %s [Y/n] " "$1"
    read ans
    case "$ans" in
        ""|[yY]|[yY][eE][sS]) return 0 ;;
        *) printf "  aborted\n"; exit 0 ;;
    esac
}

cleanup() { [ -n "$CLONE_DIR" ] && [ -d "$CLONE_DIR" ] && rm -rf "$CLONE_DIR"; }
trap cleanup EXIT

usage() { sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; }

# ---------------------------------------------------------------------------
# arguments
# ---------------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
    case "$1" in
        --edition|--flavor) [ "$#" -ge 2 ] || die "--edition needs a value"
                            EDITION="$2"; shift 2 ;;
        --edition=*|--flavor=*) EDITION="${1#*=}"; shift ;;
        --program)           [ "$#" -ge 2 ] || die "--program needs a value"
                            PROGRAM="$2"; shift 2 ;;
        --program=*)         PROGRAM="${1#*=}"; shift ;;
        --firefox)           FIREFOX=1; shift ;;
        --no-firefox)        FIREFOX=0; shift ;;
        --dir)               [ "$#" -ge 2 ] || die "--dir needs a value"
                            DOTFILES_DIR="$2"; shift 2 ;;
        --dir=*)             DOTFILES_DIR="${1#*=}"; shift ;;
        --repo)              [ "$#" -ge 2 ] || die "--repo needs a value"
                            REPO_URL="$2"; shift 2 ;;
        --repo=*)            REPO_URL="${1#*=}"; shift ;;
        --no-upgrade)        DO_UPGRADE=0; shift ;;
        --yes|-y)            ASSUME_YES=1; shift ;;
        --help|-h)           usage; exit 0 ;;
        *)                   usage >&2; die "unknown option: $1" ;;
    esac
done

case "$EDITION" in
    ""|install|install-min|install-base) ;;
    *) die "unknown edition '$EDITION' (install, install-min, install-base)" ;;
esac
case "$PROGRAM" in
    ""|vim|mouse) ;;
    *) die "unknown program '$PROGRAM' (vim, mouse)" ;;
esac
case "$FIREFOX" in
    ""|0|1) ;;
    *) die "--firefox/--no-firefox take no value, got: $FIREFOX" ;;
esac

[ "$(id -u)" -eq 0 ] && die "do not run as root. Run as your normal user (sudo is used when needed)."
[ -d "$DOTFILES_DIR" ] || die "${DOTFILES_DIR} does not exist - nothing to update. Run an installer first (see MANUAL_INSTALL.md)."

INDICATOR="${DOTFILES_DIR}/.rstl-edition"

# ---------------------------------------------------------------------------
# what is installed?
# ---------------------------------------------------------------------------
pkg_installed() {
    command -v pacman >/dev/null 2>&1 || return 1
    pacman -Q "$1" >/dev/null 2>&1
}

# value of one key in the edition indicator (empty when absent)
indicator_get() {
    [ -f "$INDICATOR" ] || return 0
    sed -n "s/^$1=//p" "$INDICATOR" | tail -n 1
}

# fall back to guessing, for dotfiles installed before the indicator existed
detect_edition() {
    if [ -e "${HOME}/.config/nvim" ] || [ -e "${HOME}/.config/micro" ] ||
       pkg_installed neovim || pkg_installed micro; then
        echo install
    elif pkg_installed swaylock || pkg_installed swayidle; then
        echo install-min
    else
        echo install-base
    fi
}

detect_program() {
    if [ -e "${HOME}/.config/micro" ] || pkg_installed micro || pkg_installed rovr-bin; then
        echo mouse
    else
        echo vim
    fi
}

# ---------------------------------------------------------------------------
# plan
# ---------------------------------------------------------------------------
header "checking this installation"

if [ -f "$INDICATOR" ]; then
    info "edition indicator: ${INDICATOR}"
    info "recorded $(indicator_get installed) by $(indicator_get packages)"
else
    info "no edition indicator at ${INDICATOR}, detecting instead"
fi

if [ -z "$EDITION" ]; then
    EDITION="$(indicator_get edition)"
    [ -n "$EDITION" ] || EDITION="$(detect_edition)"
    info "edition: ${EDITION} (detected)"
else
    info "edition: ${EDITION} (given)"
fi

if [ "$EDITION" = "install-base" ]; then
    PROGRAM="none"     # the base edition carries no program configuration
else
    if [ -z "$PROGRAM" ]; then
        PROGRAM="$(indicator_get program)"
        case "$PROGRAM" in
            vim|mouse) ;;
            *) PROGRAM="$(detect_program)" ;;
        esac
    fi
    info "program: ${PROGRAM}"
fi

if [ -z "$FIREFOX" ]; then
    FIREFOX="$(indicator_get firefox)"
    case "$FIREFOX" in
        0|1) ;;    # the indicator says which bundle this machine was installed with
        *) if pkg_installed firefox; then FIREFOX=1; else FIREFOX=0; fi ;;
    esac
fi
info "firefox bundle: ${FIREFOX}"

# ---------------------------------------------------------------------------
# fetch the newest dotfiles
# ---------------------------------------------------------------------------
clone_dotfiles() {
    info "$1, cloning ${REPO_URL}"
    CLONE_DIR="$(mktemp -d)" || return 1
    git clone --depth 1 "$REPO_URL" "${CLONE_DIR}/rstl.sway" || return 1
    git -C "${CLONE_DIR}/rstl.sway" submodule update --init --depth 1 nvim || return 1
    SOURCE_DIR="${CLONE_DIR}/rstl.sway"
}

fetch_dotfiles() {
    if [ -d "${DOTFILES_DIR}/.git" ] &&
       git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        # still a checkout (a manual clone): fast-forward it in place
        info "git checkout found, pulling in place"
        if [ -n "$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null)" ]; then
            warn "local changes in ${DOTFILES_DIR}, not pulling"
        else
            git -C "$DOTFILES_DIR" pull --ff-only || return 1
        fi
        git -C "$DOTFILES_DIR" submodule update --init --depth 1 nvim ||
            warn "submodule update failed"
        SOURCE_DIR="$DOTFILES_DIR"
    else
        # an installed system has no .git: the ISO build strips it and the
        # installers never copy one in, so take a fresh shallow clone and let
        # the installer copy the result over
        clone_dotfiles "no git checkout" || return 1
    fi

    # the full edition's installer is bin/install.sh, not bin/install-install.sh
    case "$EDITION" in
        install)      INSTALLER="bin/install.sh" ;;
        install-min)  INSTALLER="bin/install-min.sh" ;;
        install-base) INSTALLER="bin/install-base.sh" ;;
    esac
    if [ -f "${SOURCE_DIR}/${INSTALLER}" ]; then
        return 0
    fi
    if [ "$SOURCE_DIR" = "$DOTFILES_DIR" ]; then
        # A checkout that is too old to have the installer where it belongs now
        # (before the bin/ move), or an incomplete one. Either way the files this
        # run needs are not in it, so fall back to a fresh clone; the installer
        # copies the result over the checkout anyway.
        warn "${INSTALLER} is not in this checkout, using a fresh clone instead"
        clone_dotfiles "checkout without ${INSTALLER}" || return 1
    fi
    [ -f "${SOURCE_DIR}/${INSTALLER}" ] ||
        die "${SOURCE_DIR}/${INSTALLER} is missing (wrong repository?)"
    return 0
}

header "fetching the newest dotfiles"
fetch_dotfiles || die "could not fetch the dotfiles (see above)"

# the package list of the fetched edition: what we are about to make sure of
LIST="${SOURCE_DIR}/packages-${EDITION}.txt"
[ -f "$LIST" ] || die "package list ${LIST} is missing"

core_list() {
    awk '/^#@/ { sect = substr($0, 3); next }
         /^#/  { next }
         NF == 0 { next }
         sect == "core" { print }' "$LIST"
}

CORE_COUNT="$(core_list | wc -l | tr -d ' ')"

# what is missing right now, before anything is changed
if command -v pacman >/dev/null 2>&1; then
    HAVE="$(mktemp)"
    pacman -Qq 2>/dev/null | sort -u > "$HAVE"
    MISSING=""
    for pkg in $(core_list); do
        grep -qxF "$pkg" "$HAVE" || MISSING="$MISSING $pkg"
    done
    rm -f "$HAVE"
    [ -n "$MISSING" ] && warn "not installed, the installer will add them:$MISSING"
fi

# ---------------------------------------------------------------------------
# go
# ---------------------------------------------------------------------------
header "update plan"
printf "  edition   %s\n" "$EDITION"
printf "  program   %s\n" "$PROGRAM"
printf "  firefox   %s\n" "$FIREFOX"
printf "  packages  %s core packages from %s\n" "$CORE_COUNT" "$(basename "$LIST")"
printf "  system    %s\n" "$([ "$DO_UPGRADE" -eq 1 ] && echo 'pacman -Syu' || echo 'no -Syu (--no-upgrade)')"
echo
confirm "update this machine now?"

if [ "$DO_UPGRADE" -eq 1 ]; then
    header "upgrading the system"
    sudo -v
    attempt=0
    until sudo pacman -Syu --noconfirm; do
        attempt=$((attempt + 1))
        [ "$attempt" -ge 3 ] && die "pacman -Syu failed after ${attempt} attempts"
        warn "pacman -Syu failed, retrying (${attempt}/3)"
        sleep 2
    done
    ok "system upgraded"
fi

header "re-applying the dotfiles (${INSTALLER})"
sudo -v
if RSTL_PROGRAM="$PROGRAM" RSTL_FIREFOX="$FIREFOX" \
   sh "${SOURCE_DIR}/${INSTALLER}" --yes --no-cleanup; then
    ok "dotfiles updated"
else
    die "the installer failed - see the output above"
fi

header "done"
printf "  reload sway to pick up the new config:  mod+Shift+c\n"
printf "  (or:                                     mod+Shift+q, then log back in)\n"
echo
