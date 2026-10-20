#!/bin/bash
# preview.sh PATH CACHE_DIR — describe a file for Quick Look (docs/SPEC.md §6)
# as one JSON object:
#   { kind: image|text|markdown|dir|info|missing, path, name, mime, size,
#     mtime, image?, text?, count? }
# PDFs, videos and images Qt cannot read become a PNG in CACHE_DIR.

set -uo pipefail
path=$1
cache=$2
max_text=65536

emit() { # emit KIND IMAGE TEXT [COUNT]
  jq -n --arg kind "$1" --arg path "$path" --arg name "${path##*/}" --arg mime "${mime:-}" \
    --arg size "${size:-0}" --arg mtime "${mtime:-0}" --arg image "$2" --arg text "$3" --arg count "${4:-}" \
    '{kind: $kind, path: $path, name: $name, mime: $mime, size: ($size|tonumber), mtime: ($mtime|tonumber),
      image: $image, text: $text} + (if $count == "" then {} else {count: ($count|tonumber)} end)'
  exit 0
}

[[ -e $path ]] || emit missing "" ""

mime=$(file -b --mime-type -- "$path" 2>/dev/null)
size=$(stat -c %s -- "$path" 2>/dev/null || echo 0)
mtime=$(stat -c %Y -- "$path" 2>/dev/null || echo 0)

if [[ -d $path ]]; then
  listing=$(ls -1Ap --group-directories-first -- "$path" 2>/dev/null)
  count=$(grep -c . <<<"$listing")
  emit dir "" "$(head -n 300 <<<"$listing")" "$count"
fi

mkdir -p "$cache"
thumb="$cache/$(printf '%s:%s' "$path" "$mtime" | md5sum | cut -c1-24).png"

case $mime in
  image/png | image/jpeg | image/gif | image/webp | image/svg+xml | image/bmp)
    emit image "$path" "" ;;
  image/*)
    [[ -s $thumb ]] || magick -- "$path[0]" -resize '1600x1600>' "$thumb" 2>/dev/null
    [[ -s $thumb ]] && emit image "$thumb" ""
    emit info "" "" ;;
  application/pdf)
    [[ -s $thumb ]] || pdftoppm -png -f 1 -l 1 -scale-to 1600 -singlefile -- "$path" "${thumb%.png}" 2>/dev/null
    [[ -s $thumb ]] && emit image "$thumb" ""
    emit info "" "" ;;
  video/*)
    [[ -s $thumb ]] || ffmpegthumbnailer -i "$path" -o "$thumb" -s 1280 -q 8 2>/dev/null
    [[ -s $thumb ]] && emit image "$thumb" ""
    emit info "" "" ;;
esac

# Text: by mime, or a file with no NUL byte in its first 8 KiB.
if [[ $mime == text/* || $mime == application/json || $mime == application/xml || $mime == *javascript* \
   || $mime == *x-shellscript* || $mime == application/x-empty || $mime == inode/x-empty ]] \
   || { (( size < 4194304 )) && ! head -c 8192 -- "$path" | grep -qaP '\x00'; }; then
  text=$(head -c "$max_text" -- "$path" | iconv -f utf-8 -t utf-8 -c 2>/dev/null)
  case ${path,,} in
    *.md | *.markdown) emit markdown "" "$text" ;;
    *) emit text "" "$text" ;;
  esac
fi

emit info "" ""
