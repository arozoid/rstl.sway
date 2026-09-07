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
