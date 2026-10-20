// Omarchy menu JSONC → flat entries (docs/SPEC.md §3, `omarchy` provider).
//
// Format (documented at the top of omarchy-menu.jsonc): an object whose keys
// are dotted ids; the parent of "a.b.c" is "a.b". `action` makes a runnable
// row, `target` links to another submenu, anything else is a submenu.
// Later files override earlier ones field by field.

// Remove // and /* */ comments and trailing commas, leaving strings intact.
function stripJsonc(raw) {
  var s = String(raw || "")
  var out = ""
  var i = 0
  var n = s.length
  while (i < n) {
    var c = s.charAt(i)
    if (c === '"') {
      var j = i + 1
      while (j < n && s.charAt(j) !== '"') j += s.charAt(j) === "\\" ? 2 : 1
      out += s.slice(i, j + 1)
      i = j + 1
    } else if (c === "/" && s.charAt(i + 1) === "/") {
      while (i < n && s.charAt(i) !== "\n") i++
    } else if (c === "/" && s.charAt(i + 1) === "*") {
      var end = s.indexOf("*/", i + 2)
      i = end < 0 ? n : end + 2
    } else {
      out += c
      i++
    }
  }
  return out.replace(/,(\s*[}\]])/g, "$1")
}

// Parse one file. Returns { entries: { id: rawObject }, error }.
function parseFile(raw) {
  var text = stripJsonc(raw)
  if (!text.trim()) return { entries: {}, error: "" }
  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return { entries: {}, error: String(e && e.message || e) }
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return { entries: {}, error: "not an object" }
  if (parsed.items && typeof parsed.items === "object" && !Array.isArray(parsed.items)) parsed = parsed.items
  var entries = {}
  for (var id in parsed) {
    if (parsed[id] && typeof parsed[id] === "object" && !Array.isArray(parsed[id])) entries[id] = parsed[id]
  }
  return { entries: entries, error: "" }
}

function str(v) { return typeof v === "string" ? v : "" }

function parentOf(id) {
  var dot = id.lastIndexOf(".")
  return dot < 0 ? "" : id.slice(0, dot)
}

// Merge parsed files (lowest priority first) into normalized entries:
// { id, parent, kind: action|link|menu, label, title, icon, iconFont,
//   description, action, target, provider, aliases, when, checked, disabled,
//   order }
function merge(files) {
  var raw = {}
  var order = []
  for (var f = 0; f < files.length; f++) {
    var entries = files[f] || {}
    for (var id in entries) {
      if (!raw[id]) { raw[id] = {}; order.push(id) }
      for (var k in entries[id]) raw[id][k] = entries[id][k]
    }
  }
  var out = {}
  for (var i = 0; i < order.length; i++) {
    var key = order[i]
    var r = raw[key]
    var aliases = Array.isArray(r.aliases) ? r.aliases.filter(function(a) { return typeof a === "string" && a })
      : (str(r.aliases) ? [r.aliases] : [])
    out[key] = {
      id: key,
      parent: str(r.parent) || parentOf(key),
      kind: str(r.action) ? "action" : (str(r.target) ? "link" : "menu"),
      label: str(r.label) || key,
      title: str(r.title),
      icon: str(r.icon),
      iconFont: str(r.iconFont),
      description: str(r.description),
      action: str(r.action),
      target: str(r.target),
      provider: str(r.provider),
      aliases: aliases,
      when: str(r.when),
      checked: str(r.checked),
      disabled: str(r.disabled),
      order: i
    }
  }
  return out
}

// Labels from the root down to (not including) `id`, e.g. ["Setup", "Default"].
function trail(entries, id) {
  var labels = []
  var seen = {}
  var p = entries[id] ? entries[id].parent : ""
  while (p && entries[p] && !seen[p]) {
    seen[p] = true
    labels.unshift(entries[p].label)
    p = entries[p].parent
  }
  return labels
}

// Ids whose `when` failed, plus everything under them.
function hiddenIds(entries, whenResults) {
  var hidden = {}
  function isHidden(id, depth) {
    if (depth > 32 || !id || !entries[id]) return false
    if (hidden[id] !== undefined) return hidden[id]
    var e = entries[id]
    var h = (e.when && whenResults[id] === false) || isHidden(e.parent, depth + 1)
    hidden[id] = h
    return h
  }
  for (var id in entries) isHidden(id, 0)
  var out = {}
  for (var k in hidden) if (hidden[k]) out[k] = true
  return out
}

// Children of a submenu in file order ("" = root).
function children(entries, parentId) {
  var list = []
  for (var id in entries) if (entries[id].parent === parentId) list.push(entries[id])
  list.sort(function(a, b) { return a.order - b.order })
  return list
}

// One bash script that evaluates every guard and prints "<index>\t<0|1>"
// per guard. Each condition runs in a subshell with a timeout so one slow
// or broken condition cannot stall the rest.
function guardScript(guards) {
  var lines = []
  for (var i = 0; i < guards.length; i++) {
    var cond = guards[i].replace(/'/g, "'\\''")
    lines.push("( timeout 2 bash -c '" + cond + "' >/dev/null 2>&1 ) && echo '" + i + "\t1' || echo '" + i + "\t0' &")
  }
  lines.push("wait")
  return lines.join("\n")
}

function parseGuardOutput(text, count) {
  var results = new Array(count)
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    var idx = parseInt(parts[0], 10)
    if (!isNaN(idx) && idx >= 0 && idx < count) results[idx] = parts[1] === "1"
  }
  return results
}

if (typeof module !== "undefined") {
  module.exports = { stripJsonc: stripJsonc, parseFile: parseFile, merge: merge, trail: trail,
    hiddenIds: hiddenIds, children: children, guardScript: guardScript, parseGuardOutput: parseGuardOutput }
}
