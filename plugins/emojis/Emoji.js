// Emoji search in French and English (tests/emojis.test.js). Names come
// from Unicode CLDR (tools/build-emojis.js).

// Lower case, no accents, œ → oe: "Cœur" and "coeur" match.
function fold(s) {
  return String(s || "").toLowerCase().replace(/œ/g, "oe").replace(/æ/g, "ae")
    .normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[’']/g, " ")
}

// The search text after ":" (":feu", ": coeur rouge"), or null.
function termsFrom(query) {
  var m = /^:\s*(.*?)\s*$/.exec(String(query || ""))
  return m ? fold(m[1]).split(/\s+/).filter(function(w) { return w }) : null
}

function prepare(list) {
  return list.map(function(x) {
    return { e: x.e, en: x.en, fr: x.fr, g: x.g, names: fold(x.fr + " " + x.en), keys: fold(x.k), frName: fold(x.fr), enName: fold(x.en) }
  })
}

// Every word must start a word of the names or keywords. An exact name
// wins, then names beat keywords and whole words beat prefixes; shorter
// names, then Unicode order, break ties.
function search(items, words, limit) {
  var scored = []
  for (var i = 0; i < items.length; i++) {
    var it = items[i]
    var score = 0
    for (var w = 0; w < words.length; w++) {
      var re = new RegExp("(^|[^a-z0-9])" + words[w].replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "([^a-z0-9]|$)?")
      var mn = re.exec(it.names)
      var mk = mn ? null : re.exec(it.keys)
      if (!mn && !mk) { score = -1; break }
      score += (mn ? 10 : 4) + ((mn || mk)[2] !== undefined ? 3 : 0)
    }
    if (score < 0) continue
    var phrase = words.join(" ")
    if (it.frName === phrase || it.enName === phrase) score += 50
    scored.push({ i: i, s: score, len: Math.min(it.frName.length || 999, it.enName.length) })
  }
  scored.sort(function(a, b) { return b.s - a.s || a.len - b.len || a.i - b.i })
  return scored.slice(0, limit || 40).map(function(x) { return items[x.i] })
}

if (typeof module !== "undefined") module.exports = { fold: fold, termsFrom: termsFrom, prepare: prepare, search: search }
