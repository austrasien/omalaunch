// Quick settings queries (tests/settings.test.js).

var COMMANDS = [
  { cmd: "volume", words: ["vol", "volume", "son"] },
  { cmd: "brightness", words: ["lum", "luminosite", "luminosité", "brightness", "bri", "ecran", "écran"] },
  { cmd: "wifi", words: ["wifi", "wi-fi", "wlan", "reseau", "réseau"] },
  { cmd: "bluetooth", words: ["bt", "bluetooth"] },
  { cmd: "output", words: ["sortie", "output", "audio", "haut-parleur", "casque"] },
  { cmd: "dnd", words: ["dnd", "silence", "deranger", "déranger", "ne pas deranger", "ne pas déranger", "focus"] },
  { cmd: "battery", words: ["batterie", "battery", "bat", "power"] }
]

// → { cmd, arg } ("vol 40" → { cmd: "volume", arg: "40" }), else null.
function parse(query) {
  var q = String(query || "").trim().toLowerCase().replace(/\s+/g, " ")
  if (!q) return null
  for (var i = 0; i < COMMANDS.length; i++) {
    var c = COMMANDS[i]
    for (var j = 0; j < c.words.length; j++) {
      var w = c.words[j]
      if (q === w) return { cmd: c.cmd, arg: "" }
      if (q.indexOf(w + " ") === 0) return { cmd: c.cmd, arg: q.slice(w.length + 1).trim() }
    }
  }
  return null
}

// "40" → { set: 40 }, "+10" / "-5" → { by: ±n }, else null. 0–100 (150 for volume).
function level(arg, max) {
  var m = /^([+-]?)(\d{1,3})\s*%?$/.exec(String(arg || "").trim())
  if (!m) return null
  var n = parseInt(m[2], 10)
  if (m[1]) return { by: m[1] === "-" ? -n : n }
  return n <= (max || 100) ? { set: n } : null
}

// `wpctl status` → [{ id, name, default }] for the audio sinks.
function sinks(status) {
  var out = []
  var inAudio = false, inSinks = false
  String(status || "").split("\n").forEach(function(line) {
    if (/^Audio/.test(line)) { inAudio = true; return }
    if (/^(Video|Settings)/.test(line)) { inAudio = false; inSinks = false; return }
    if (!inAudio) return
    if (/Sinks:/.test(line)) { inSinks = true; return }
    if (/(Sources|Filters|Streams):/.test(line)) { inSinks = false; return }
    if (!inSinks) return
    var m = /^[\s│├└─]*(\*)?\s*(\d+)\.\s+(.*?)\s*(?:\[vol:.*)?$/.exec(line)
    if (m) out.push({ id: +m[2], name: m[3], default: !!m[1] })
  })
  return out
}

// `nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list` → networks, the
// strongest first, one row per SSID.
function networks(text) {
  var by = {}
  String(text || "").split("\n").forEach(function(line) {
    var f = line.replace(/\\:/g, "\u0001").split(":").map(function(x) { return x.replace(/\u0001/g, ":") })
    if (f.length < 4 || !f[1]) return
    var n = { ssid: f[1], signal: +f[2] || 0, secure: !!f[3] && f[3] !== "--", active: f[0] === "*" }
    var old = by[n.ssid]
    if (!old || n.active || (!old.active && n.signal > old.signal)) by[n.ssid] = n
  })
  var list = []
  for (var k in by) list.push(by[k])
  list.sort(function(a, b) { return (b.active ? 1 : 0) - (a.active ? 1 : 0) || b.signal - a.signal })
  return list
}

// `bluetoothctl devices Paired` + per-device "Connected: yes" lines.
function devices(text) {
  var out = []
  String(text || "").split("\n").forEach(function(line) {
    var m = /^Device ([0-9A-F:]{17}) (.*?)(?:\t(yes|no))?$/.exec(line.trim())
    if (m) out.push({ mac: m[1], name: m[2], connected: m[3] === "yes" })
  })
  return out
}

if (typeof module !== "undefined") module.exports = { parse: parse, level: level, sinks: sinks, networks: networks, devices: devices }
