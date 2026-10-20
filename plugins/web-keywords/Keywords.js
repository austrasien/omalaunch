// Web keywords: "<keyword> terms" opens a site search (tests/keywords.test.js).
// ~/.config/omalaunch/web.json adds to or replaces these; a keyword set to
// null removes a default.

var DEFAULTS = {
  gh:     { title: "GitHub", url: "https://github.com/search?q={query}&type=repositories", icon: "\uf09b" },
  yt:     { title: "YouTube", url: "https://www.youtube.com/results?search_query={query}", icon: "\uf16a" },
  ytm:    { title: "YouTube Music", url: "https://music.youtube.com/search?q={query}", icon: "\uf001" },
  maps:   { title: "Google Maps", url: "https://www.google.com/maps/search/{query}", icon: "\uf279" },
  wiki:   { title: "Wikipedia (fr)", url: "https://fr.wikipedia.org/w/index.php?search={query}", icon: "\uf266" },
  wen:    { title: "Wikipedia (en)", url: "https://en.wikipedia.org/w/index.php?search={query}", icon: "\uf266" },
  grok:   { title: "Grokipedia", url: "https://grokipedia.com/search?q={query}", icon: "\uf02d" },
  deepl:  { title: "DeepL", url: "https://www.deepl.com/translator#auto/en/{query}", icon: "\uf1ab" },
  li:     { title: "LinkedIn", url: "https://www.linkedin.com/search/results/all/?keywords={query}", icon: "\uf0e1" },
  pcloud: { title: "pCloud", url: "https://my.pcloud.com/#/filemanager?q=name%3A{query}&folderid=0&filter=all", icon: "\uf0c2" },
  amz:    { title: "Amazon.fr", url: "https://www.amazon.fr/s?k={query}", icon: "\uf270" },
  amzde:  { title: "Amazon.de", url: "https://www.amazon.de/s?k={query}", icon: "\uf270" },
  reddit: { title: "Reddit", url: "https://www.reddit.com/search/?q={query}", icon: "\uf281" }
}

// Defaults merged with the user's object: [{ keyword, title, url, icon }].
function merge(user) {
  var all = {}
  var k
  for (k in DEFAULTS) all[k] = DEFAULTS[k]
  if (user && typeof user === "object" && !Array.isArray(user)) {
    for (k in user) {
      if (user[k] === null) { delete all[k]; continue }
      var u = user[k]
      if (typeof u === "string") u = { url: u }
      if (!u || typeof u.url !== "string" || u.url.indexOf("{query}") < 0) continue
      all[k] = { title: String(u.title || (DEFAULTS[k] && DEFAULTS[k].title) || k), url: u.url, icon: String(u.icon || (DEFAULTS[k] && DEFAULTS[k].icon) || "\uf0ac") }
    }
  }
  var out = []
  for (k in all) {
    var kw = String(k).trim().toLowerCase()
    if (/^\S+$/.test(kw)) out.push({ keyword: kw, title: all[k].title, url: all[k].url, icon: all[k].icon })
  }
  return out
}

// { site, terms } for "<keyword> terms", else null.
function match(query, sites) {
  var q = String(query || "").replace(/^\s+/, "")
  var sp = q.indexOf(" ")
  if (sp < 1) return null
  var kw = q.slice(0, sp).toLowerCase()
  var terms = q.slice(sp + 1).trim()
  for (var i = 0; i < sites.length; i++) if (sites[i].keyword === kw) return { site: sites[i], terms: terms }
  return null
}

function urlFor(site, terms) {
  return site.url.split("{query}").join(encodeURIComponent(terms))
}

if (typeof module !== "undefined") module.exports = { DEFAULTS: DEFAULTS, merge: merge, match: match, urlFor: urlFor }
