// Assemble the root list (docs/SPEC.md §4).
//
// catalog: rows from catalog providers, each
//   { key, title, subtitle?, keywords?, group: "commands"|"apps", when?: "always"|"empty"|"searching", ... }
// dynamic: sections from query providers, each
//   { id, title, placement: "inline"|"bottom", order, rows: [row] }
// Returns [{ id, title, rows }] with empty sections dropped.

var SUGGESTIONS = 6
var RESULTS_LIMIT = 80

function decorate(rows, state, now, deps) {
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (state.disabled[r.key]) continue
    var d = {}
    for (var k in r) d[k] = r[k]
    d.alias = state.aliases[r.key] || ""
    d.favorite = state.favorites.indexOf(r.key) >= 0
    d.frecency = deps.State.frecency(state, r.key, now)
    d.terms = deps.State.terms(state, r.key, now)
    out.push(d)
  }
  return out
}

function byTitle(a, b) {
  var ta = String(a.title || "").toLowerCase()
  var tb = String(b.title || "").toLowerCase()
  return ta < tb ? -1 : (ta > tb ? 1 : 0)
}

function rootSections(catalog, dynamic, query, state, now, deps) {
  var q = String(query || "").trim()
  var rows = decorate(catalog, state, now, deps)
  var sections = []
  var dyn = (dynamic || []).filter(function(s) { return s.rows && s.rows.length > 0 })
    .sort(function(a, b) { return (a.order || 0) - (b.order || 0) })

  if (q) {
    dyn.filter(function(s) { return s.placement === "inline" }).forEach(function(s) {
      sections.push({ id: s.id, title: s.title, rows: s.rows })
    })
    var searchable = rows.filter(function(r) { return r.when !== "empty" })
    var ranked = deps.Rank.rank(searchable, q).slice(0, RESULTS_LIMIT).map(function(x) { return x.row })
    if (ranked.length) sections.push({ id: "results", title: "Results", rows: ranked })
    dyn.filter(function(s) { return s.placement !== "inline" }).forEach(function(s) {
      sections.push({ id: s.id, title: s.title, rows: s.rows })
    })
    return sections
  }

  var index = {}
  rows.forEach(function(r) { index[r.key] = r })
  var taken = {}
  var favorites = []
  state.favorites.forEach(function(key) {
    if (index[key]) { favorites.push(index[key]); taken[key] = true }
  })
  var suggestions = deps.Rank.rank(rows.filter(function(r) { return !taken[r.key] && r.frecency > 0.05 }), "")
    .slice(0, SUGGESTIONS).map(function(x) { return x.row })
  suggestions.forEach(function(r) { taken[r.key] = true })
  var visible = rows.filter(function(r) { return !taken[r.key] && r.when !== "searching" })
  var commands = visible.filter(function(r) { return r.group !== "apps" })
  var apps = visible.filter(function(r) { return r.group === "apps" }).sort(byTitle)

  if (favorites.length) sections.push({ id: "favorites", title: "Favorites", rows: favorites })
  if (suggestions.length) sections.push({ id: "suggestions", title: "Suggestions", rows: suggestions })
  if (commands.length) sections.push({ id: "commands", title: "Commands", rows: commands })
  if (apps.length) sections.push({ id: "apps", title: "Applications", rows: apps })
  return sections
}

// A submenu view: its children in order, or, while searching, every row
// whose key starts with `prefix`, ranked.
function submenuSections(rows, query, state, now, deps) {
  var q = String(query || "").trim()
  var list = decorate(rows, state, now, deps)
  if (!q) {
    var shown = list.filter(function(r) { return r.when !== "searching" })
    return shown.length ? [{ id: "menu", title: "", rows: shown }] : []
  }
  var ranked = deps.Rank.rank(list, q).map(function(x) { return x.row })
  return ranked.length ? [{ id: "results", title: "Results", rows: ranked }] : []
}

// Flatten sections for the list view: header rows interleaved with items.
function flatten(sections) {
  var out = []
  var n = 0
  for (var i = 0; i < sections.length; i++) {
    var s = sections[i]
    if (s.title) out.push({ header: true, title: s.title, section: s.id })
    for (var j = 0; j < s.rows.length; j++) {
      out.push({ header: false, row: s.rows[j], section: s.id, ordinal: n++ })
    }
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = { rootSections: rootSections, submenuSections: submenuSections, flatten: flatten }
}
