// Ranking for catalog rows (docs/SPEC.md §5).
//
// A row: { key, title, subtitle?, keywords?: [string], alias?, favorite?,
//          frecency?: number, terms?: [string], boost?: number }
// rank(rows, query) returns [{ row, score }] best first; rows that do not
// match are dropped. With an empty query every row is kept, ordered by
// frecency.

var FAVORITE_BONUS = 0.5
var FRECENCY_WEIGHT = 40

// Lower-case, strip accents, collapse whitespace.
function normalize(text) {
  var s = String(text || "").toLowerCase()
  if (s.normalize) s = s.normalize("NFD").replace(/[̀-ͯ]/g, "")
  return s.replace(/\s+/g, " ").trim()
}

// Words of a title, splitting camelCase, digits and punctuation.
function words(text) {
  var spaced = String(text || "")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/([A-Za-z])([0-9])/g, "$1 $2")
  return normalize(spaced).split(/[^a-z0-9]+/).filter(function(w) { return w.length > 0 })
}

function initials(text) {
  return words(text).map(function(w) { return w.charAt(0) }).join("")
}

// Fuzzy subsequence score in [0, 1], or -1 when q is not a subsequence of
// text or the match looks accidental. Greedy left-to-right, but each letter
// prefers a word start or the position right after the previous match.
function fuzzy(q, text) {
  if (!q) return 0
  var t = text
  var starts = {}
  for (var i = 0; i < t.length; i++) {
    if (i === 0 || !/[a-z0-9]/.test(t.charAt(i - 1))) starts[i] = true
  }
  var pos = -1
  var good = 0
  var span = 0
  for (var k = 0; k < q.length; k++) {
    var c = q.charAt(k)
    var next = t.indexOf(c, pos + 1)
    if (next < 0) return -1
    // Look ahead for a word start with this letter before settling for a
    // mid-word hit, unless the hit is contiguous with the previous one.
    if (next !== pos + 1 && !starts[next]) {
      for (var j = next + 1; j < t.length; j++) {
        if (t.charAt(j) === c && starts[j]) { next = j; break }
      }
    }
    if (next === pos + 1 || starts[next]) good++
    if (k > 0) span += next - pos - 1
    pos = next
  }
  var quality = good / q.length
  if (q.length > 3 && quality < 0.5) return -1
  var compact = 1 / (1 + span / Math.max(1, q.length))
  return 0.6 * quality + 0.4 * compact
}

// Best match score of q against one text, on the 0–800 ladder. Fuzzy
// matching is for titles only; on keywords it mostly finds noise.
function textScore(q, text, noFuzzy) {
  var t = normalize(text)
  if (!t) return 0
  if (t === q) return 800
  if (t.indexOf(q) === 0) return 700
  var ws = words(text)
  for (var i = 0; i < ws.length; i++) {
    if (ws[i].indexOf(q) === 0) return 600
  }
  if (q.length >= 2 && initials(text) === q.replace(/ /g, "")) return 550
  if (t.indexOf(q) >= 0) return 450
  if (noFuzzy) return 0
  var f = fuzzy(q.replace(/ /g, ""), t)
  return f < 0 ? 0 : Math.round(100 + 200 * f)
}

function matchScore(row, q) {
  var best = 0
  var alias = normalize(row.alias)
  if (alias) {
    if (alias === q) best = 1000
    else if (alias.indexOf(q) === 0) best = 900
  }
  best = Math.max(best, textScore(q, row.title))
  var secondary = 0
  if (row.subtitle) secondary = Math.max(secondary, textScore(q, row.subtitle, true))
  var kws = row.keywords || []
  for (var i = 0; i < kws.length; i++) secondary = Math.max(secondary, textScore(q, kws[i], true))
  best = Math.max(best, Math.round(secondary * 0.6))
  return best
}

function termBonus(row, q) {
  var terms = row.terms || []
  var bonus = 0
  for (var i = 0; i < terms.length; i++) {
    var term = normalize(terms[i])
    if (term === q) return 350
    if (term.indexOf(q) === 0) bonus = 200
  }
  return bonus
}

function frecencyBonus(row) {
  var f = Number(row.frecency) || 0
  return f > 0 ? FRECENCY_WEIGHT * Math.log(1 + f) / Math.LN2 : 0
}

function compare(a, b) {
  if (b.score !== a.score) return b.score - a.score
  var fa = a.row.favorite ? 1 : 0
  var fb = b.row.favorite ? 1 : 0
  if (fa !== fb) return fb - fa
  var la = String(a.row.title || "").length
  var lb = String(b.row.title || "").length
  if (la !== lb) return la - lb
  var ta = normalize(a.row.title)
  var tb = normalize(b.row.title)
  return ta < tb ? -1 : (ta > tb ? 1 : 0)
}

function rank(rows, query) {
  var q = normalize(query)
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    var score
    if (!q) {
      score = frecencyBonus(row) + (row.favorite ? FAVORITE_BONUS : 0)
    } else {
      var m = matchScore(row, q)
      var t = termBonus(row, q)
      if (m === 0 && t === 0) continue
      // `boost` lets a provider rank its kind of row above or below others
      // at equal match quality (apps above deep menu entries).
      score = m + t + frecencyBonus(row) + (Number(row.boost) || 0)
    }
    out.push({ row: row, score: score })
  }
  out.sort(compare)
  return out
}

if (typeof module !== "undefined") {
  module.exports = { normalize: normalize, words: words, initials: initials, fuzzy: fuzzy,
    textScore: textScore, matchScore: matchScore, rank: rank }
}
