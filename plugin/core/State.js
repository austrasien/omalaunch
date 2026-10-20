// Persistent user state (docs/SPEC.md §8). Pure functions over a plain object
// so they can be tested outside QML; the Store service persists the object.

var VERSION = 1
var HALF_LIFE_MS = 7 * 24 * 3600 * 1000
var TERM_TTL_MS = 30 * 24 * 3600 * 1000
var TERMS_PER_ITEM = 50
var HISTORY_LIMIT = 50

function empty() {
  return {
    version: VERSION,
    frecency: {},   // key -> { score, at }
    terms: {},      // key -> [{ q, at }]
    aliases: {},    // key -> alias
    favorites: [],  // keys, in display order
    disabled: {},   // key -> true
    history: [],    // recent queries, newest first
    zoom: 1
  }
}

// Fill in anything missing from an older or hand-edited file.
function upgrade(raw) {
  var s = empty()
  if (!raw || typeof raw !== "object") return s
  for (var k in s) {
    if (raw[k] === undefined) continue
    if (Array.isArray(s[k]) !== Array.isArray(raw[k])) continue
    if (typeof s[k] !== typeof raw[k]) continue
    s[k] = raw[k]
  }
  s.version = VERSION
  return s
}

function decayed(entry, now) {
  if (!entry) return 0
  var age = Math.max(0, now - (Number(entry.at) || 0))
  return (Number(entry.score) || 0) * Math.pow(0.5, age / HALF_LIFE_MS)
}

function frecency(state, key, now) {
  return decayed(state.frecency[key], now)
}

// Record a launch of `key`, optionally after typing `query`.
function recordUse(state, key, query, now) {
  state.frecency[key] = { score: decayed(state.frecency[key], now) + 1, at: now }
  var q = String(query || "").trim().toLowerCase()
  if (q) {
    var list = (state.terms[key] || []).filter(function(t) { return t.q !== q && now - t.at < TERM_TTL_MS })
    list.unshift({ q: q, at: now })
    state.terms[key] = list.slice(0, TERMS_PER_ITEM)
  }
}

function terms(state, key, now) {
  return (state.terms[key] || []).filter(function(t) { return now - t.at < TERM_TTL_MS }).map(function(t) { return t.q })
}

function resetRanking(state, key) {
  delete state.frecency[key]
  delete state.terms[key]
}

function pushHistory(state, query) {
  var q = String(query || "").trim()
  if (!q) return
  state.history = [q].concat(state.history.filter(function(h) { return h !== q })).slice(0, HISTORY_LIMIT)
}

function isFavorite(state, key) {
  return state.favorites.indexOf(key) >= 0
}

function toggleFavorite(state, key) {
  var i = state.favorites.indexOf(key)
  if (i >= 0) state.favorites.splice(i, 1)
  else state.favorites.push(key)
  return i < 0
}

// Move a favourite up (delta -1) or down (+1). Returns true if it moved.
function moveFavorite(state, key, delta) {
  var i = state.favorites.indexOf(key)
  var j = i + delta
  if (i < 0 || j < 0 || j >= state.favorites.length) return false
  state.favorites.splice(i, 1)
  state.favorites.splice(j, 0, key)
  return true
}

function setAlias(state, key, alias) {
  var a = String(alias || "").trim()
  if (a) state.aliases[key] = a
  else delete state.aliases[key]
}

function setDisabled(state, key, disabled) {
  if (disabled) state.disabled[key] = true
  else delete state.disabled[key]
  if (disabled) {
    var i = state.favorites.indexOf(key)
    if (i >= 0) state.favorites.splice(i, 1)
  }
}

if (typeof module !== "undefined") {
  module.exports = { empty: empty, upgrade: upgrade, frecency: frecency, recordUse: recordUse,
    terms: terms, resetRanking: resetRanking, pushHistory: pushHistory, isFavorite: isFavorite,
    toggleFavorite: toggleFavorite, moveFavorite: moveFavorite, setAlias: setAlias,
    setDisabled: setDisabled, HALF_LIFE_MS: HALF_LIFE_MS, TERM_TTL_MS: TERM_TTL_MS }
}
