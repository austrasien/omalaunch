#!/bin/bash
# sessions.sh [LIMIT] — recent Claude Code sessions, newest first, one per
# line: mtime<TAB>session id<TAB>working directory<TAB>title. The title is
# the one set with /rename, else Claude's own, else the first prompt.

limit=${1:-150}
shopt -s nullglob
files=("$HOME"/.claude/projects/*/*.jsonl)
(( ${#files[@]} )) || exit 0
stat -c '%Y %n' -- "${files[@]}" | sort -rn | head -n "$limit" | while read -r mtime file; do
  id=${file##*/}; id=${id%.jsonl}
  cwd=$(rg -m1 -o --no-filename '"cwd":"[^"]*"' "$file" | head -n1 | sed 's/^"cwd":"//; s/"$//')
  [[ -n $cwd ]] || continue
  title=$(rg --no-filename '"type":"custom-title"' "$file" | tail -n1 | jq -r '.customTitle // .title // empty' 2>/dev/null)
  [[ -n $title ]] || title=$(rg --no-filename '"type":"ai-title"' "$file" | tail -n1 | jq -r '.aiTitle // empty' 2>/dev/null)
  if [[ -z $title ]]; then
    title=$(rg -m5 --no-filename '"type":"user"' "$file" | jq -r 'select(.isMeta != true) | .message.content | if type == "string" then . else ([.[] | select(.type == "text") | .text] | join(" ")) end' 2>/dev/null |
      grep -v '^<' | grep -m1 . | tr '\n\t' '  ' | cut -c1-100)
  fi
  [[ -n $title ]] || continue
  printf '%s\t%s\t%s\t%s\n' "$mtime" "$id" "$cwd" "${title//$'\t'/ }"
done
