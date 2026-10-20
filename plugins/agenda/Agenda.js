// Agenda helpers (tests/agenda.test.js).

var DAYS = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
var MONTHS = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]

// "agenda", "cal demain", "rdv client" → { filter, day } where day is
// "today" | "tomorrow" | "" ; else null.
function parse(query) {
  var m = /^(?:agenda|cal|calendar|rdv|meetings?|reunions?|réunions?)(?:\s+(.*?))?\s*$/i.exec(String(query || ""))
  if (!m) return null
  var rest = (m[1] || "").toLowerCase()
  if (rest === "aujourd'hui" || rest === "aujourd hui" || rest === "today" || rest === "auj") return { filter: "", day: "today" }
  if (rest === "demain" || rest === "tomorrow") return { filter: "", day: "tomorrow" }
  return { filter: rest, day: "" }
}

function pad(n) { return (n < 10 ? "0" : "") + n }
function hm(d) { return pad(d.getHours()) + ":" + pad(d.getMinutes()) }
function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate() }

// "aujourd'hui", "demain", "jeudi 22 oct."
function dayLabel(d, now) {
  if (sameDay(d, now)) return "aujourd'hui"
  var t = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
  if (sameDay(d, t)) return "demain"
  return DAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()]
}

// "en cours", "dans 25 min", "dans 3 h", "" (later days).
function relative(start, end, now) {
  if (start <= now && end > now) return "en cours"
  var min = Math.round((start - now) / 60000)
  if (min < 0) return "terminé"
  if (min < 60) return "dans " + min + " min"
  if (min < 12 * 60) return "dans " + Math.round(min / 60) + " h"
  return ""
}

// The next timed event that has not ended (all-day events skipped).
function next(events, now) {
  for (var i = 0; i < events.length; i++) {
    var e = events[i]
    if (!e.allDay && new Date(e.end) > now) return e
  }
  return null
}

if (typeof module !== "undefined") module.exports = { parse: parse, dayLabel: dayLabel, relative: relative, next: next, hm: hm, sameDay: sameDay }
