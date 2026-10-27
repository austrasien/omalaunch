#!/usr/bin/env bash
# Prints "Name<TAB>Icon" of the default browser. A default with no icon (a
# router such as open-in-webapps) is followed to the real browser it hands
# URLs to.
dirs=("${XDG_DATA_HOME:-$HOME/.local/share}" ${XDG_DATA_DIRS//:/ } /usr/local/share /usr/share)

desktop_file() {
  local d
  for d in "${dirs[@]}"; do [[ -f $d/applications/$1 ]] && { echo "$d/applications/$1"; return; }; done
}
field() { sed -n "/^\[Desktop Entry\]/,/^\[/{s/^$1=//p}" "$2" | head -1; }

id=$(omarchy-cmd-default-browser 2>/dev/null || xdg-settings get default-web-browser 2>/dev/null)
file=$(desktop_file "$id")
[[ -n $file ]] || exit 1
icon=$(field Icon "$file")
if [[ -z $icon ]]; then
  real=$(head -n1 "${XDG_DATA_HOME:-$HOME/.local/share}/omarchy/open-in-webapps/real-browser-exec" 2>/dev/null)
  [[ -n $real ]] || exit 1
  real=${real##*/}
  for d in "${dirs[@]}"; do
    for f in "$d"/applications/*.desktop; do
      [[ -f $f ]] || continue
      exe=$(field Exec "$f"); exe=${exe%% *}
      if [[ ${exe##*/} == "$real" ]]; then file=$f; icon=$(field Icon "$f"); break 2; fi
    done
  done
fi
printf '%s\t%s\n' "$(field Name "$file")" "$icon"
