import QtQuick
import "Agenda.js" as Agenda

// Upcoming events from the calendars in ~/.config/omalaunch/calendars.json
// ([{ "name", "url" }]; for Google Calendar, the "secret address in iCal
// format" from the calendar's settings). "agenda" lists the next 14 days,
// "agenda demain" one day, "agenda client" filters; Enter joins the
// meeting link (Meet, Zoom, Teams…) or opens Google Calendar on that day.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Agenda"
  property string sectionTitle: "Agenda"
  property string placement: "inline"
  property int order: 9
  property var events: []
  property var errors: []
  property double loadedAt: 0
  property bool loading: false
  property var waiting: []
  readonly property string configFile: (root.host ? root.host.home : "") + "/.config/omalaunch/calendars.json"

  property var items: []

  function start() { load(function() {}) }
  function opened() {
    if (Date.now() - root.loadedAt > 120000) load(function() {})
    else publish()
  }

  function load(callback) {
    root.waiting = root.waiting.concat([callback])
    if (root.loading) return
    root.loading = true
    root.host.capture(["python3", root.pluginDir + "/agenda.py", root.configFile, root.host.dataDir, "14"], function(code, out) {
      root.loading = false
      try {
        var d = JSON.parse(out)
        root.events = Array.isArray(d) ? d : (d.events || [])
        root.errors = d.errors || []
      } catch (e) { root.events = [] }
      root.loadedAt = Date.now()
      publish()
      var w = root.waiting
      root.waiting = []
      w.forEach(function(cb) { cb() })
    }, 30000)
  }

  function eventRow(e, now, i) {
    var s = new Date(e.start), f = new Date(e.end)
    var when = e.allDay ? "Toute la journée" : Agenda.hm(s) + "–" + Agenda.hm(f)
    var rel = e.allDay ? "" : Agenda.relative(s, f, now)
    var bits = [Agenda.dayLabel(s, now)]
    if (rel) bits.push(rel)
    if (e.link) bits.push(/meet\.google/.test(e.link) ? "Meet" : (/zoom/.test(e.link) ? "Zoom" : (/teams/.test(e.link) ? "Teams" : "Visio")))
    else if (e.location) bits.push(e.location)
    bits.push(e.calendar)
    return {
      id: "ev:" + i + ":" + e.start + ":" + e.title, title: when + "  " + e.title, subtitle: bits.join("  ·  "),
      icon: e.link ? "" : (e.allDay ? "" : ""), type: "Event", event: e,
      copy: e.title + " — " + Agenda.dayLabel(s, now) + " " + when + (e.link ? " — " + e.link : (e.location ? " — " + e.location : "")),
      previewText: [e.title, Agenda.dayLabel(s, now) + ", " + when, e.location, e.link, e.calendar].filter(function(x) { return x }).join("\n")
    }
  }

  function publish() {
    var now = new Date()
    var rows = [
      { id: "add", title: "Add Calendar", subtitle: "Paste a calendar's secret iCal address (.ics)", icon: "", type: "Command", keywords: ["agenda", "calendar", "google calendar", "ics"] },
      { id: "edit", title: "Edit Calendars", subtitle: "~/.config/omalaunch/calendars.json", icon: "", type: "Command", keywords: ["agenda", "calendar", "settings"] }
    ]
    var n = Agenda.next(root.events, now)
    if (n) {
      var r = eventRow(n, now, "next")
      r.id = "next"
      r.title = "Next: " + r.title
      r.keywords = ["next meeting", "prochain rendez-vous", "prochain rdv", "agenda", "meeting"]
      rows.unshift(r)
    }
    if (JSON.stringify(rows) !== JSON.stringify(root.items)) {
      root.items = rows
      root.host.changed()
    }
  }

  function query(text, reply) {
    var q = Agenda.parse(text)
    if (!q) return []
    root.sectionTitle = "Agenda"
    var show = function() {
      var now = new Date()
      var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
      var list = root.events.filter(function(e) {
        var s = new Date(e.start)
        if (q.day === "today" && !Agenda.sameDay(s, now) && !(s <= now && new Date(e.end) > now)) return false
        if (q.day === "tomorrow" && !Agenda.sameDay(s, tomorrow)) return false
        return !q.filter || (e.title + " " + e.location + " " + e.calendar).toLowerCase().indexOf(q.filter) >= 0
      }).slice(0, 40)
      var rows = list.map(function(e, i) { return root.eventRow(e, now, i) })
      if (!rows.length) {
        var none = root.errors.length ? "Could not read: " + root.errors.join(", ") : (q.day || q.filter ? "No matching event" : "Nothing in the next 14 days")
        rows = [{ id: "none", title: none, subtitle: "Add a calendar with “Add Calendar”", icon: "", type: "Agenda", disabled: true }]
      }
      reply(rows, "inline")
    }
    if (Date.now() - root.loadedAt > 120000) load(show)
    else show()
    return null
  }

  function actions(row) {
    if (row.id === "add") return [{ id: "add", title: "Add Calendar" }]
    if (row.id === "edit") return [{ id: "edit", title: "Edit Calendars" }]
    if (!row.event) return [{ id: "none", title: "Nothing to do" }]
    var acts = []
    if (row.event.link) acts.push({ id: "join", title: "Join Call" })
    acts.push({ id: "calendar", title: "Open in Google Calendar" })
    acts.push({ id: "copy", title: "Copy Details" })
    return acts
  }

  function run(row, actionId) {
    if (row.id === "add") {
      root.host.ask("Calendar address (Google Calendar: Settings › your calendar › Secret address in iCal format)", function(url) {
        var u = String(url).trim()
        if (!/^(https?:\/\/|webcal:\/\/|\/|~)/.test(u)) { root.host.toast("That does not look like a calendar address"); return }
        u = u.replace(/^webcal:\/\//, "https://")
        root.host.ask("Name for this calendar", function(name) {
          var script = 'f=$1; mkdir -p "$(dirname "$f")"; [[ -s $f ]] || echo "[]" > "$f"; '
            + 'jq --arg n "$2" --arg u "$3" ". + [{name: \\$n, url: \\$u}]" "$f" > "$f.tmp" && mv "$f.tmp" "$f" && chmod 600 "$f"'
          root.host.capture(["bash", "-c", script, "bash", root.configFile, String(name).trim() || "Calendar", u], function(code) {
            if (code !== 0) { root.host.toast("Could not save the calendar"); return }
            root.host.toast("Calendar added; loading…")
            root.loadedAt = 0
            load(function() { root.host.toast(root.events.length + " upcoming events"); root.host.setQuery("agenda") })
          })
        }, "Askalon")
      })
      return { close: false }
    }
    if (row.id === "edit") {
      root.host.exec(["bash", "-c", 'mkdir -p "$(dirname "$1")"; [[ -e $1 ]] || { echo "[]" > "$1"; chmod 600 "$1"; }; exec omarchy-launch-editor "$1"', "bash", root.configFile])
      return { close: true }
    }
    var e = row.event
    if (!e) return { close: false }
    if (actionId === "copy") {
      root.host.copy(row.copy)
      return { close: false, toast: "Copied" }
    }
    if (actionId === "join" || (actionId !== "calendar" && e.link)) {
      root.host.browse(e.link)
      return { close: true }
    }
    var s = new Date(e.start)
    root.host.browse("https://calendar.google.com/calendar/r/day/" + s.getFullYear() + "/" + (s.getMonth() + 1) + "/" + s.getDate())
    return { close: true }
  }
}
