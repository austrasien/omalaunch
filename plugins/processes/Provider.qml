import QtQuick
import "Processes.js" as Processes

// "kill [name]": your processes grouped by program, biggest memory first.
// Enter sends SIGTERM to every process of the program, Ctrl+Enter SIGKILL.
// The session's own plumbing (Hyprland, the shell, PipeWire…) is listed but
// cannot be killed from here.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Processes"
  property string placement: "inline"
  property int order: 7

  property var items: [
    { id: "list", title: "Kill a Process", subtitle: "Type “kill” and a program name", icon: "", type: "Command", keywords: ["kill", "process", "task manager", "tuer", "force quit"] }
  ]

  function query(text, reply) {
    var words = Processes.termsFrom(text)
    if (words === null) return []
    root.host.capture(["bash", "-c", 'echo $$; ps -u "$(id -u)" -o pid=,comm=,%cpu=,rss=,args= --sort=-rss'], function(code, out) {
      var lines = String(out || "").split("\n")
      var self = parseInt(lines.shift(), 10)
      var groups = Processes.groups(Processes.parsePs(lines.join("\n"), self), words).slice(0, 25)
      var rows = groups.map(function(g) {
        var count = g.pids.length > 1 ? g.pids.length + " processes  ·  " : "pid " + g.pids[0] + "  ·  "
        return {
          id: "p:" + g.comm, title: g.comm,
          subtitle: count + Processes.memory(g.rss) + "  ·  " + g.cpu.toFixed(1) + " % CPU" + (g.protected ? "  ·  part of the session, not killed from here" : ""),
          icon: g.protected ? "" : "", type: "Process", pids: g.pids, comm: g.comm, disabled: g.protected,
          copy: g.pids.join(" "), previewText: g.args
        }
      })
      if (!rows.length) rows = [{ id: "none", title: "No process matches “" + words.join(" ") + "”", icon: "", type: "Process", disabled: true }]
      reply(rows, "inline")
    }, 5000)
    return null
  }

  function actions(row) {
    if (row.id === "list") return [{ id: "start", title: "List Processes" }]
    if (!row.pids) return [{ id: "none", title: "Nothing to do" }]
    var n = row.pids.length > 1 ? " (" + row.pids.length + ")" : ""
    return [{ id: "term", title: "Quit " + row.comm + n }, { id: "kill", title: "Force Kill " + row.comm + n }, { id: "copy", title: "Copy PIDs" }]
  }

  function run(row, actionId) {
    if (row.id === "list") {
      root.host.setQuery("kill ")
      return { close: false }
    }
    if (!row.pids) return { close: false }
    if (actionId === "copy") {
      root.host.copy(row.pids.join(" "))
      return { close: false, toast: "PIDs copied" }
    }
    var signal = actionId === "kill" ? "-KILL" : "-TERM"
    root.host.capture(["kill", signal].concat(row.pids.map(String)), function(code, out, err) {
      root.host.toast(code === 0 ? (actionId === "kill" ? "Killed " : "Asked to quit: ") + row.comm : "Could not signal " + row.comm + ": " + String(err || "").trim())
      root.host.refresh()
    })
    return { close: false }
  }
}
