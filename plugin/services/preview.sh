#!/bin/bash
# preview.sh PATH CACHE_DIR [SIZE] — describe a file for Quick Look (docs/SPEC.md §6)
# as one JSON object:
#   { kind: image|pages|rich|text|markdown|dir|info|missing, path, name, mime,
#     size, mtime, image?, width?, height?, pages?, html?, caption?, text?, count? }
# image: one picture (photo, PDF page, slide, video frames, 3D render, cover,
#   font sample, waveform) with an optional HTML caption; pages: several
#   pictures shown one under the other (PDF); rich: HTML (syntax-coloured
#   code, tables, archive listings); markdown / text / dir as they say.
# Generated pictures go to CACHE_DIR. With SIZE (grid thumbnails) only a
# small picture is made, and text is not read.

set -uo pipefail
path=$1
cache=$2
thumbsize=${3:-0}
big=$(( thumbsize > 0 ? thumbsize : 1600 ))
max_text=65536
here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
extra() { timeout 20 python3 "$here/preview_extra.py" "$@" 2>/dev/null; }

html="" caption="" pages="[]"

emit() { # emit KIND IMAGE TEXT [COUNT]
  local dims="" w="" h="" first="$2"
  [[ $1 == pages ]] && first=$(jq -r '.[0] // ""' <<<"$pages")
  [[ $1 == image || $1 == pages ]] && dims=$(magick identify -format '%w %h' -- "$first[0]" 2>/dev/null) && read -r w h <<<"$dims"
  jq -n --arg kind "$1" --arg path "$path" --arg name "${path##*/}" --arg mime "${mime:-}" \
    --arg size "${size:-0}" --arg mtime "${mtime:-0}" --arg image "$2" --arg text "$3" --arg count "${4:-}" \
    --arg w "$w" --arg h "$h" --arg html "$html" --arg caption "$caption" --argjson pages "$pages" \
    '{kind: $kind, path: $path, name: $name, mime: $mime, size: ($size|tonumber), mtime: ($mtime|tonumber),
      image: $image, text: $text, html: $html, caption: $caption, pages: $pages}
      + (if $count == "" then {} else {count: ($count|tonumber)} end)
      + (if $w == "" or $h == "" then {} else {width: ($w|tonumber), height: ($h|tonumber)} end)'
  exit 0
}

esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' <<<"$1"; }

