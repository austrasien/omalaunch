// Script command headers (docs/SPEC.md §7).
//
//   #!/bin/bash
//   # @omalaunch.title Restart Waybar
//   # @omalaunch.mode toast
//   # @omalaunch.icon 󰑓
//   # @omalaunch.argument service name

var HEADER = /^\s*(?:#|\/\/|--)\s*@omalaunch\.([a-zA-Z]+)\s+(.*?)\s*$/
var MODES = { silent: true, toast: true, terminal: true }
var SCAN_LINES = 30

// Returns { title, mode, icon, description, argument } or null when the
// file has no title.
function parseHeader(text) {
  var lines = String(text || "").split("\n").slice(0, SCAN_LINES)
  var meta = {}
  for (var i = 0; i < lines.length; i++) {
    var m = HEADER.exec(lines[i])
    if (m) meta[m[1].toLowerCase()] = m[2]
  }
  if (!meta.title) return null
  return {
    title: meta.title,
    mode: MODES[meta.mode] ? meta.mode : "silent",
    icon: meta.icon || "",
    description: meta.description || "",
    argument: meta.argument || ""
  }
}

// When the script takes an argument and the query starts with its title
// (or alias) followed by a space, the rest of the query is the argument.
function argumentFrom(query, title, alias) {
  var q = String(query || "")
  var heads = [String(title || ""), String(alias || "")]
  for (var i = 0; i < heads.length; i++) {
    var h = heads[i]
    if (h && q.length > h.length && q.slice(0, h.length + 1).toLowerCase() === (h + " ").toLowerCase()) {
      return q.slice(h.length + 1).trim()
    }
  }
  return ""
}

if (typeof module !== "undefined") {
  module.exports = { parseHeader: parseHeader, argumentFrom: argumentFrom }
}
