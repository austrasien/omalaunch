// Script command headers (docs/SPEC.md §7).
//
//   #!/bin/bash
//   # @omalaunch.title Restart Waybar
//   # @omalaunch.mode toast
//   # @omalaunch.icon 󰑓
//   # @omalaunch.argument service name
//
// Mode "filter" makes a script filter: typing "<keyword> text" runs the
// script with the text as $1 and lists the JSON items it prints.
//   # @omalaunch.mode filter
//   # @omalaunch.keyword gh

var HEADER = /^\s*(?:#|\/\/|--)\s*@omalaunch\.([a-zA-Z]+)\s+(.*?)\s*$/
var MODES = { silent: true, toast: true, terminal: true, filter: true }
var MAX_ITEMS = 50
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
    argument: meta.argument || "",
    keyword: String(meta.keyword || "").trim().split(/\s+/)[0] || ""
  }
}

// The text after "<keyword> " when the query addresses a filter, else null.
// The bare keyword gives "".
function filterText(query, keyword) {
  var q = String(query || "").replace(/^\s+/, "")
  var k = String(keyword || "")
  if (!k) return null
  if (q.toLowerCase() === k.toLowerCase()) return ""
  if (q.slice(0, k.length + 1).toLowerCase() === (k + " ").toLowerCase()) return q.slice(k.length + 1).trim()
  return null
}

// Rows from a filter script's stdout: a JSON array of items, or an object
// with an "items" array. Items need a title; everything else is optional.
function parseFilterOutput(text) {
  var data
  try { data = JSON.parse(String(text || "").trim()) } catch (e) { return null }
  var list = Array.isArray(data) ? data : (data && Array.isArray(data.items) ? data.items : null)
  if (!list) return null
  var rows = []
  for (var i = 0; i < list.length && rows.length < MAX_ITEMS; i++) {
    var it = list[i]
    if (typeof it === "string") it = { title: it }
    if (!it || typeof it !== "object" || it.title === undefined || it.title === "") continue
    var arg = it.arg !== undefined ? String(it.arg) : String(it.title)
    rows.push({
      id: "item:" + i + ":" + (it.id !== undefined ? String(it.id) : arg),
      title: String(it.title),
      subtitle: it.subtitle !== undefined ? String(it.subtitle) : "",
      icon: it.icon !== undefined ? String(it.icon) : "",
      type: it.type !== undefined ? String(it.type) : "",
      arg: arg,
      open: it.open !== undefined ? String(it.open) : "",
      copy: it.copy !== undefined ? String(it.copy) : arg
    })
  }
  return rows
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
  module.exports = { parseHeader: parseHeader, argumentFrom: argumentFrom, filterText: filterText, parseFilterOutput: parseFilterOutput }
}
