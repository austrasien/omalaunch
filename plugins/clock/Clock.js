// World clock, date arithmetic and timers in French or English
// (tests/clock.test.js). Pure helpers; the provider asks `date` for
// time-zone conversions.

var DAYS = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
var MONTHS = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]

function fold(s) {
  return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/['’]/g, " ").trim()
}

// French and everyday names that are not tz database cities.
var ALIASES = {
  "londres": "Europe/London", "uk": "Europe/London", "angleterre": "Europe/London",
  "geneve": "Europe/Zurich", "geneva": "Europe/Zurich", "lausanne": "Europe/Zurich", "suisse": "Europe/Zurich", "switzerland": "Europe/Zurich",
  "bruxelles": "Europe/Brussels", "vienne": "Europe/Vienna", "varsovie": "Europe/Warsaw", "lisbonne": "Europe/Lisbon",
  "moscou": "Europe/Moscow", "athenes": "Europe/Athens", "rome": "Europe/Rome", "milan": "Europe/Rome", "munich": "Europe/Berlin",
  "francfort": "Europe/Berlin", "allemagne": "Europe/Berlin", "germany": "Europe/Berlin", "espagne": "Europe/Madrid", "barcelone": "Europe/Madrid",
  "france": "Europe/Paris", "lyon": "Europe/Paris", "marseille": "Europe/Paris", "japon": "Asia/Tokyo", "japan": "Asia/Tokyo",
  "pekin": "Asia/Shanghai", "beijing": "Asia/Shanghai", "chine": "Asia/Shanghai", "china": "Asia/Shanghai", "hong kong": "Asia/Hong_Kong",
  "seoul": "Asia/Seoul", "coree": "Asia/Seoul", "inde": "Asia/Kolkata", "india": "Asia/Kolkata", "delhi": "Asia/Kolkata", "new delhi": "Asia/Kolkata",
  "mumbai": "Asia/Kolkata", "bombay": "Asia/Kolkata", "bangalore": "Asia/Kolkata", "duba": "Asia/Dubai", "dubai": "Asia/Dubai", "dubaï": "Asia/Dubai",
  "tel aviv": "Asia/Jerusalem", "israel": "Asia/Jerusalem", "le caire": "Africa/Cairo", "egypte": "Africa/Cairo", "singapour": "Asia/Singapore",
  "sydney": "Australia/Sydney", "australie": "Australia/Sydney", "melbourne": "Australia/Melbourne",
  "new york": "America/New_York", "nyc": "America/New_York", "washington": "America/New_York", "boston": "America/New_York", "miami": "America/New_York",
  "usa": "America/New_York", "etats unis": "America/New_York", "san francisco": "America/Los_Angeles", "sf": "America/Los_Angeles",
  "silicon valley": "America/Los_Angeles", "seattle": "America/Los_Angeles", "californie": "America/Los_Angeles", "california": "America/Los_Angeles",
  "austin": "America/Chicago", "dallas": "America/Chicago", "houston": "America/Chicago", "montreal": "America/Toronto", "quebec": "America/Toronto",
  "canada": "America/Toronto", "mexico": "America/Mexico_City", "bresil": "America/Sao_Paulo", "brazil": "America/Sao_Paulo", "rio": "America/Sao_Paulo",
  "buenos aires": "America/Argentina/Buenos_Aires", "argentine": "America/Argentina/Buenos_Aires", "reunion": "Indian/Reunion", "la reunion": "Indian/Reunion",
  "martinique": "America/Martinique", "guadeloupe": "America/Guadeloupe", "tahiti": "Pacific/Tahiti", "noumea": "Pacific/Noumea",
  "utc": "UTC", "gmt": "UTC"
}

// A tz name for a place: alias, else a tz database city ("tokyo" →
// Asia/Tokyo, "new york" → America/New_York), else null.
function zoneFor(place, zones) {
  var p = fold(place)
  if (!p) return null
  if (ALIASES[p]) return ALIASES[p]
  var want = p.replace(/\s+/g, "_")
  for (var i = 0; i < (zones || []).length; i++) {
    var z = zones[i]
    if (fold(z.slice(z.lastIndexOf("/") + 1)) === want) return z
  }
  return null
}

// Time-zone abbreviations and their fixed offsets in minutes. Where an
// abbreviation is ambiguous the most common meaning wins (CST = US Central,
// IST = India).
var ABBREVIATIONS = {
  utc: 0, gmt: 0, z: 0, wet: 0, west: 60, bst: 60, ist: 330, cet: 60, cest: 120, eet: 120, eest: 180, msk: 180,
  gst: 240, pkt: 300, ict: 420, wib: 420, sgt: 480, hkt: 480, awst: 480, pht: 480, jst: 540, kst: 540,
  acst: 570, acdt: 630, aest: 600, aedt: 660, nzst: 720, nzdt: 780,
  brt: -180, art: -180, ast: -240, adt: -180, est: -300, edt: -240, cst: -360, cdt: -300, mst: -420, mdt: -360,
  pst: -480, pdt: -420, akst: -540, akdt: -480, hst: -600
}

// A zone token: "UTC+2", "GMT-5:30", "+0200", "BST", or a place →
// { fixed: minutes, label } or { zone: "Area/City", label }, else null.
function zoneSpec(token, zones) {
  var t = fold(token).replace(/\s+/g, "")
  var m = /^(?:(utc|gmt)?([+-])(\d{1,2})(?::?(\d{2}))?|(utc|gmt))$/.exec(t)
  if (m && (m[1] || m[2] || m[5])) {
    var off = m[5] ? 0 : (m[2] === "-" ? -1 : 1) * (parseInt(m[3], 10) * 60 + (m[4] ? parseInt(m[4], 10) : 0))
    if (Math.abs(off) <= 14 * 60) return { fixed: off, label: m[5] ? m[5].toUpperCase() : offsetLabel(off) }
  }
  if (ABBREVIATIONS[t] !== undefined) return { fixed: ABBREVIATIONS[t], label: t.toUpperCase() + " (" + offsetLabel(ABBREVIATIONS[t]) + ")" }
  var z = zoneFor(token, zones)
  return z ? { zone: z, label: z === "UTC" ? "UTC" : z.slice(z.lastIndexOf("/") + 1).replace(/_/g, " ") } : null
}

function offsetLabel(min) {
  if (!min) return "UTC"
  var a = Math.abs(min)
  return "UTC" + (min > 0 ? "+" : "−") + Math.floor(a / 60) + (a % 60 ? ":" + (a % 60 < 10 ? "0" : "") + (a % 60) : "")
}

// "15h", "15h30", "15:30", "3pm", "3:30 pm", and in conversions "1000" /
// "930" → { h, m } or null.
function parseClock(s, allowBare) {
  var t = fold(s).replace(/\s+/g, "")
  var bare = /^(\d{1,2})(\d{2})$/.exec(t)
  if (allowBare && bare && t.length >= 3) {
    var bh = parseInt(bare[1], 10), bm = parseInt(bare[2], 10)
    return bh < 24 && bm < 60 ? { h: bh, m: bm } : null
  }
  var m = /^(\d{1,2})(?:[h:](\d{2})?)?(am|pm)?$/.exec(t)
  if (!m || (!m[2] && !m[3] && !/[h:]/.test(t))) return null
  var h = parseInt(m[1], 10), min = m[2] ? parseInt(m[2], 10) : 0
  if (m[3] === "pm" && h < 12) h += 12
  if (m[3] === "am" && h === 12) h = 0
  return h < 24 && min < 60 ? { h: h, m: min } : null
}

var UNITS = {
  j: "d", jour: "d", jours: "d", d: "d", day: "d", days: "d",
  sem: "w", semaine: "w", semaines: "w", w: "w", week: "w", weeks: "w",
  mois: "m", month: "m", months: "m",
  an: "y", ans: "y", annee: "y", annees: "y", y: "y", year: "y", years: "y",
  h: "h", heure: "h", heures: "h", hour: "h", hours: "h",
  min: "min", mn: "min", minute: "min", minutes: "min"
}

function addTo(d, n, unit) {
  var x = new Date(d.getTime())
  if (unit === "d") x.setDate(x.getDate() + n)
  else if (unit === "w") x.setDate(x.getDate() + 7 * n)
  else if (unit === "m") x.setMonth(x.getMonth() + n)
  else if (unit === "y") x.setFullYear(x.getFullYear() + n)
  else if (unit === "h") x.setTime(x.getTime() + n * 3600000)
  else if (unit === "min") x.setTime(x.getTime() + n * 60000)
  return x
}

function startOfDay(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
function daysBetween(a, b) { return Math.round((startOfDay(b) - startOfDay(a)) / 86400000) }

function isoWeek(d) {
  var t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
  var day = t.getUTCDay() || 7
  t.setUTCDate(t.getUTCDate() + 4 - day)
  return Math.ceil(((t - new Date(Date.UTC(t.getUTCFullYear(), 0, 1))) / 86400000 + 1) / 7)
}

function frenchDate(d) {
  return DAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear()
}

// "25/12", "25/12/2027", "2027-01-15", "today"/"aujourd'hui", "demain".
function parseDay(s, now) {
  var t = fold(s)
  if (t === "today" || t === "aujourd hui" || t === "auj") return startOfDay(now)
  if (t === "demain" || t === "tomorrow") return addTo(startOfDay(now), 1, "d")
  if (t === "hier" || t === "yesterday") return addTo(startOfDay(now), -1, "d")
  var m = /^(\d{1,2})[\/.](\d{1,2})(?:[\/.](\d{2,4}))?$/.exec(t)
  if (m) {
    var y = m[3] ? parseInt(m[3], 10) : now.getFullYear()
    if (y < 100) y += 2000
    var d = new Date(y, parseInt(m[2], 10) - 1, parseInt(m[1], 10))
    if (!m[3] && d < startOfDay(now)) d.setFullYear(y + 1)
    return d
  }
  m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(t)
  if (m) return new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10))
  return null
}

