#!/bin/bash
# values.sh NAME... [-- COMMAND...] — the external values a snippet needs,
# as one JSON object: {"values": {name: text}, "commands": {command: output}}.
# Commands come only from snippets marked executable (chmod +x).

declare -a names=() cmds=()
while (( $# )); do
  [[ $1 == -- ]] && { shift; cmds=("$@"); break; }
  names+=("$1"); shift
done

value() {
  case $1 in
    clipboard) wl-paste -n --type text 2>/dev/null ;;
    selection) wl-paste -p -n --type text 2>/dev/null ;;
    hostname) cat /etc/hostname 2>/dev/null || hostname ;;
    user) printf '%s' "$USER" ;;
    fullname) git config --global user.name 2>/dev/null || getent passwd "$USER" | cut -d: -f5 | cut -d, -f1 ;;
    email) git config --global user.email 2>/dev/null ;;
    ip) ip -4 route get 1.1.1.1 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit } }' ;;
    publicip) curl -fsS -m 4 https://api.ipify.org 2>/dev/null ;;
  esac
}

{
  for n in "${names[@]}"; do printf '%s\0%s\0' "$n" "$(value "$n")"; done
} | jq -Rs 'split("\u0000") | . as $a | [range(0; (length / 2 | floor)) | {key: $a[2 * .], value: $a[2 * . + 1]}] | from_entries' >"${TMPDIR:-/tmp}/omalaunch-values.$$"

{
  for c in "${cmds[@]}"; do printf '%s\0%s\0' "$c" "$(timeout 10 bash -c "$c" 2>/dev/null)"; done
} | jq -Rs 'split("\u0000") | . as $a | [range(0; (length / 2 | floor)) | {key: $a[2 * .], value: $a[2 * . + 1]}] | from_entries' >"${TMPDIR:-/tmp}/omalaunch-cmds.$$"

jq -n --slurpfile v "${TMPDIR:-/tmp}/omalaunch-values.$$" --slurpfile c "${TMPDIR:-/tmp}/omalaunch-cmds.$$" '{values: $v[0], commands: $c[0]}'
rm -f "${TMPDIR:-/tmp}/omalaunch-values.$$" "${TMPDIR:-/tmp}/omalaunch-cmds.$$"
