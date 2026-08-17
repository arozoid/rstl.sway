#!/bin/sh
# lf previewer script

file="$1"
w="$2"
h="$3"

case "$(file -Lb --mime-type "$file")" in
    image/*) chafa -f sixel -s "${w}x${h}" -- "$file" ;;
    text/*|application/json) bat --style=plain --color=always --wrap=character --terminal-width="$w" "$file" 2>/dev/null || cat "$file" 2>/dev/null ;;
    application/pdf) pdftotext "$file" - 2>/dev/null | head -n "$h" ;;
    application/zip) unzip -l "$file" 2>/dev/null | head -n "$h" ;;
    *) file -Lb "$file" 2>/dev/null | head -n "$h" ;;
esac