// One of:
//   { kind: "zone", place }                     time tokyo / heure à tokyo / tokyo time
//   { kind: "convert", h, m, from, to }         15h paris en tokyo / 3pm london to tokyo
//   { kind: "date", date, label }               dans 3 jours / in 2 weeks / il y a 10 jours / 3 days ago / aujourd'hui
//   { kind: "until", date }                     25/12 - today / jusqu'au 25/12 / until 25/12
//   { kind: "timer", minutes, label }           timer 25 café / minuteur 1h30 thé
// or null.
function parse(query, now) {
  var raw = String(query || "").trim()
  var q = fold(raw)
  var m
  if ((m = /^(?:timer|minuteur|rappel|reminder)\s+(?:(\d+)\s*h\s*(\d+)?|(\d+)\s*(?:min|mn|m)?)(?:\s+(.+))?$/.exec(q))) {
    var minutes = m[1] !== undefined ? parseInt(m[1], 10) * 60 + (m[2] ? parseInt(m[2], 10) : 0) : parseInt(m[3], 10)
    var label = m[4] ? raw.replace(/^\S+\s+\S+\s*/, "") : ""
    if (m[1] !== undefined && m[2] !== undefined && /^\S+\s+\d+\s*h\s+\d+/.test(raw)) label = raw.replace(/^\S+\s+\d+\s*h\s+\d+\s*/, "")
    return minutes > 0 ? { kind: "timer", minutes: minutes, label: label } : null
  }
  if (q === "time" || q === "heure" || q === "quelle heure") return { kind: "zone", place: "" }
  if ((m = /^(?:time|heure|il est quelle heure|quelle heure)(?:\s+(?:a|in|at|en|au|aux))?\s+(.+)$/.exec(q)) || (m = /^(.+?)\s+(?:time|heure)$/.exec(q))) {
    return { kind: "zone", place: m[1] }
  }
  if ((m = /^(\S+(?:\s*(?:am|pm))?)\s+(?:a\s+|at\s+)?(.+?)\s+(?:en|to|in|vers|->|=>)\s+(.+)$/.exec(q))) {
    var c = parseClock(m[1], true)
    if (c) return { kind: "convert", h: c.h, m: c.m, from: m[2], to: m[3] }
  }
  if ((m = /^(?:now|maintenant)\s+(?:en|to|in)\s+(.+)$/.exec(q))) return { kind: "zone", place: m[1] }
  if ((m = /^(?:dans|in)\s+(\d+)\s*([a-z]+)$/.exec(q)) && UNITS[m[2]]) {
    return { kind: "date", date: addTo(now, parseInt(m[1], 10), UNITS[m[2]]), unit: UNITS[m[2]] }
  }
  if (((m = /^il y a\s+(\d+)\s*([a-z]+)$/.exec(q)) || (m = /^(\d+)\s*([a-z]+)\s+ago$/.exec(q))) && UNITS[m[2]]) {
    return { kind: "date", date: addTo(now, -parseInt(m[1], 10), UNITS[m[2]]), unit: UNITS[m[2]] }
  }
  if ((m = /^(?:jusqu\s*(?:a|au|a la)|until|avant le|before)\s+(.+)$/.exec(q)) || (m = /^(.+?)\s*-\s*(?:today|aujourd hui|auj)$/.exec(q))) {
    var d = parseDay(m[1], now)
    if (d) return { kind: "until", date: d }
  }
  if (q === "today" || q === "aujourd hui" || q === "date" || q === "quel jour" || q === "demain" || q === "tomorrow") {
    return { kind: "date", date: parseDay(q === "date" || q === "quel jour" ? "today" : q, now), unit: "d" }
  }
  return null
}

if (typeof module !== "undefined") {
  module.exports = { fold: fold, zoneFor: zoneFor, zoneSpec: zoneSpec, offsetLabel: offsetLabel, parseClock: parseClock, parse: parse, daysBetween: daysBetween, frenchDate: frenchDate, isoWeek: isoWeek, DAYS: DAYS, MONTHS: MONTHS }
}
