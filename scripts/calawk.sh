#!/bin/sh

if [ $# -gt 0 ]; then
    awk "BEGIN { print $* }" 2>/dev/null || echo "Error"
    exit 0
fi

pi="3.14159265358979323846264338327950288419716939937510"
e="2.71828182845904523536028747135266249775724709369995"
tau="6.28318530717958647692528676655900576839433879875021"
phi="1.61803398874989484820458683436563811772030917980576"
ESC=$(printf '\033')
DEL=$(printf '\177')

replace() {
    awk -v s="$1" -v f="$2" -v r="$3" 'BEGIN{gsub(f,r,s);print s}'
}

evaluate() {
    awk 'BEGIN{print '"$1"'}' 2>/dev/null
}

substitute_constants() {
    _s=$(replace "$1" 'ans' "$ans")
    _s=$(replace "$_s" 'pi' "$pi")
    _s=$(replace "$_s" 'tau' "$tau")
    _s=$(replace "$_s" 'phi' "$phi")
    printf '%s' "$(replace "$_s" 'e' "$e")"
}

tty_read() {
    dd bs=1 count=1 </dev/tty 2>/dev/null
}

read_line() {
    _rl=""
    while :; do
        _ch=$(tty_read)
        [ -z "$_ch" ] && { printf '\n' > /dev/tty; return; }
        if [ "$_ch" = "$ESC" ]; then
            dd bs=2 count=1 </dev/tty >/dev/null 2>&1
            continue
        fi
        [ "$_ch" = "$DEL" ] && { [ -n "$_rl" ] && { _rl=${_rl%?}; printf '\b \b' > /dev/tty; }; continue; }
        _rl="${_rl}${_ch}"
        printf '%s' "$_ch" > /dev/tty
    done
}

_done=0
cleanup() {
    [ "$_done" = 1 ] && return
    _done=1
    stty echo icanon 2>/dev/tty
    printf '\n' > /dev/tty
}
trap cleanup EXIT INT TERM

stty -icanon -echo 2>/dev/tty

printf "====== calawk ======
type expressions and press Enter. 'q' to quit | 'c' to clear.
"
ans="0"

while :; do
    printf 'ans[%s] > ' "$ans" > /dev/tty
    read_line

    case "$_rl" in
        q|exit) printf '\nGoodbye!\n' > /dev/tty; break ;;
        c|clear) ans="0"; printf '\nCleared.\n\n' > /dev/tty; continue ;;
        "") continue ;;
    esac

    _rl=$(substitute_constants "$_rl")
    _res=$(evaluate "$_rl")

    case "$_res" in
        ""|*[eE][rR][oO][rR]*) printf 'Error: Invalid expression\n\n' > /dev/tty ;;
        *) ans="$_res"; printf '=> %s\n\n' "$ans" > /dev/tty ;;
    esac
done
