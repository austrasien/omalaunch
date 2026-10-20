import QtQuick
import "../core/Scripts.js" as Scripts

// Executables in ~/.config/omalaunch/scripts with an @omalaunch header
// (docs/SPEC.md §7). Rescanned each time the launcher opens.
Item {
  id: root

  property var host: null
  property string title: "Scripts"
  property var items: []
  readonly property string dir: (root.host ? root.host.home : "") + "/.config/omalaunch/scripts"
  property bool scanning: false

  function start() { scan() }
  function opened() { scan() }

  function scan() {
    if (root.scanning || !root.host) return
    root.scanning = true
    var script = 'shopt -s nullglob; for f in "$1"/*; do [[ -f $f && -x $f && $f != *.template.* ]] || continue; '
      + '(( $(stat -c %s "$f") < 2097152 )) || continue; printf "%s\\x1f" "$f"; head -n 30 "$f"; printf "\\x1e"; done'
    root.host.capture(["bash", "-c", script, "bash", root.dir], function(code, out) {
      root.scanning = false
      var rows = []
      var chunks = String(out || "").split("\x1e")
      for (var i = 0; i < chunks.length; i++) {
        var parts = chunks[i].split("\x1f")
        if (parts.length < 2) continue
        var path = parts[0].trim()
        var meta = Scripts.parseHeader(parts[1])
        if (!meta) continue
        rows.push({
          id: path.slice(path.lastIndexOf("/") + 1),
          title: meta.title,
          subtitle: meta.description || (meta.argument ? "Type the title, a space, then " + meta.argument : ""),
          icon: meta.icon || "",
          type: "Script",
          group: "commands",
          path: path,
          mode: meta.mode,
          argument: meta.argument,
          copy: path
        })
      }
      if (JSON.stringify(rows) !== JSON.stringify(root.items)) {
        root.items = rows
        root.host.changed()
      }
    })
  }

  function actions(row) {
    return [{ id: "run", title: "Run Script" }, { id: "edit", title: "Edit Script" }, { id: "copy-path", title: "Copy Path" }]
  }

  function run(row, actionId, ctx) {
    if (actionId === "edit") {
      root.host.exec(["omarchy-launch-editor", row.path])
      return { close: true }
    }
    if (actionId === "copy-path") {
      root.host.copy(row.path)
      return { close: false, toast: "Path copied" }
    }
    var arg = row.argument ? Scripts.argumentFrom(ctx.query, row.title, ctx.alias) : ""
    var argv = arg ? [row.path, arg] : [row.path]
    var cwd = row.path.slice(0, row.path.lastIndexOf("/"))
    if (row.mode === "terminal") {
      var quoted = argv.map(function(a) { return "'" + a.replace(/'/g, "'\\''") + "'" }).join(" ")
      root.host.terminal("cd '" + cwd.replace(/'/g, "'\\''") + "' && " + quoted, true)
      return { close: true }
    }
    if (row.mode === "toast") {
      root.host.capture(["bash", "-c", 'cd "$1" && shift && exec "$@"', "bash", cwd].concat(argv), function(code, out, err) {
        var lines = String(out || "").split("\n").filter(function(l) { return l.trim() })
        var last = lines.length ? lines[lines.length - 1] : (code === 0 ? "Done" : "Failed (" + code + ")")
        if (code !== 0 && err) last = String(err).trim().split("\n").pop()
        root.host.notify(row.title, last)
      }, 120000)
      return { close: true }
    }
    root.host.exec(["bash", "-c", 'cd "$1" && shift && exec "$@"', "bash", cwd].concat(argv))
    return { close: true }
  }
}