# "1h 02 min" / "3 min 20 s" from seconds.
duration() {
  local s=${1%.*}
  [[ $s =~ ^[0-9]+$ ]] || return
  if (( s >= 3600 )); then printf '%dh %02d min' $((s / 3600)) $((s % 3600 / 60))
  else printf '%d min %02d s' $((s / 60)) $((s % 60)); fi
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

# The first sheet of a spreadsheet as CSV, through LibreOffice.
sheet_csv() {
  command -v soffice >/dev/null || return 1
  local dir="$cache/sheet-$$"
  mkdir -p "$dir"
  timeout 25 soffice -env:UserInstallation="file://$cache/lo-profile" --headless --convert-to csv --outdir "$dir" "$path" >/dev/null 2>&1
  local out=("$dir"/*.csv)
  [[ -s ${out[0]} ]] && cp "${out[0]}" "$1"
  rm -rf "$dir"
  [[ -s $1 ]]
}

[[ -e $path ]] || emit missing "" ""

mime=$(file -b --mime-type -- "$path" 2>/dev/null)
size=$(stat -c %s -- "$path" 2>/dev/null || echo 0)
mtime=$(stat -c %Y -- "$path" 2>/dev/null || echo 0)
mkdir -p "$cache"
key=$(printf '%s:%s:%s' "$path" "$mtime" "$thumbsize" | md5sum | cut -c1-24)
thumb="$cache/$key.png"
lower=${path,,}

# ------------------------------------------------------------- folders
if [[ -d $path ]]; then
  if [[ -d $path/.git ]] && (( thumbsize == 0 )); then
    branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null)
    last=$(git -C "$path" log -1 --format='%h %s (%cr)' 2>/dev/null)
    status=$(git -C "$path" status --short 2>/dev/null | head -n 15)
    readme=$(find "$path" -maxdepth 1 -iname 'readme*' -type f | head -n1)
    md="**Git** · branch \`${branch:-?}\`"$'\n\n'"Last commit: ${last:-none}"$'\n\n'
    if [[ -n $status ]]; then md+="**Changes**"$'\n\n```\n'"$status"$'\n```\n\n'; else md+="*Working tree clean*"$'\n\n'; fi
    [[ -n $readme ]] && md+=$'---\n\n'"$(head -c "$max_text" -- "$readme")"
    emit markdown "" "$md"
  fi
  listing=$(ls -1Ap --group-directories-first -- "$path" 2>/dev/null)
  count=$(grep -c . <<<"$listing")
  emit dir "" "$(head -n 300 <<<"$listing")" "$count"
fi

# ----------------------------------------------------------- 3D models
case $lower in
  *.stl | *.obj | *.3mf | *.step | *.stp | *.ply | *.gltf | *.glb | *.fbx | *.off)
    if [[ $lower != *.obj ]] || grep -qm1 '^v ' -- "$path" 2>/dev/null; then
      dims=""
      case $lower in *.stl | *.obj | *.3mf) dims=$(extra bbox "$path") ;; esac
      [[ -n $dims ]] && caption="<b>$(esc "$dims")</b> (model units, usually mm)"
      if command -v f3d >/dev/null; then
        [[ -s $thumb ]] || timeout 40 f3d --output="$thumb" --resolution="$big,$(( big * 3 / 4 ))" --up=+Z --anti-aliasing "$path" >/dev/null 2>&1
        [[ -s $thumb ]] && emit image "$thumb" ""
      elif (( thumbsize == 0 )); then
        caption+="${caption:+<br>}Install f3d for a 3D view: <tt>sudo pacman -S f3d</tt>"
      fi
      emit info "" ""
    fi ;;
esac

# --------------------------------------------------------------- fonts
case $lower in
  *.ttf | *.otf | *.woff | *.woff2 | *.ttc)
    family=$(fc-scan --format '%{family[0]} %{style[0]}' -- "$path" 2>/dev/null | head -n1)
    if [[ ! -s $thumb ]]; then
      if (( thumbsize > 0 )); then sample="Aa"; pt=$(( thumbsize / 3 ))
      else sample=$'Aa Bb Cc Dd Ee\nPortez ce vieux whisky\nau juge blond qui fume.\n0123456789 !?&@€'; pt=96; fi
      magick -background '#1a1b26' -fill '#e0e2ea' -font "$path" -pointsize "$pt" label:"$sample" -bordercolor '#1a1b26' -border 40 "$thumb" 2>/dev/null
    fi
    caption="<b>$(esc "${family:-${path##*/}}")</b>"
    [[ -s $thumb ]] && emit image "$thumb" ""
    emit info "" "" ;;
esac

# ---------------------------------------------------------------- epub
if [[ $lower == *.epub ]]; then
  meta=$(extra epub "$path" "$cache")
  cover=$(jq -r '.cover // ""' <<<"$meta" 2>/dev/null)
  title=$(jq -r '.title // ""' <<<"$meta" 2>/dev/null)
  author=$(jq -r '.author // ""' <<<"$meta" 2>/dev/null)
  caption="<b>$(esc "$title")</b>${author:+<br>$(esc "$author")}"
  [[ -n $cover && -s $cover ]] && emit image "$cover" ""
  emit info "" ""
fi

# ------------------------------------------------------------ archives
case $lower in
  *.zip | *.tar | *.tar.gz | *.tgz | *.tar.xz | *.txz | *.tar.zst | *.tzst | *.tar.bz2 | *.tbz2 | *.7z | *.rar | *.jar | *.apk | *.xpi | *.iso)
    (( thumbsize > 0 )) && emit info "" ""
    html=$(extra archive "$path")
    [[ -n $html ]] && emit rich "" ""
    emit info "" "" ;;
esac

# -------------------------------------------------------- spreadsheets
case $lower in
  *.csv | *.tsv)
    (( thumbsize > 0 )) && emit info "" ""
    html=$(extra table "$path")
    [[ -n $html ]] && emit rich "" "" ;;
  *.xlsx | *.xls | *.ods)
    if (( thumbsize == 0 )); then
      tmp="$cache/$key.csv"
      { [[ -s $tmp ]] || sheet_csv "$tmp"; } && html=$(extra table "$tmp")
      [[ -n $html ]] && { caption="First sheet"; emit rich "" ""; }
    fi ;;
esac

