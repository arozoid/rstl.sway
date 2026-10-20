## environment setup

# editor
export EDITOR=nvim

# format man pages
export MANROFFOPT="-c"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

# append common directories to $PATH
path=(
    ~/.local/bin
    ~/.cargo/bin
    ~/Applications/depot_tools
    $path
)


## welcome message

# run fastfetch
if (( $+commands[fastfetch] )); then
    echo
    fastfetch --pipe false --logo none | sed 's/^/   /'
    echo
fi


## history
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE


## history shortcuts
bindkey -e

# !!
__history_previous_command() {
    if [[ "$LBUFFER" == "!" ]]; then
        LBUFFER="${history[1]}"
    else
        LBUFFER+="!"
    fi
    zle redisplay
}
zle -N __history_previous_command

# !$
__history_previous_command_arguments() {
    if [[ "$LBUFFER" == "!" ]]; then
        LBUFFER=""
        zle history-token-search-backward
    else
        LBUFFER+='$'
    fi
    zle redisplay
}
zle -N __history_previous_command_arguments

bindkey '!' __history_previous_command
bindkey '$' __history_previous_command_arguments


## functions

# backup a file
backup() {
    cp -- "$1" "$1.bak"
}

# copy dir1 dir2
copy() {
    if [[ $# -eq 2 && -d "$1" ]]; then
        local from="${1%/}"
        local to="$2"
        command cp -r -- "$from" "$to"
    else
        command cp "$@"
    fi
}

# obsidian git push
obipush() {
    git add .
    git commit -m "vault backup $(date '+%Y-%m-%d %H:%M:%S')"
    git push
}


## aliases

# replace ls with eza
alias ls='eza -al --color=always --group-directories-first --icons=always'
alias la='eza -a --color=always --group-directories-first --icons=always'
alias ll='eza -l --color=always --group-directories-first --icons=always'
alias lt='eza -aT --color=always --group-directories-first --icons=always'
alias l.='eza -a | grep -e "^\."'

# replace cd with zoxide
if (( $+commands[zoxide] )); then
    eval "$(zoxide init zsh --cmd cd)"
fi

# common use
alias grubup='sudo grub-mkconfig -o /boot/grub/grub.cfg'
alias fixpacman='sudo rm /var/lib/pacman/db.lck'
alias tarnow='tar -acf'
alias untar='tar -zxvf'
alias wget='wget -c'
alias psmem='ps auxf | sort -nr -k 4'
alias psmem10='ps auxf | sort -nr -k 4 | head -10'

# navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'

# core utilities
alias dir='dir --color=auto'
alias vdir='vdir --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# hardware info
alias hw='hwinfo --short'

# sort installed packages by size
alias big="expac -H M '%m\t%n' | sort -h | nl"

# list amount of -git packages
alias gitpkg='pacman -Q | grep -i "\-git" | wc -l'

# help people new to arch
alias apt='man pacman'
alias apt-get='man pacman'
alias tb='nc termbin.com 9999'

# cleanup orphaned packages
alias cleanup='sudo pacman -Rns $(pacman -Qtdq)'

# get error messages from journalctl
alias jctl='journalctl -p 3 -xb'

# recent installed packages
alias rip="expac --timefmt='%Y-%m-%d %T' '%l\t%n %v' | sort | tail -200 | nl"

# neovim -> vim
alias vim='nvim'

# obsidian-cli -> obi
alias obi='obsidian-cli'

# calculator
alias calc='~/.config/rstl.sway/scripts/calawk.sh'

## ddusb
# dependencies: dd, lsblk (always); sgdisk, partprobe, udevadm, mkfs.ext4 (--writable)

# usage:
#   ddusb image.iso
#   ddusb image.iso /dev/sdX
#   ddusb image.iso /dev/sdX --writable 2G
#   ddusb --help
ddusb() {
    emulate -L zsh

    local image=""
    local device=""
    local writable=""
    local label="WRITABLE"
    local assume_yes=0
    local arg

    # help
    if [[ "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
        cat <<'EOF'
ddusb — flash an image to a usb drive

usage:
  ddusb <image> [device] [options]

arguments:
  image                 image file to flash
  device                target disk, e.g. /dev/sdb

options:
  --writable SIZE       create an ext4 writable partition at the end
                        of the drive, e.g. 2G, 512M
  --label NAME          filesystem label (default: WRITABLE)
  -y, --yes             skip the flash confirmation
  -h, --help            show this help

examples:
  ddusb archlinux.iso
  ddusb archlinux.iso /dev/sdb
  ddusb archlinux.iso /dev/sdb --writable 2G
  ddusb live.iso /dev/sda --writable 4G --label PERSIST

notes:
  - the entire target disk is overwritten.
  - the optional writable partition requires a compatible GPT image.
  - the writable partition is formatted as ext4; persistence must be
    supported and configured by the live operating system separately.
  - missing dependencies are offered for installation via pacman,
    xbps-install or dnf before flashing begins.
  - back up important data before flashing.
EOF
        return 0
    fi

    image="$1"
    shift

    # parse arguments
    while (( $# )); do
        case "$1" in
            --writable)
                if (( $# < 2 )); then
                    print -u2 "error: --writable requires a size, e.g. 2G"
                    return 2
                fi
                writable="$2"
                shift 2
                ;;
            --label)
                if (( $# < 2 )); then
                    print -u2 "error: --label requires a name"
                    return 2
                fi
                label="$2"
                shift 2
                ;;
            -y|--yes)
                assume_yes=1
                shift
                ;;
            -h|--help)
                ddusb --help
                return
                ;;
            /dev/*)
                if [[ -n "$device" ]]; then
                    print -u2 "error: multiple target devices supplied"
                    return 2
                fi
                device="$1"
                shift
                ;;
            *)
                print -u2 "error: unknown argument: $1"
                print -u2 "run 'ddusb --help' for usage"
                return 2
                ;;
        esac
    done

    # validate image
    if [[ ! -f "$image" || ! -r "$image" ]]; then
        print -u2 "error: image not found or unreadable: $image"
        return 1
    fi

    image="${image:A}"

    # validate writable size
    if [[ -n "$writable" ]]; then
        if [[ ! "$writable" =~ '^[1-9][0-9]*([MG])$' ]]; then
            print -u2 "error: size must be a positive integer followed by M or G"
            print -u2 "example: --writable 512M"
            return 2
        fi

        if [[ ! "$label" =~ '^[a-zA-Z0-9_-]{1,16}$' ]]; then
            print -u2 "error: label must be 1–16 letters, numbers, _ or -"
            return 2
        fi
    fi

    # check only the dependencies this operation needs
    local -a required=(dd lsblk)
    if [[ -n "$writable" ]]; then
        required+=(sgdisk partprobe udevadm mkfs.ext4)
    fi

    local -a missing=()
    for arg in "${required[@]}"; do
        command -v "$arg" >/dev/null 2>&1 || missing+=("$arg")
    done

    if (( ${#missing[@]} )); then
        # pick the package manager for this distribution
        local pm=""
        if (( $+commands[pacman] )); then
            pm=pacman
        elif (( $+commands[xbps-install] )); then
            pm=xbps-install
        elif (( $+commands[dnf] )); then
            pm=dnf
        fi

        # command -> package name, per distribution
        local -A pkgmap
        case "$pm" in
            pacman)
                pkgmap=(dd coreutils lsblk util-linux sgdisk gptfdisk partprobe parted udevadm systemd mkfs.ext4 e2fsprogs)
                ;;
            xbps-install)
                pkgmap=(dd coreutils lsblk util-linux sgdisk gptfdisk partprobe parted udevadm eudev mkfs.ext4 e2fsprogs)
                ;;
            dnf)
                pkgmap=(dd coreutils lsblk util-linux sgdisk gdisk partprobe parted udevadm systemd-udev mkfs.ext4 e2fsprogs)
                ;;
        esac

        local -a pkgs=()
        local -A seen
        seen=()
        local dep p
        for dep in "${missing[@]}"; do
            p="${pkgmap[$dep]:-$dep}"
            if [[ -z "${seen[$p]:-}" ]]; then
                seen[$p]=1
                pkgs+=("$p")
            fi
        done

        print -u2 "missing dependencies for this operation: ${missing[*]}"

        if [[ -z "$pm" ]]; then
            print -u2 "error: could not detect a supported package manager (pacman, xbps-install or dnf)"
            print -u2 "install the missing commands above with your package manager"
            return 1
        fi

        print -u2 "packages needed: ${pkgs[*]}"

        local -a install_cmd
        case "$pm" in
            pacman) install_cmd=(sudo pacman -S --needed --noconfirm "${pkgs[@]}") ;;
            xbps-install) install_cmd=(sudo xbps-install -S -y "${pkgs[@]}") ;;
            dnf) install_cmd=(sudo dnf install -y "${pkgs[@]}") ;;
        esac

        print -u2 "install with: ${install_cmd[*]}"

        local reply
        read "reply?install them now? [Y/n] "
        if [[ "$reply" == "n" || "$reply" == "N" ]]; then
            print -u2 "aborted: install the missing dependencies and try again"
            return 1
        fi

        if ! "${install_cmd[@]}"; then
            print -u2 "error: failed to install dependencies"
            return 1
        fi

        # make sure everything is available now
        missing=()
        for dep in "${required[@]}"; do
            command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
        done
        if (( ${#missing[@]} )); then
            print -u2 "error: still missing after install: ${missing[*]}"
            return 1
        fi
    fi

    # discover a target if none was provided
    if [[ -z "$device" ]]; then
        print "available disks:"
        lsblk -dpno NAME,SIZE,MODEL,TRAN,TYPE | awk '$5 == "disk"'
        print
        read "device?target disk (e.g. /dev/sdb): "
    fi

    # validate target
    if [[ ! -b "$device" ]]; then
        print -u2 "error: not a block device: $device"
        return 1
    fi

    device="$(readlink -f "$device")"

    if [[ "$(lsblk -dnro TYPE "$device")" != "disk" ]]; then
        print -u2 "error: target must be a whole disk, not a partition"
        return 1
    fi

    # refuse mounted target partitions
    if lsblk -nrpo MOUNTPOINT "$device" | grep -q '[^[:space:]]'; then
        print -u2 "error: the target disk has mounted filesystems"
        print -u2 "unmount its partitions before flashing"
        return 1
    fi

    # writable partitions require GPT support in the flashed image
    if [[ -n "$writable" ]]; then
        print "checking image partition table..."

        if ! sudo sgdisk -p "$device" >/dev/null 2>&1; then
            print -u2 "error: unable to read a GPT partition table on the target"
            print -u2 "flash without --writable, or use a compatible GPT image"
            return 1
        fi
    fi

    # confirm destructive operation
    print
    print "image:  $image"
    print "target: $device ($(lsblk -dnro SIZE "$device"))"
    print "model:  $(lsblk -dnro MODEL "$device" | sed 's/^[[:space:]]*//')"

    if [[ -n "$writable" ]]; then
        print "extra:  ${writable} ext4 partition labeled $label"
    fi

    print
    print "WARNING: all existing data on $device will be destroyed."

    if (( ! assume_yes )); then
        read "reply?type YES to continue: "
        [[ "$reply" == "YES" ]] || {
            print "cancelled."
            return 1
        }
    fi

    # flash the image
    print
    print "flashing image..."

    if ! sudo dd if="$image" of="$device" bs=4M status=progress conv=fsync; then
        print -u2 "error: flashing failed"
        return 1
    fi

    print
    print "image written successfully."

    # optionally create a writable ext4 partition
    if [[ -n "$writable" ]]; then
        print "relocating backup GPT and creating writable partition..."

        if ! sudo sgdisk -e "$device"; then
            print -u2 "error: unable to relocate backup GPT"
            return 1
        fi

        if ! sudo sgdisk \
            -n "0:0:+${writable}" \
            -t "0:8300" \
            -c "0:${label}" \
            "$device"; then
            print -u2 "error: failed to create writable partition"
            return 1
        fi

        sudo partprobe "$device" || true
        sudo udevadm settle

        # identify the newly created final partition
        local partition
        partition="$(lsblk -lnpo NAME,TYPE "$device" |
            awk '$2 == "part" { p = $1 } END { print p }')"

        if [[ -z "$partition" ]]; then
            print -u2 "error: could not identify the new partition"
            return 1
        fi

        print "formatting $partition as ext4..."

        if ! sudo mkfs.ext4 -F -L "$label" "$partition"; then
            print -u2 "error: failed to format writable partition"
            return 1
        fi

        print "writable partition created: $partition"
    fi

    print
    print "done! safely eject the usb before removing it."
}

## less

# allow less to output ansi escape codes and nerd fonts
export LESS='-R'
export LESSUTFCHARDEF='e000-e09f:w,e0a0-e0bf:p,e0c0-f8ff:w,f0001-fffff:w'


## zsh completion
zmodload zsh/complist

fpath=(
    /usr/share/zsh/site-functions
    $fpath
)

autoload -Uz compinit
compinit


## completion appearance

# don't show the "n/n" or "n possibilities" prompt
zstyle ':completion:*' list-prompt ''
zstyle ':completion:*' select-prompt ''

# use "-" as the list separator
zstyle ':completion:*' list-separator $'\e[0m \e[38;5;179m-'

# keep commands, arguments, and subcommands white
zstyle ':completion:*:commands' list-colors '=(#b)(*)=37'
zstyle ':completion:*:arguments' list-colors '=(#b)(*)=37'

zstyle ':completion:*:*:*:*:subcommands' list-colors '=(#b)(*)=37'
zstyle ':completion:*:*:*:*:-commands' list-colors '=(#b)(*)=37'
zstyle ':completion:*:*:*:*:*commands' list-colors '=(#b)(*)=37'


# keep the completion list compact
LISTMAX=7

## zsh autosuggestions
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_STRATEGY=(history)

## zsh auto notify
if [[ -f /usr/share/zsh/plugins/zsh-auto-notify/auto-notify.plugin.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-auto-notify/auto-notify.plugin.zsh
fi

## zsh syntax highlighting
if [[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi


## syntax highlighting colors

# commands
ZSH_HIGHLIGHT_STYLES[command]='fg=white'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=white'
ZSH_HIGHLIGHT_STYLES[function]='fg=white'
ZSH_HIGHLIGHT_STYLES[alias]='fg=white'
ZSH_HIGHLIGHT_STYLES[hashed-command]='fg=white'
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=white'

# sudo
ZSH_HIGHLIGHT_STYLES[precommand]='fg=179'

# invalid commands
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=red'

# arguments / paths / options
ZSH_HIGHLIGHT_STYLES[default]='fg=179'
ZSH_HIGHLIGHT_STYLES[path]='fg=179'
ZSH_HIGHLIGHT_STYLES[path_prefix]='fg=179'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=179'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=179'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=179'

# quoted strings
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=214'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=214'


## keybindings

# backspace
bindkey '^H' backward-kill-word

# ctrl + left / right
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word

## prompt
PROMPT='%F{green}%n%f@%f%m%f %F{green}%~%f ${USER_CHAR} '
setopt PROMPT_SUBST
if [ "$UID" -eq 0 ]; then
    USER_CHAR="#"
else
    USER_CHAR="$"
fi


