// Snippet templates (tests/snippets.test.js): ";name" pastes the file
// ~/.config/omalaunch/snippets/name.txt with its {variables} filled in.

var FR = {
  months: ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"],
  days: ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
}

function pad(n, w) { n = String(n); while (n.length < (w || 2)) n = "0" + n; return n }

// ISO 8601 week number.
function isoWeek(d) {
  var t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
  var day = t.getUTCDay() || 7
  t.setUTCDate(t.getUTCDate() + 4 - day)
  var year = new Date(Date.UTC(t.getUTCFullYear(), 0, 1))
  return Math.ceil(((t - year) / 86400000 + 1) / 7)
}

// YYYY YY MMMM MMM MM M DD D dddd ddd HH H mm ss WW; [text] is literal.
function formatDate(d, fmt) {
  var tokens = {
    YYYY: function() { return String(d.getFullYear()) },
    YY: function() { return String(d.getFullYear()).slice(-2) },
    MMMM: function() { return FR.months[d.getMonth()] },
    MMM: function() { return FR.months[d.getMonth()].slice(0, 4).replace(/\.?$/, ".").replace("mai.", "mai").replace("juin.", "juin").replace("août.", "août") },
    MM: function() { return pad(d.getMonth() + 1) },
    M: function() { return String(d.getMonth() + 1) },
    dddd: function() { return FR.days[d.getDay()] },
    ddd: function() { return FR.days[d.getDay()].slice(0, 3) + "." },
    DD: function() { return pad(d.getDate()) },
    D: function() { return String(d.getDate()) },
    HH: function() { return pad(d.getHours()) },
    H: function() { return String(d.getHours()) },
    mm: function() { return pad(d.getMinutes()) },
    ss: function() { return pad(d.getSeconds()) },
    WW: function() { return pad(isoWeek(d)) }
  }
  return String(fmt).replace(/\[([^\]]*)\]|YYYY|YY|MMMM|MMM|MM|M|dddd|ddd|DD|D|HH|H|mm|ss|WW/g, function(t, lit) {
    return lit !== undefined ? lit : tokens[t]()
  })
}

function shift(now, amount, unit) {
  var d = new Date(now.getTime())
  if (unit === "d") d.setDate(d.getDate() + amount)
  else if (unit === "w") d.setDate(d.getDate() + 7 * amount)
  else if (unit === "m") d.setMonth(d.getMonth() + amount)
  else if (unit === "y") d.setFullYear(d.getFullYear() + amount)
  return d
}

var TOKEN = /\{([a-z]+)([+-]\d+[dwmy])?(?::([^{}]*))?\}/g
var EXTERNAL = { clipboard: 1, selection: 1, hostname: 1, user: 1, fullname: 1, email: 1, ip: 1, publicip: 1 }

// What a template needs before it can be expanded: external values,
// {input:…} labels in order, {shell:…} commands, {snippet:…} names.
function needs(text) {
  var out = { values: [], inputs: [], commands: [], snippets: [] }
  var m
  TOKEN.lastIndex = 0
  while ((m = TOKEN.exec(String(text || "")))) {
    var name = m[1], arg = m[3]
    if (EXTERNAL[name] && out.values.indexOf(name) < 0) out.values.push(name)
    else if (name === "input" && arg && out.inputs.indexOf(arg) < 0) out.inputs.push(arg)
    else if (name === "shell" && arg && out.commands.indexOf(arg) < 0) out.commands.push(arg)
    else if (name === "snippet" && arg && out.snippets.indexOf(arg) < 0) out.snippets.push(arg)
  }
  return out
}

// Inline {snippet:name} (3 levels deep at most).
function inline(text, library, depth) {
  if ((depth || 0) > 3) return text
  return String(text).replace(/\{snippet:([^{}]+)\}/g, function(all, name) {
    return library[name] !== undefined ? inline(library[name], library, (depth || 0) + 1) : all
  })
}

function uuid(rand) {
  var h = "0123456789abcdef"
  var s = ""
  for (var i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) s += "-"
    else if (i === 14) s += "4"
    else if (i === 19) s += h[(Math.floor(rand() * 16) & 3) | 8]
    else s += h[Math.floor(rand() * 16)]
  }
  return s
}

// → { text, cursor } where cursor is the number of characters after the
// {cursor} mark (0 when there is none). ctx: { now, values, inputs,
// commands, rand }.
function expand(text, ctx) {
  var now = ctx.now || new Date()
  var rand = ctx.rand || Math.random
  var values = ctx.values || {}, inputs = ctx.inputs || {}, commands = ctx.commands || {}
  var CURSOR = "\u0000cursor\u0000"
  var out = String(text).replace(TOKEN, function(all, name, offset, arg) {
    var when = offset ? shift(now, parseInt(offset.slice(0, -1), 10), offset.slice(-1)) : now
    switch (name) {
    case "date": return formatDate(when, arg || "YYYY-MM-DD")
    case "time": return formatDate(when, arg || "HH:mm")
    case "datetime": return formatDate(when, arg || "YYYY-MM-DD HH:mm")
    case "weekday": return formatDate(when, "dddd")
    case "week": return String(isoWeek(when))
    case "uuid": return uuid(rand)
    case "random":
      var n = Math.max(1, Math.min(64, parseInt(arg || "8", 10) || 8))
      var abc = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
      var r = ""
      for (var i = 0; i < n; i++) r += abc[Math.floor(rand() * abc.length)]
      return r
    case "cursor": return CURSOR
    case "input": return inputs[arg] !== undefined ? inputs[arg] : ""
    case "shell": return commands[arg] !== undefined ? commands[arg] : all
    }
    if (EXTERNAL[name]) return values[name] !== undefined ? values[name] : ""
    return all
  })
  var at = out.indexOf(CURSOR)
  if (at < 0) return { text: out, cursor: 0 }
  out = out.slice(0, at) + out.slice(at + CURSOR.length).split(CURSOR).join("")
  return { text: out, cursor: Array.from(out.slice(at)).length }
}

// ";sig" → "sig"; ";" → ""; else null.
function nameFrom(query) {
  var m = /^;(\S*)\s*$/.exec(String(query || ""))
  return m ? m[1].toLowerCase() : null
}

if (typeof module !== "undefined") {
  module.exports = { formatDate: formatDate, isoWeek: isoWeek, needs: needs, inline: inline, expand: expand, nameFrom: nameFrom }
}
