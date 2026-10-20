// Pure helpers for the dictionary plugin (tested in tests/dictionary.test.js).

// { mode: "define" | "spell", word } or null.
function parse(query) {
  var m = /^(define|def|spell)\s+(.*\S)\s*$/i.exec(String(query || ""))
  if (!m) return null
  return { mode: m[1].toLowerCase() === "spell" ? "spell" : "define", word: m[2] }
}

var ENTITIES = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " }

function stripHtml(html) {
  return String(html || "")
    .replace(/<[^>]+>/g, "")
    .replace(/&(#x?[0-9a-f]+|[a-z]+);/gi, function(all, e) {
      if (e[0] === "#") return String.fromCharCode(e[1] === "x" || e[1] === "X" ? parseInt(e.slice(2), 16) : parseInt(e.slice(1), 10))
      return ENTITIES[e.toLowerCase()] !== undefined ? ENTITIES[e.toLowerCase()] : all
    })
    .replace(/\s+/g, " ")
    .trim()
}

// Wiktionary REST definitions → [{ definition, partOfSpeech, language }],
// languages in `prefer` order first.
function definitions(json, prefer, limit) {
  var data = typeof json === "string" ? JSON.parse(json) : json
  var langs = Object.keys(data || {})
  var order = (prefer || []).filter(function(l) { return langs.indexOf(l) >= 0 })
    .concat(langs.filter(function(l) { return (prefer || []).indexOf(l) < 0 }))
  var out = []
  for (var i = 0; i < order.length; i++) {
    var entries = data[order[i]] || []
    for (var j = 0; j < entries.length; j++) {
      var defs = entries[j].definitions || []
      for (var k = 0; k < defs.length; k++) {
        var text = stripHtml(defs[k].definition)
        if (!text) continue
        out.push({ definition: text, partOfSpeech: entries[j].partOfSpeech || "", language: entries[j].language || order[i] })
        if (out.length >= (limit || 6)) return out
      }
    }
  }
  return out
}

// `hunspell -a` output for one word → { correct, suggestions }.
function spellResult(text) {
  var lines = String(text || "").split("\n").slice(1).filter(function(l) { return l.trim() })
  if (!lines.length) return { correct: false, suggestions: [] }
  var l = lines[0]
  if (l[0] === "*" || l[0] === "+" || l[0] === "-") return { correct: true, suggestions: [] }
  var colon = l.indexOf(":")
  return { correct: false, suggestions: colon < 0 ? [] : l.slice(colon + 1).split(",").map(function(s) { return s.trim() }).filter(function(s) { return s }) }
}

// Dictionary names from `hunspell -D` (stderr).
function dictionaries(text) {
  var out = []
  var lines = String(text || "").split("\n")
  var on = false
  for (var i = 0; i < lines.length; i++) {
    if (/^AVAILABLE DICTIONARIES/.test(lines[i])) { on = true; continue }
    if (/^LOADED DICTIONARY/.test(lines[i])) break
    if (on && /^\s*\//.test(lines[i])) {
      var name = lines[i].trim().split("/").pop()
      if (out.indexOf(name) < 0) out.push(name)
    }
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = { parse: parse, stripHtml: stripHtml, definitions: definitions, spellResult: spellResult, dictionaries: dictionaries }
}
