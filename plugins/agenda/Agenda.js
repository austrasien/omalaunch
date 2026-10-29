// Agenda helpers (tests/agenda.test.js).

var DAYS = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
var SHORT = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
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

// The last day an event covers: an end at midnight belongs to the day before.
function lastDay(start, end) {
  var d = new Date(end.getTime() - 1)
  return d < start ? start : d
}

function multiDay(start, end) { return !sameDay(start, lastDay(start, end)) }

// "11:00–11:45", "mer. 11:39 → jeu. 16:19" (dates added past a week),
// "Toute la journée", "Jusqu'au ven. 31 oct.".
function span(start, end, allDay) {
  var last = lastDay(start, end)
  if (allDay) return sameDay(start, last) ? "Toute la journée" : "Jusqu'au " + SHORT[last.getDay()] + " " + last.getDate() + " " + MONTHS[last.getMonth()]
  if (sameDay(start, last)) return hm(start) + "–" + hm(end)
  var dated = end - start >= 6 * 86400000
  function day(d) { return SHORT[d.getDay()] + (dated ? " " + d.getDate() + " " + MONTHS[d.getMonth()] : "") }
  return day(start) + " " + hm(start) + " → " + day(end) + " " + hm(end)
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

if (typeof module !== "undefined") module.exports = { parse: parse, dayLabel: dayLabel, relative: relative, next: next, hm: hm, sameDay: sameDay, span: span, multiDay: multiDay }
