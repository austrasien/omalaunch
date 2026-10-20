#!/bin/bash
# preview.sh PATH CACHE_DIR [SIZE] — describe a file for Quick Look (docs/SPEC.md §6)
# as one JSON object:
#   { kind: image|text|markdown|dir|info|missing, path, name, mime, size,
#     mtime, image?, width?, height?, text?, count? }
# PDFs, videos, office documents and images Qt cannot read become a PNG in
# CACHE_DIR. Images carry their pixel size so the pane can match its shape.
# With SIZE (grid thumbnails), images are always scaled down to SIZE px and
# text is not read.

set -uo pipefail
path=$1
cache=$2
thumbsize=${3:-0}
big=$(( thumbsize > 0 ? thumbsize : 1600 ))
max_text=65536

emit() { # emit KIND IMAGE TEXT [COUNT]
  local dims="" w="" h=""
  [[ $1 == image ]] && dims=$(magick identify -format '%w %h' -- "$2[0]" 2>/dev/null) && read -r w h <<<"$dims"
  jq -n --arg kind "$1" --arg path "$path" --arg name "${path##*/}" --arg mime "${mime:-}" \
    --arg size "${size:-0}" --arg mtime "${mtime:-0}" --arg image "$2" --arg text "$3" --arg count "${4:-}" \
    --arg w "$w" --arg h "$h" \
    '{kind: $kind, path: $path, name: $name, mime: $mime, size: ($size|tonumber), mtime: ($mtime|tonumber),
      image: $image, text: $text} + (if $count == "" then {} else {count: ($count|tonumber)} end)
      + (if $w == "" or $h == "" then {} else {width: ($w|tonumber), height: ($h|tonumber)} end)'
  exit 0
}

# First page or slide of an office document, through LibreOffice (its own
# profile, so a running LibreOffice is not disturbed).
office_thumb() {
  command -v soffice >/dev/null || return 1
  local dir="$cache/office-$$"
  mkdir -p "$dir"
  timeout 25 soffice -env:UserInstallation="file://$cache/lo-profile" --headless --convert-to png --outdir "$dir" "$path" >/dev/null 2>&1
  local out=("$dir"/*.png)
  [[ -s ${out[0]} ]] && magick -- "${out[0]}" -resize "${big}x${big}>" "$thumb" 2>/dev/null
  rm -rf "$dir"
  [[ -s $thumb ]]
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
thumb="$cache/$(printf '%s:%s:%s' "$path" "$mtime" "$thumbsize" | md5sum | cut -c1-24).png"

case $mime in
  image/png | image/jpeg | image/gif | image/webp | image/svg+xml | image/bmp)
    if (( thumbsize > 0 )); then
      [[ -s $thumb ]] || magick -- "$path[0]" -thumbnail "${thumbsize}x${thumbsize}>" "$thumb" 2>/dev/null
      [[ -s $thumb ]] && emit image "$thumb" ""
    fi
    emit image "$path" "" ;;
  image/*)
    [[ -s $thumb ]] || magick -- "$path[0]" -resize "${big}x${big}>" "$thumb" 2>/dev/null
    [[ -s $thumb ]] && emit image "$thumb" ""
    emit info "" "" ;;
  application/pdf)
    [[ -s $thumb ]] || pdftoppm -png -f 1 -l 1 -scale-to "$big" -singlefile -- "$path" "${thumb%.png}" 2>/dev/null
    [[ -s $thumb ]] && emit image "$thumb" ""
    emit info "" "" ;;
  video/*)
    [[ -s $thumb ]] || ffmpegthumbnailer -i "$path" -o "$thumb" -s "$(( thumbsize > 0 ? thumbsize : 1280 ))" -q 8 2>/dev/null
    [[ -s $thumb ]] && emit image "$thumb" ""
    emit info "" "" ;;
  application/vnd.openxmlformats-officedocument.* | application/vnd.oasis.opendocument.* | application/msword \
  | application/vnd.ms-excel | application/vnd.ms-powerpoint | application/vnd.apple.keynote | application/rtf)
    { [[ -s $thumb ]] || office_thumb; } && emit image "$thumb" ""
    emit info "" "" ;;
esac
case ${path,,} in
  *.key | *.pages | *.numbers)
    { [[ -s $thumb ]] || office_thumb; } && emit image "$thumb" "" ;;
esac

(( thumbsize > 0 )) && emit info "" ""

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
