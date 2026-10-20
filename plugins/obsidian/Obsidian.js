// Obsidian notes (tests/obsidian.test.js): "o term" searches the vaults,
// "o+ text" adds a line to today's daily note, "on Title" creates a note.

// { mode: "search" | "journal" | "new", text } or null.
function parse(query) {
  var q = String(query || "")
  var m
  if ((m = /^o\+\s*(.*?)\s*$/.exec(q))) return { mode: "journal", text: m[1] }
  if ((m = /^on\s+(.*?)\s*$/i.exec(q))) return { mode: "new", text: m[1] }
  if ((m = /^o(?:\s+(.*?))?\s*$/i.exec(q))) return { mode: "search", text: m[1] || "" }
  return null
}

// ~/.config/obsidian/obsidian.json → [{ path, name, open }], the open vault first.
function vaults(json) {
  var data = typeof json === "string" ? JSON.parse(json) : json
  var out = []
  var v = (data && data.vaults) || {}
  for (var id in v) {
    if (!v[id] || !v[id].path) continue
    var p = String(v[id].path).replace(/\/+$/, "")
    out.push({ path: p, name: p.slice(p.lastIndexOf("/") + 1), open: !!v[id].open })
  }
  out.sort(function(a, b) { return (b.open ? 1 : 0) - (a.open ? 1 : 0) })
  return out
}

function pad(n) { return (n < 10 ? "0" : "") + n }

// The moment.js tokens Obsidian date formats use most.
var EN_DAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
var EN_MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
function formatMoment(d, fmt) {
  return String(fmt || "YYYY-MM-DD").replace(/\[([^\]]*)\]|YYYY|YY|MMMM|MMM|MM|M|DDDD|DD|D|dddd|ddd|HH|H|mm|ss/g, function(t, lit) {
    if (lit !== undefined) return lit
    switch (t) {
    case "YYYY": return String(d.getFullYear())
    case "YY": return String(d.getFullYear()).slice(-2)
    case "MMMM": return EN_MONTHS[d.getMonth()]
    case "MMM": return EN_MONTHS[d.getMonth()].slice(0, 3)
    case "MM": return pad(d.getMonth() + 1)
    case "M": return String(d.getMonth() + 1)
    case "DD": return pad(d.getDate())
    case "D": return String(d.getDate())
    case "dddd": return EN_DAYS[d.getDay()]
    case "ddd": return EN_DAYS[d.getDay()].slice(0, 3)
    case "HH": return pad(d.getHours())
    case "H": return String(d.getHours())
    case "mm": return pad(d.getMinutes())
    case "ss": return pad(d.getSeconds())
    }
    return t
  })
}

// Obsidian's core template variables: {{title}}, {{date}}, {{time}},
// {{date:FORMAT}}, {{time:FORMAT}}.
function fillTemplate(text, title, now) {
  return String(text || "").replace(/\{\{\s*(title|date|time)\s*(?::([^}]*))?\}\}/g, function(all, name, fmt) {
    if (name === "title") return title
    return formatMoment(now, fmt || (name === "date" ? "YYYY-MM-DD" : "HH:mm"))
  })
}

// Insert `line` at the end of the section under `heading` (before the next
// heading of the same or a higher level); append at the end when the
// heading is missing.
function insertLine(content, heading, line) {
  var lines = String(content || "").split("\n")
  var level = heading ? (/^(#+)\s/.exec(heading) || [, ""])[1].length : 0
  var at = -1
  for (var i = 0; heading && i < lines.length; i++) if (lines[i].trim() === heading.trim()) { at = i; break }
  if (at < 0) {
    var body = String(content || "").replace(/\s*$/, "")
    return (body ? body + "\n" : "") + line + "\n"
  }
  var end = lines.length
  for (var j = at + 1; j < lines.length; j++) {
    var h = /^(#+)\s/.exec(lines[j])
    if (h && h[1].length <= level) { end = j; break }
  }
  // Back up over blank lines so the new line joins the section's content.
  var pos = end
  while (pos > at + 1 && lines[pos - 1].trim() === "") pos--
  lines.splice(pos, 0, line)
  return lines.join("\n")
}

// A file name for a new note title.
function fileName(title) {
  return String(title || "").replace(/[\\\/:*?"<>|#^\[\]]/g, " ").replace(/\s+/g, " ").trim()
}

if (typeof module !== "undefined") {
  module.exports = { parse: parse, vaults: vaults, formatMoment: formatMoment, fillTemplate: fillTemplate, insertLine: insertLine, fileName: fileName }
}
