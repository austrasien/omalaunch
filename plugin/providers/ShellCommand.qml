import QtQuick

// "> command" runs a shell command (docs/SPEC.md §7): in a floating
// terminal by default, silently with Ctrl+Enter.
Item {
  id: root

  property var host: null
  property string title: "Shell"
  property string placement: "inline"
  property int order: 5

  function commandFrom(text) {
    var m = /^>\s*(.*\S)\s*$/.exec(String(text || ""))
    return m ? m[1] : ""
  }

  function query(text) {
    var cmd = commandFrom(text)
    if (!cmd) return []
    return [{ id: "run", title: cmd, subtitle: "Run in a terminal", icon: "", type: "Shell", command: cmd, copy: cmd }]
  }

  function actions(row) {
    return [
      { id: "terminal", title: "Run in Terminal" },
      { id: "silent", title: "Run in Background" },
      { id: "copy", title: "Copy Command" }
    ]
  }

  function run(row, actionId) {
    if (actionId === "copy") {
      root.host.copy(row.command)
      return { close: false, toast: "Copied" }
    }
    if (actionId === "silent") {
      root.host.shell(row.command)
      return { close: true }
    }
    root.host.terminal(row.command, true)
    return { close: true }
  }
}