# ---------------------------------------------------------------- media
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
    if (( thumbsize > 0 )); then
      [[ -s $thumb ]] || pdftoppm -png -f 1 -l 1 -scale-to "$big" -singlefile -- "$path" "${thumb%.png}" 2>/dev/null
      [[ -s $thumb ]] && emit image "$thumb" ""
      emit info "" ""
    fi
    count=$(pdfinfo -- "$path" 2>/dev/null | awk '/^Pages:/ { print $2 }')
    prefix="$cache/$key-page"
    shopt -s nullglob
    rendered=("$prefix"-*.png)
    (( ${#rendered[@]} )) || pdftoppm -png -f 1 -l 8 -scale-to "$big" -- "$path" "$prefix" 2>/dev/null
    rendered=("$prefix"-*.png)
    if (( ${#rendered[@]} )); then
      pages=$(printf '%s\n' "${rendered[@]}" | sort -V | jq -R . | jq -s .)
      caption="${count:-?} page$( [[ ${count:-0} == 1 ]] || echo s)$( (( ${count:-0} > 8 )) && echo ", the first 8 shown")"
      emit pages "" "" "${count:-0}"
    fi
    emit info "" "" ;;
  video/*)
    info=$(ffprobe -v quiet -print_format json -show_format -show_streams -- "$path" 2>/dev/null)
    dur=$(jq -r '.format.duration // empty' <<<"$info")
    if [[ ! -s $thumb ]]; then
      if (( thumbsize > 0 )) || [[ -z $dur ]]; then
        ffmpegthumbnailer -i "$path" -o "$thumb" -s "$(( thumbsize > 0 ? thumbsize : 1280 ))" -q 8 2>/dev/null
      else
        # Six frames spread over the video, in a 3 × 2 contact sheet.
        frames=()
        for i in 1 2 3 4 5 6; do
          t=$(awk -v d="$dur" -v i="$i" 'BEGIN { printf "%.2f", d * (i - 0.5) / 6 }')
          f="$cache/$key-f$i.png"
          timeout 15 ffmpeg -nostdin -v quiet -ss "$t" -i "$path" -frames:v 1 -vf scale=640:-2 -y "$f" && frames+=("$f")
        done
        if (( ${#frames[@]} == 6 )); then
          magick \( "${frames[@]:0:3}" +append \) \( "${frames[@]:3:3}" +append \) -append "$thumb" 2>/dev/null
        fi
        rm -f "${frames[@]}"
      fi
    fi
    if (( thumbsize == 0 )); then
      v=$(jq -r '[.streams[] | select(.codec_type == "video")][0] | "\(.width)×\(.height)  ·  \(.codec_name)  ·  \(.r_frame_rate | split("/") | (.[0] | tonumber) / ((.[1] // "1") | tonumber) | floor) fps"' <<<"$info" 2>/dev/null)
      caption="<b>$(duration "$dur")</b>  ·  $(esc "$v")"
    fi
    [[ -s $thumb ]] && emit image "$thumb" ""
    emit info "" "" ;;
  audio/*)
    info=$(ffprobe -v quiet -print_format json -show_format -show_streams -- "$path" 2>/dev/null)
    if [[ ! -s $thumb ]]; then
      timeout 15 ffmpeg -nostdin -v quiet -i "$path" -an -frames:v 1 -y "$thumb" 2>/dev/null
      if [[ ! -s $thumb ]]; then
        rm -f "$thumb"
        timeout 30 ffmpeg -nostdin -v quiet -i "$path" -filter_complex "aformat=channel_layouts=mono,showwavespic=s=${big}x$(( big / 4 )):colors=#7aa2f7" -frames:v 1 -y "$thumb" 2>/dev/null
      fi
    fi
    if (( thumbsize == 0 )); then
      tag() { jq -r --arg k "$1" '[.format.tags // {} | to_entries[] | select(.key | ascii_downcase == $k) | .value][0] // ""' <<<"$info"; }
      t=$(tag title) a=$(tag artist) al=$(tag album)
      dur=$(jq -r '.format.duration // empty' <<<"$info")
      br=$(jq -r '((.format.bit_rate // "0") | tonumber / 1000 | floor | tostring) + " kb/s"' <<<"$info")
      caption="<b>$(esc "${t:-${path##*/}}")</b>${a:+<br>$(esc "$a")}${al:+ — $(esc "$al")}<br>$(duration "$dur")  ·  $br"
    fi
    [[ -s $thumb ]] && emit image "$thumb" ""
    emit info "" "" ;;
  application/vnd.openxmlformats-officedocument.* | application/vnd.oasis.opendocument.* | application/msword \
  | application/vnd.ms-excel | application/vnd.ms-powerpoint | application/vnd.apple.keynote | application/rtf)
    { [[ -s $thumb ]] || office_thumb; } && emit image "$thumb" ""
    emit info "" "" ;;
esac
case $lower in
  *.key | *.pages | *.numbers)
    { [[ -s $thumb ]] || office_thumb; } && emit image "$thumb" "" ;;
esac

(( thumbsize > 0 )) && emit info "" ""

# ----------------------------------------------------------------- text
if [[ $mime == text/* || $mime == application/json || $mime == application/xml || $mime == *javascript* \
   || $mime == *x-shellscript* || $mime == application/x-empty || $mime == inode/x-empty ]] \
   || { (( size < 4194304 )) && ! head -c 8192 -- "$path" | grep -qaP '\x00'; }; then
  case $lower in
    *.md | *.markdown)
      dir=$path
      while [[ $dir != / && ! -d $dir/.obsidian ]]; do dir=$(dirname "$dir"); done
      if [[ $dir != / ]]; then
        note=$(extra note "$path")
        [[ -n $note ]] && emit markdown "" "$note"
      fi
      emit markdown "" "$(head -c "$max_text" -- "$path" | iconv -f utf-8 -t utf-8 -c 2>/dev/null)" ;;
    *.txt | *.log | *.text | */readme | */license | */copying)
      ;;
    *)
      if (( size < 400000 )); then
        html=$(extra code "$path")
        [[ -n $html ]] && emit rich "" ""
      fi ;;
  esac
  emit text "" "$(head -c "$max_text" -- "$path" | iconv -f utf-8 -t utf-8 -c 2>/dev/null)"
fi

emit info "" ""
