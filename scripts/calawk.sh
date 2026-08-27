#!/bin/sh

if [ $# -gt 0 ]; then
    awk "BEGIN { print $* }" 2>/dev/null || echo "Error"
    exit 0
fi

echo "====== calawk ======"
echo "type expressions and press Enter. 'q' to quit | 'c' to clear."
echo ""

ans="0"

while true; do
    printf "ans[%s] > " "$ans"
    if ! read -r input; then
        echo "Goodbye!"
        break
    fi

    if [ "$input" = "q" ] || [ "$input" = "exit" ]; then
        echo "Goodbye!"
        break
    fi

    if [ "$input" = "c" ] || [ "$input" = "clear" ]; then
        ans="0"
        echo "Cleared."
        echo ""
        continue
    fi

    if [ -z "$input" ]; then
        continue
    fi

    case "$input" in
        *ans*)
            input=$(awk -v in_str="$input" -v replace="$ans" 'BEGIN { gsub(/ans/, replace, in_str); print in_str }')
            ;;
    esac

    res=$(awk "BEGIN { print $input }" 2>/dev/null)

    case "$res" in
        ""|*[eE][rR][rR][oO][rR]*)
            echo "Error: Invalid expression"
            ;;
        *)
            ans="$res"
            echo "=> $ans"
            ;;
    esac
    echo ""
done
