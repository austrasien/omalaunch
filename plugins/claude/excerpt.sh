#!/bin/bash
# excerpt.sh FILE [N] — the last N exchanges of a Claude Code session as
# Markdown, for Quick Look.

file=$1
n=${2:-12}
tail -n 2000 -- "$file" | jq -r --argjson n "$n" -s '
  [ .[]
    | select(.type == "user" or .type == "assistant")
    | select(.isMeta != true and .isSidechain != true)
    | { who: .type,
        text: (.message.content
               | if type == "string" then .
                 else ([.[] | select(.type == "text") | .text] | join("\n\n")) end) }
    | select(.text != "" and (.text | startswith("<") | not)) ]
  | .[-$n:]
  | map((if .who == "user" then "**Toi**" else "**Claude**" end) + "\n\n" + (.text | if length > 1500 then .[0:1500] + " …" else . end))
  | join("\n\n---\n\n")' 2>/dev/null
