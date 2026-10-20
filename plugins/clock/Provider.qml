import QtQuick
import "Clock.js" as Clock

// World clock, date arithmetic and timers (see Clock.parse for what it
// understands, in French or English). Timers are Omarchy reminders.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Clock"
  property string placement: "inline"
  property int order: 6
  property var zones: []

  function start() {
    root.host.capture(["timedatectl", "list-timezones"], function(code, out) {
      root.zones = String(out || "").split("\n").filter(function(z) { return z })
    })
  }

  function pad(n) { return (n < 10 ? "0" : "") + n }
  function hm(d) { return pad(d.getHours()) + ":" + pad(d.getMinutes()) }
  function place(zone) { return zone === "UTC" ? "UTC" : zone.slice(zone.lastIndexOf("/") + 1).replace(/_/g, " ") }

  // "+0900" → minutes east of UTC.
  function offsetMinutes(z) {
    var m = /^([+-])(\d{2})(\d{2})$/.exec(z)
    return m ? (m[1] === "-" ? -1 : 1) * (parseInt(m[2], 10) * 60 + parseInt(m[3], 10)) : 0
  }

  function gap(minutes) {
    if (!minutes) return "même heure qu'ici"
    var h = Math.floor(Math.abs(minutes) / 60), m = Math.abs(minutes) % 60
    return (minutes > 0 ? "+" : "−") + h + " h" + (m ? " " + pad(m) : "") + " par rapport à ici"
  }

  // Ask `date` for the wall time in `zone` (optionally of a time given in
  // another zone): fields "Y M D H M weekday offset".
  function wallTime(zone, spec, callback) {
    var fmt = "+%Y %m %d %H %M %w %z"
    var argv = zone ? ["env", "TZ=" + zone, "date"] : ["date"]
    argv = spec ? argv.concat(["-d", spec, fmt]) : argv.concat([fmt])
    root.host.capture(argv, function(code, out) {
      var f = String(out || "").trim().split(" ")
      if (code !== 0 || f.length < 7) { callback(null); return }
      callback({ y: +f[0], mo: +f[1], d: +f[2], h: +f[3], mi: +f[4], wd: +f[5], off: f[6] })
    }, 3000)
  }

  function describe(t) {
    return Clock.DAYS[t.wd] + " " + t.d + " " + Clock.MONTHS[t.mo - 1]
  }

  function query(text, reply) {
    var now = new Date()
    var q = Clock.parse(text, now)
    if (!q) return []
    var here = -now.getTimezoneOffset()

    if (q.kind === "zone") {
      var zone = q.place ? Clock.zoneFor(q.place, root.zones) : ""
      if (q.place && !zone) return []
      wallTime(zone || "", "", function(t) {
        if (!t) return
        var time = pad(t.h) + ":" + pad(t.mi)
        reply([{ id: "zone", title: zone ? time + " à " + place(zone) : time + " — heure locale", subtitle: describe(t) + "  ·  UTC" + t.off.slice(0, 3) + ":" + t.off.slice(3) + (zone ? "  ·  " + gap(offsetMinutes(t.off) - here) : ""), icon: "", type: "Clock", copy: time }])
      })
      return null
    }

    if (q.kind === "convert") {
      var from = Clock.zoneFor(q.from, root.zones), to = Clock.zoneFor(q.to, root.zones)
      if (!from || !to) return []
      var day = now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate())
      wallTime(to, 'TZ="' + from + '" ' + day + " " + pad(q.h) + ":" + pad(q.m), function(t) {
        if (!t) return
        var time = pad(t.h) + ":" + pad(t.mi)
        reply([{ id: "convert", title: time + " à " + place(to), subtitle: pad(q.h) + ":" + pad(q.m) + " à " + place(from) + " → " + describe(t) + " à " + place(to), icon: "", type: "Clock", copy: time }])
      })
      return null
    }

    if (q.kind === "date") {
      var d = q.date
      var withTime = q.unit === "h" || q.unit === "min"
      var title = Clock.frenchDate(d) + (withTime ? " à " + hm(d) : "")
      var n = Clock.daysBetween(now, d)
      var rel = n === 0 ? "aujourd'hui" : (n > 0 ? "dans " + n + " jour" + (n > 1 ? "s" : "") : "il y a " + (-n) + " jour" + (n < -1 ? "s" : ""))
      var iso = d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
      return [{ id: "date", title: title, subtitle: rel + "  ·  semaine " + Clock.isoWeek(d) + "  ·  " + iso, icon: "", type: "Date", copy: iso }]
    }

    if (q.kind === "until") {
      var days = Clock.daysBetween(now, q.date)
      var w = Math.floor(Math.abs(days) / 7), r = Math.abs(days) % 7
      var detail = w ? w + " semaine" + (w > 1 ? "s" : "") + (r ? " et " + r + " jour" + (r > 1 ? "s" : "") : "") : ""
      return [{ id: "until", title: Math.abs(days) + " jour" + (Math.abs(days) > 1 ? "s" : "") + (days < 0 ? " écoulés" : ""), subtitle: (days < 0 ? "depuis le " : "jusqu'au ") + Clock.frenchDate(q.date) + (detail ? "  ·  " + detail : ""), icon: "", type: "Date", copy: String(Math.abs(days)) }]
    }

    if (q.kind === "timer") {
      var at = new Date(now.getTime() + q.minutes * 60000)
      var dur = q.minutes >= 60 ? Math.floor(q.minutes / 60) + " h" + (q.minutes % 60 ? " " + pad(q.minutes % 60) : "") : q.minutes + " min"
      return [{ id: "timer", title: "Minuteur " + dur + (q.label ? " — " + q.label : ""), subtitle: "Notification à " + hm(at) + " (rappel Omarchy)", icon: "", type: "Timer", minutes: q.minutes, label: q.label, copy: hm(at) }]
    }
    return []
  }

  function actions(row) {
    if (row.id === "timer") return [{ id: "start", title: "Start Timer" }, { id: "show", title: "Show Reminders" }]
    return [{ id: "copy", title: "Copy" }]
  }

  function run(row, actionId) {
    if (row.id === "timer") {
      if (actionId === "show") {
        root.host.exec(["omarchy", "reminder", "show"])
        return { close: true }
      }
      var argv = ["omarchy", "reminder", String(row.minutes)]
      if (row.label) argv.push(row.label)
      root.host.exec(argv)
      return { close: true }
    }
    root.host.copy(row.copy)
    return { close: false, toast: "Copied " + row.copy }
  }
}
