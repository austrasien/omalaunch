// Pure helpers for the files plugin (tested in tests/files.test.js).

var PREFIX = /^(?:'|find\s+)\s*(.*\S)\s*$/i

// The search terms after "'" or "find ", or null.
function termsFrom(query) {
  var m = PREFIX.exec(String(query || ""))
  if (!m) return null
  var words = m[1].toLowerCase().split(/\s+/).filter(function(w) { return w })
  return words.length ? words : null
}

function basename(path) {
  var p = String(path).replace(/\/+$/, "")
  return p.slice(p.lastIndexOf("/") + 1)
}

function tilde(path, home) {
  return home && path.indexOf(home + "/") === 0 ? "~" + path.slice(home.length) : path
}

// Keep paths whose full path holds every word, best first: name equal to
// the first word, name starting with it, name containing it, then shorter
// paths.
function rank(paths, words, limit) {
  var first = words[0]
  var scored = []
  for (var i = 0; i < paths.length; i++) {
    var p = paths[i]
    if (!p) continue
    var low = p.toLowerCase()
    var ok = true
    for (var w = 0; w < words.length; w++) if (low.indexOf(words[w]) < 0) { ok = false; break }
    if (!ok) continue
    var name = basename(low)
    var stem = name.replace(/\.[^.]*$/, "")
    var s = stem === first || name === first ? 0 : (name.indexOf(first) === 0 ? 1 : (name.indexOf(first) >= 0 ? 2 : 3))
    var bare = p.replace(/\/+$/, "")
    scored.push({ path: p, s: s, depth: bare.split("/").length, len: bare.length })
  }
  scored.sort(function(a, b) { return a.s - b.s || a.depth - b.depth || a.len - b.len })
  return scored.slice(0, limit || 30).map(function(x) { return x.path })
}

// Search filters: a keyword limited to some extensions and folders, from
// ~/.config/omalaunch/file-filters.json (these defaults when it is absent).
var DEFAULT_FILTERS = [
  { keyword: "pdf", title: "PDFs", extensions: ["pdf"] },
  { keyword: "img", title: "Images", extensions: ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "avif"] },
  { keyword: "doc", title: "Documents", extensions: ["pdf", "odt", "ods", "odp", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "md", "txt", "rtf", "csv"] },
  { keyword: "vid", title: "Videos", extensions: ["mp4", "mkv", "mov", "webm", "avi"] }
]

// Valid filters from the parsed config: keyword (one word), title,
// extensions (without dots), folders (default ["~"]), hidden, type
// ("file", "folder" or "any").
function normalizeFilters(list) {
  if (!Array.isArray(list)) return []
  var out = []
  var taken = {}
  for (var i = 0; i < list.length; i++) {
    var f = list[i] || {}
    var kw = String(f.keyword || "").trim().toLowerCase()
    if (!/^\S+$/.test(kw) || taken[kw]) continue
    taken[kw] = true
    var ext = Array.isArray(f.extensions) ? f.extensions.map(function(e) { return String(e).replace(/^\./, "").toLowerCase() }).filter(function(e) { return /^[a-z0-9]+$/.test(e) }) : []
    var folders = Array.isArray(f.folders) && f.folders.length ? f.folders.map(String) : ["~"]
    var type = f.type === "folder" || f.type === "any" ? f.type : (ext.length ? "file" : "any")
    out.push({ keyword: kw, title: String(f.title || kw), extensions: ext, folders: folders, hidden: !!f.hidden, type: type })
  }
  return out
}

// { filter, words } when the query is "<keyword> " + terms (terms may be
// empty: newest files first), else null.
function filterFor(query, filters) {
  var q = String(query || "").replace(/^\s+/, "")
  var sp = q.indexOf(" ")
  if (sp < 1) return null
  var kw = q.slice(0, sp).toLowerCase()
  for (var i = 0; i < filters.length; i++) {
    if (filters[i].keyword === kw) {
      return { filter: filters[i], words: q.slice(sp + 1).toLowerCase().split(/\s+/).filter(function(w) { return w }) }
    }
  }
  return null
}

function expandHome(path, home) {
  return path === "~" ? home : (path.indexOf("~/") === 0 ? home + path.slice(1) : path)
}

// fd arguments for a filter (pattern "." when there are no words).
function fdArgs(filter, words, home) {
  var args = ["-i", "-F", "--absolute-path"]
  if (filter.hidden) args.push("-H")
  if (filter.type === "file") args.push("-t", "f")
  else if (filter.type === "folder") args.push("-t", "d")
  filter.extensions.forEach(function(e) { args.push("-e", e) })
  args.push("--", words.length ? words[0] : ".")
  return args.concat(filter.folders.map(function(f) { return expandHome(f, home) }))
}

// recently-used.xbel (freedesktop) → [{ path, modified }], newest first,
// file:// entries only.
function parseRecent(xml) {
  var out = []
  var seen = {}
  var re = /<bookmark\b([^>]*)>/g
  var m
  while ((m = re.exec(String(xml || "")))) {
    var attrs = m[1]
    var href = /\bhref="([^"]*)"/.exec(attrs)
    if (!href || href[1].indexOf("file://") !== 0) continue
    var path
    try { path = decodeURIComponent(href[1].slice(7)) } catch (e) { continue }
    path = path.replace(/&amp;/g, "&").replace(/&apos;/g, "'").replace(/&quot;/g, '"').replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    var mod = /\bmodified="([^"]*)"/.exec(attrs) || /\bvisited="([^"]*)"/.exec(attrs)
    var t = mod ? Date.parse(mod[1]) : 0
    if (seen[path] !== undefined) { out[seen[path]].modified = Math.max(out[seen[path]].modified, t || 0); continue }
    seen[path] = out.length
    out.push({ path: path, modified: t || 0 })
  }
  out.sort(function(a, b) { return b.modified - a.modified })
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    termsFrom: termsFrom, basename: basename, tilde: tilde, rank: rank, parseRecent: parseRecent,
    DEFAULT_FILTERS: DEFAULT_FILTERS, normalizeFilters: normalizeFilters, filterFor: filterFor, fdArgs: fdArgs
  }
}
