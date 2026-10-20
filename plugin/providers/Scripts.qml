import QtQuick
import "../core/Scripts.js" as Scripts

// Executables in ~/.config/omalaunch/scripts with an @omalaunch header
// (docs/SPEC.md §7). Rescanned each time the launcher opens. Filter
// scripts also answer queries that start with their keyword.
Item {
  id: root

  property var host: null
  property string title: "Scripts"
  property string sectionTitle: "Scripts"
  property string placement: "inline"
  property int order: 10
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
          subtitle: meta.description || (meta.mode === "filter" && meta.keyword ? "Type “" + meta.keyword + " ” and a search"
            : (meta.argument ? "Type the title, a space, then " + meta.argument : "")),
          icon: meta.icon || "",
          type: "Script",
          group: "commands",
          path: path,
          mode: meta.mode,
          argument: meta.argument,
          keyword: meta.keyword,
          copy: path
        })
      }
      if (JSON.stringify(rows) !== JSON.stringify(root.items)) {
        root.items = rows
        root.host.changed()
      }
    })
  }

  // ------------------------------------------------------ script filters

  function filterFor(text) {
    for (var i = 0; i < root.items.length; i++) {
      var s = root.items[i]
      if (s.mode !== "filter") continue
      var rest = Scripts.filterText(text, s.keyword)
      if (rest !== null) return { script: s, text: rest }
    }
    return null
  }

  function query(text, reply) {
    var f = filterFor(text)
    if (!f) return []
    var script = f.script
    var cwd = script.path.slice(0, script.path.lastIndexOf("/"))
    root.host.capture(["bash", "-c", 'cd "$1" && shift && exec "$@"', "bash", cwd, script.path, f.text], function(code, out, err) {
      var rows = Scripts.parseFilterOutput(out)
      if (rows === null) {
        var why = code !== 0 ? (String(err || "").trim().split("\n").pop() || "exit " + code) : "output is not JSON"
        rows = [{ id: "error", title: script.title + " failed", subtitle: why, icon: "\uf071", type: "Error", copy: String(err || out || "") }]
      }
      rows.forEach(function(r) { r.script = script.path; r.scriptTitle = script.title; r.filterItem = true })
      root.sectionTitle = script.title
      reply(rows, "inline")
    }, 15000)
    return null
  }

  function actions(row) {
    if (row.filterItem) {
      if (row.id === "error") return [{ id: "copy", title: "Copy Error" }]
      return [{ id: "pick", title: row.open ? "Open" : "Run" }, { id: "copy", title: "Copy" }]
    }
    if (row.mode === "filter") return [{ id: "run", title: "Search " + row.title }, { id: "edit", title: "Edit Script" }, { id: "copy-path", title: "Copy Path" }]
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
    if (row.filterItem) return pick(row, actionId)
    if (row.mode === "filter") {
      root.host.setQuery(row.keyword + " ")
      return { close: false }
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

  // Enter on a filter item: open its `open` target, or run the script
  // again as `<script> --run <arg>` and notify its last line of output.
  function pick(row, actionId) {
    if (actionId === "copy" || row.id === "error") {
      root.host.copy(row.copy)
      return { close: false, toast: "Copied" }
    }
    if (row.open) {
      if (/^https?:\/\//.test(row.open)) root.host.browse(row.open)
      else root.host.exec(["xdg-open", row.open])
      return { close: true }
    }
    var cwd = row.script.slice(0, row.script.lastIndexOf("/"))
    root.host.capture(["bash", "-c", 'cd "$1" && shift && exec "$@"', "bash", cwd, row.script, "--run", row.arg], function(code, out, err) {
      var lines = String(out || "").split("\n").filter(function(l) { return l.trim() })
      if (code !== 0) root.host.notify(row.scriptTitle, String(err || "").trim().split("\n").pop() || "Failed (" + code + ")")
      else if (lines.length) root.host.notify(row.scriptTitle, lines[lines.length - 1])
    }, 120000)
    return { close: true }
  }
}
