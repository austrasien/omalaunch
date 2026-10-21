// Build the list the launcher shows (docs/SPEC.md §4).
//
// Inputs:
//   catalog  rows from catalog providers:
//            { key, title, ..., group: "commands"|"apps", visibility: "always"|"search-only"|"idle-only" }
//   dynamic  query-provider sections: { id, title, placement: "inline"|"bottom", order, rows }
// Output: [{ id, title, rows }], empty sections left out.

var SUGGESTION_COUNT = 6
var RESULT_LIMIT = 80
var MIN_FRECENCY = 0.05

// Copy each row with the user's state attached; drop disabled rows.
function withState(rows, state, now, deps) {
  var out = []
  rows.forEach(function(r) {
    if (state.disabled[r.key]) return
    var d = Object.assign({}, r)
    d.alias = state.aliases[r.key] || ""
    d.favorite = state.favorites.indexOf(r.key) >= 0
    d.frecency = deps.State.frecency(state, r.key, now)
    d.terms = deps.State.terms(state, r.key, now)
    out.push(d)
  })
  return out
}

function titleOrder(a, b) {
  return String(a.title || "").localeCompare(String(b.title || ""), undefined, { sensitivity: "base" })
}

// Idle (empty query) view. Every row lands in exactly one bucket, decided
// in priority order: favourite, frequently used, then its group.
function idleView(rows, state, deps) {
  var favOrder = {}
  state.favorites.forEach(function(k, i) { favOrder[k] = i })
  var frequent = {}
  deps.Rank.rank(rows.filter(function(r) { return !(r.key in favOrder) && r.frecency > MIN_FRECENCY }), "")
    .slice(0, SUGGESTION_COUNT)
    .forEach(function(x, i) { frequent[x.row.key] = i })

  var buckets = { favorites: [], suggestions: [], commands: [], apps: [] }
  rows.forEach(function(r) {
    if (r.key in favOrder) buckets.favorites.push(r)
    else if (r.key in frequent) buckets.suggestions.push(r)
    else if (r.visibility === "search-only") return
    else buckets[r.group === "apps" ? "apps" : "commands"].push(r)
  })
  buckets.favorites.sort(function(a, b) { return favOrder[a.key] - favOrder[b.key] })
  buckets.suggestions.sort(function(a, b) { return frequent[a.key] - frequent[b.key] })
  buckets.apps.sort(titleOrder)

  var layout = [
    ["favorites", "Favorites"],
    ["suggestions", "Suggestions"],
    ["commands", "Commands"],
    ["apps", "Applications"]
  ]
  return layout.map(function(l) { return { id: l[0], title: l[1], rows: buckets[l[0]] } })
}

// Search view: inline plugin sections, then ranked results, then the rest.
function searchView(rows, dynamic, query, deps) {
  // Sections of one placement in order; neighbours with the same title
  // (several providers adding to "Search the web") become one section.
  var byPlacement = function(p) {
    var out = []
    dynamic.filter(function(s) { return (s.placement === "inline") === (p === "inline") })
      .sort(function(a, b) { return (a.order || 0) - (b.order || 0) })
      .forEach(function(s) {
        var last = out[out.length - 1]
        if (last && s.title && last.title === s.title) last.rows = last.rows.concat(s.rows || [])
        else out.push({ id: s.id, title: s.title, rows: (s.rows || []).slice() })
      })
    return out
  }
  var candidates = rows.filter(function(r) { return r.visibility !== "idle-only" })
  var results = deps.Rank.rank(candidates, query).slice(0, RESULT_LIMIT).map(function(x) { return x.row })
  return byPlacement("inline")
    .concat([{ id: "results", title: "Results", rows: results }])
    .concat(byPlacement("bottom"))
}

function nonEmpty(sections) {
  return sections.filter(function(s) { return s.rows.length > 0 })
}

function rootSections(catalog, dynamic, query, state, now, deps) {
  var rows = withState(catalog, state, now, deps)
  var q = String(query || "").trim()
  return nonEmpty(q ? searchView(rows, dynamic || [], q, deps) : idleView(rows, state, deps))
}

// A pushed sub-list. Idle: its visible rows in order. Searching: all rows,
// ranked.
function submenuSections(rows, query, state, now, deps) {
  var list = withState(rows, state, now, deps)
  var q = String(query || "").trim()
  if (q) return nonEmpty([{ id: "results", title: "Results", rows: deps.Rank.rank(list, q).map(function(x) { return x.row }) }])
  return nonEmpty([{ id: "menu", title: "", rows: list.filter(function(r) { return r.visibility !== "search-only" }) }])
}

// Flatten for the list view: header entries interleaved with numbered items.
function flatten(sections) {
  var out = []
  var n = 0
  sections.forEach(function(s) {
    if (s.title) out.push({ header: true, title: s.title, section: s.id })
    s.rows.forEach(function(r) { out.push({ header: false, row: r, section: s.id, ordinal: n++ }) })
  })
  return out
}

if (typeof module !== "undefined") {
  module.exports = { rootSections: rootSections, submenuSections: submenuSections, flatten: flatten }
}
