import QtQuick

// Omarchy's clipboard history (~/.local/state/omarchy/clipboard-history.json,
// kept by the shell's clipboard plugin): "clip text" searches it inline, the
// "Clipboard History" command lists it. Enter pastes into the focused window.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Clipboard"
  property string placement: "inline"
  property int order: 15
  property var entries: []
  readonly property string historyFile: (root.host ? root.host.home : "") + "/.local/state/omarchy/clipboard-history.json"
  readonly property int maxEntries: 200
  readonly property int maxChars: 20000

  property var items: [
    { id: "history", title: "Clipboard History", subtitle: "Search and paste what you copied", icon: "", type: "Command", keywords: ["clipboard", "paste", "copy", "clip"] }
  ]

  function start() { load() }
  function opened() { load() }

  function load() {
    var filter = '[.[:' + root.maxEntries + '][] | if .type == "text" then {type, text: .text[0:' + root.maxChars + ']} else {type, path, mime} end]'
    root.host.capture(["jq", "-c", filter, root.historyFile], function(code, out) {
      if (code !== 0) return
      try { root.entries = JSON.parse(out) } catch (e) { root.entries = [] }
    })
  }

  function rowFor(entry, i) {
    if (entry.type === "image") {
      return { id: "clip:" + i, title: "Image", subtitle: entry.path.slice(entry.path.lastIndexOf("/") + 1), iconSource: "file://" + entry.path, type: "Image", entry: entry, copy: entry.path }
    }
    var text = String(entry.text || "")
    var first = text.replace(/^\s+/, "").split("\n")[0]
    var lines = text.split("\n").length
    return {
      id: "clip:" + i,
      title: first.length > 120 ? first.slice(0, 120) + "…" : first,
      subtitle: (lines > 1 ? lines + " lines · " : "") + text.length + " characters",
      icon: /^https?:\/\//.test(text.trim()) ? "" : "",
      type: "Clipboard",
      entry: entry,
      copy: text
    }
  }

  function matching(words, limit) {
    var rows = []
    for (var i = 0; i < root.entries.length && rows.length < limit; i++) {
      var e = root.entries[i]
      var hay = (e.type === "image" ? "image " + e.path : String(e.text || "")).toLowerCase()
      var ok = true
      for (var w = 0; w < words.length; w++) if (hay.indexOf(words[w]) < 0) { ok = false; break }
      if (ok) rows.push(rowFor(e, i))
    }
    return rows
  }

  function query(text) {
    var m = /^clip\s+(.*\S)\s*$/i.exec(String(text || ""))
    if (!m) return []
    var rows = matching(m[1].toLowerCase().split(/\s+/), 20)
    return rows.length ? rows : [{ id: "none", title: "Nothing in the clipboard history matches", icon: "", type: "Clipboard", disabled: true }]
  }

  function actions(row) {
    if (row.id === "history") return [{ id: "show", title: "Show Clipboard History" }]
    if (!row.entry) return [{ id: "none", title: "Nothing to do" }]
    return [{ id: "paste", title: "Paste" }, { id: "copy", title: "Copy" }]
  }

  function run(row, actionId) {
    if (row.id === "history") {
      var rows = root.entries.map(function(e, i) { return root.rowFor(e, i) })
      return { close: false, push: { id: "clipboard:history", title: "Clipboard History", rows: rows } }
    }
    var e = row.entry
    if (!e) return { close: false }
    var paste = actionId !== "copy"
    if (e.type === "image") {
      var script = 'wl-copy --type "$2" < "$1" || exit; [[ $3 == paste ]] || exit 0; sleep 0.15; wtype -M shift -k Insert -m shift'
      root.host.exec(["bash", "-c", script, "bash", e.path, e.mime || "image/png", paste ? "paste" : "copy"])
    } else if (paste) {
      root.host.exec([root.host.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", String(e.text)])
    } else {
      root.host.copy(e.text)
      return { close: false, toast: "Copied" }
    }
    return { close: true }
  }
}
