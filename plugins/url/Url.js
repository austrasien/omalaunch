// Is the query a URL? (tests/url.test.js). Explicit schemes, www., IPs and
// localhost always count; a bare "name.tld" only with a path or a common
// TLD, so file names such as notes.md or Main.qml stay searches.

var SCHEME = /^(https?|ftp|file):\/\/\S+$/i
var HOST = /^((?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+([a-z]{2,63})|localhost|\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-f:]+\])(:\d{1,5})?([\/?#]\S*)?$/i
var TLDS = ("com org net io dev app ai co fr de uk eu be ch es it nl lu ca us me tv info xyz gg sh so to fm ly cc gov edu int mil " +
            "biz pro tech site online page blog news cloud shop store wiki zone design studio art run team chat link live " +
            "jp cn kr in ru br au nz se no dk fi pl pt at cz ie gr ro hu il tw hk sg").split(" ")

function parse(text) {
  var t = String(text || "").trim()
  if (!t || /\s/.test(t)) return null
  if (SCHEME.test(t)) return t
  if (/^\w+:\/\//.test(t) || t.indexOf("@") >= 0) return null
  var m = HOST.exec(t)
  if (!m) return null
  var bare = m[2] && !/^www\./i.test(t) && !m[3] && !m[4]
  if (bare && TLDS.indexOf(m[2].toLowerCase()) < 0) return null
  var local = !m[2] || /^(localhost|127\.|10\.|192\.168\.|\[)/i.test(t)
  return (local ? "http://" : "https://") + t
}

if (typeof module !== "undefined") module.exports = { parse: parse }
