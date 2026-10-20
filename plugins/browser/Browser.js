// Chromium-family bookmarks and history (tests/browser.test.js).

// Bookmarks file JSON → [{ title, url, folder }].
function bookmarks(json) {
  var data = typeof json === "string" ? JSON.parse(json) : json
  var out = []
  function walk(node, path) {
    if (!node) return
    if (node.type === "url" && /^https?:/.test(node.url || "")) out.push({ title: node.name || node.url, url: node.url, folder: path.join(" › ") })
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++) walk(kids[i], node.type === "folder" && node.name ? path.concat([node.name]) : path)
  }
  var roots = (data && data.roots) || {}
  for (var r in roots) if (roots[r] && typeof roots[r] === "object") walk(roots[r], [])
  return out
}

// "b term" → ["term"], else null.
function termsFrom(query) {
  var m = /^b\s+(.*\S)\s*$/i.exec(String(query || ""))
  return m ? m[1].toLowerCase().split(/\s+/) : null
}

// An SQL query over the history `urls` table: every word in the title or
// url, most visited first.
function historySql(words, limit) {
  var cond = words.map(function(w) {
    var esc = w.replace(/'/g, "''").replace(/[%_\\]/g, "\\$&")
    return "(title LIKE '%" + esc + "%' ESCAPE '\\' OR url LIKE '%" + esc + "%' ESCAPE '\\')"
  }).join(" AND ")
  return "SELECT url, replace(replace(title, char(9), ' '), char(10), ' '), visit_count, last_visit_time FROM urls WHERE hidden = 0 AND "
    + cond + " ORDER BY visit_count DESC, last_visit_time DESC LIMIT " + (limit || 20)
}

// Chromium time (µs since 1601) → JS Date.
function chromeDate(t) { return new Date(Number(t) / 1000 - 11644473600000) }

function host(url) {
  var m = /^https?:\/\/(?:www\.)?([^\/?#]+)/.exec(url)
  return m ? m[1] : url
}

if (typeof module !== "undefined") {
  module.exports = { bookmarks: bookmarks, termsFrom: termsFrom, historySql: historySql, chromeDate: chromeDate, host: host }
}
