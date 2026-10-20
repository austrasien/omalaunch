// ~/.ssh/config hosts (tests/ssh.test.js).

// → [{ name, hostname, user, port }] for every concrete Host alias
// (patterns with * ? ! are skipped).
function hosts(text) {
  var out = []
  var current = []
  String(text || "").split("\n").forEach(function(raw) {
    var line = raw.replace(/#.*$/, "").trim()
    var m = /^([^\s=]+)\s*=?\s*(.*)$/.exec(line)
    if (!m) return
    var key = m[1].toLowerCase(), value = m[2].trim()
    if (key === "host") {
      current = value.split(/\s+/).filter(function(h) { return h && !/[*?!]/.test(h) }).map(function(h) {
        var e = { name: h, hostname: "", user: "", port: "" }
        out.push(e)
        return e
      })
    } else if (key === "match") {
      current = []
    } else if (current.length && (key === "hostname" || key === "user" || key === "port")) {
      current.forEach(function(e) { if (!e[key]) e[key] = value })
    }
  })
  var seen = {}
  return out.filter(function(e) { if (seen[e.name]) return false; seen[e.name] = true; return true })
}

// "ssh forge" → ["forge"], "ssh" → [], else null.
function termsFrom(query) {
  var m = /^ssh(?:\s+(.*?))?\s*$/i.exec(String(query || ""))
  return m ? (m[1] || "").toLowerCase().split(/\s+/).filter(function(w) { return w }) : null
}

if (typeof module !== "undefined") module.exports = { hosts: hosts, termsFrom: termsFrom }
