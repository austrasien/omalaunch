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

  // The wall time at instant `ms` in a zone spec ({ fixed } offset, { zone }
  // name, or "" for local): { y, mo, d, h, mi, wd, off (minutes) }.
  function wallAt(ms, spec, callback) {
    if (spec.fixed !== undefined) {
      var u = new Date(ms + spec.fixed * 60000)
      callback({ y: u.getUTCFullYear(), mo: u.getUTCMonth() + 1, d: u.getUTCDate(), h: u.getUTCHours(), mi: u.getUTCMinutes(), wd: u.getUTCDay(), off: spec.fixed })
      return
    }
    var argv = (spec.zone ? ["env", "TZ=" + spec.zone, "date"] : ["date"]).concat(["-d", "@" + Math.floor(ms / 1000), "+%Y %m %d %H %M %w %z"])
    root.host.capture(argv, function(code, out) {
      var f = String(out || "").trim().split(" ")
      if (code !== 0 || f.length < 7) { callback(null); return }
      callback({ y: +f[0], mo: +f[1], d: +f[2], h: +f[3], mi: +f[4], wd: +f[5], off: offsetMinutes(f[6]) })
    }, 3000)
  }

  // The instant of today's h:m in a zone spec, in ms.
  function instantOf(now, h, m, spec, callback) {
    if (spec.fixed !== undefined) {
      callback(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate(), h, m) - spec.fixed * 60000)
      return
    }
    var day = now.getFullYear() + "-" + pad(now.getMonth() + 1) + "-" + pad(now.getDate())
    root.host.capture(["date", "-d", 'TZ="' + spec.zone + '" ' + day + " " + pad(h) + ":" + pad(m), "+%s"], function(code, out) {
      callback(code === 0 ? parseInt(String(out).trim(), 10) * 1000 : null)
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
      var spec = q.place ? Clock.zoneSpec(q.place, root.zones) : { zone: "", label: "" }
      if (!spec) return []
      root.wallAt(Date.now(), spec, function(t) {
        if (!t) return
        var time = pad(t.h) + ":" + pad(t.mi)
        var title = q.place ? time + " — " + spec.label : time + " — heure locale"
        reply([{ id: "zone", title: title, subtitle: describe(t) + "  ·  " + Clock.offsetLabel(t.off) + (q.place ? "  ·  " + gap(t.off - here) : ""), icon: "\uf017", type: "Clock", copy: time }])
      })
      return null
    }

    if (q.kind === "convert") {
      var from = Clock.zoneSpec(q.from, root.zones), to = Clock.zoneSpec(q.to, root.zones)
      if (!from || !to) return []
      root.instantOf(now, q.h, q.m, from, function(ms) {
        if (ms === null) return
        root.wallAt(ms, to, function(t) {
          if (!t) return
          var time = pad(t.h) + ":" + pad(t.mi)
          var src = new Date(now.getFullYear(), now.getMonth(), now.getDate())
          var shift = Math.round((Date.UTC(t.y, t.mo - 1, t.d) - Date.UTC(src.getFullYear(), src.getMonth(), src.getDate())) / 86400000)
          var dayNote = shift === 1 ? " (lendemain)" : (shift === -1 ? " (veille)" : "")
          reply([{ id: "convert", title: time + dayNote + " — " + to.label, subtitle: pad(q.h) + ":" + pad(q.m) + " " + from.label + "  →  " + time + " " + to.label + "  ·  " + describe(t), icon: "\uf017", type: "Clock", copy: time }])
        })
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
