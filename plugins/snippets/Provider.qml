import QtQuick
import "Snippets.js" as Snippets

// Text snippets: every file in ~/.config/omalaunch/snippets/ is one, named
// after the file ("sig.txt" → ";sig"). Enter pastes it into the focused
// window with its variables filled in (docs/SPEC.md §3); the clipboard is
// put back afterwards.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Snippets"
  property string placement: "inline"
  property int order: 8
  property var snippets: []           // [{ name, file, text, trusted }]
  property bool scanning: false
  readonly property string dir: (root.host ? root.host.home : "") + "/.config/omalaunch/snippets"

  property var items: [
    { id: "new", title: "New Snippet", subtitle: "Create a text you can paste with “;name”", icon: "", type: "Command", keywords: ["snippet", "text", "template", "expand"] },
    { id: "folder", title: "Open Snippets Folder", subtitle: "~/.config/omalaunch/snippets", icon: "", type: "Command", keywords: ["snippet", "snippets"] }
  ]

  function start() { scan() }
  function opened() { scan() }

  function scan() {
    if (root.scanning) return
    root.scanning = true
    var script = 'shopt -s nullglob; for f in "$1"/*; do [[ -f $f ]] || continue; (( $(stat -c %s "$f") < 65536 )) || continue; '
      + 'x=0; [[ -x $f ]] && x=1; printf "%s\\x1f%s\\x1f" "$f" "$x"; cat "$f"; printf "\\x1e"; done'
    root.host.capture(["bash", "-c", script, "bash", root.dir], function(code, out) {
      root.scanning = false
      var list = []
      String(out || "").split("\x1e").forEach(function(chunk) {
        var p = chunk.split("\x1f")
        if (p.length < 3) return
        var file = p[0].replace(/^\s+/, "")
        var base = file.slice(file.lastIndexOf("/") + 1)
        var name = base.replace(/\.[^.]*$/, "").toLowerCase()
        if (!name || /\s/.test(name)) return
        list.push({ name: name, file: file, text: p[2].replace(/\n$/, ""), trusted: p[1] === "1" })
      })
      list.sort(function(a, b) { return a.name < b.name ? -1 : 1 })
      root.snippets = list
    })
  }

  function library() {
    var lib = {}
    root.snippets.forEach(function(s) { lib[s.name] = s.text })
    return lib
  }

  function rowFor(s) {
    var first = s.text.split("\n")[0]
    return { id: "s:" + s.name, title: ";" + s.name, subtitle: first.length > 90 ? first.slice(0, 90) + "…" : first, icon: "", type: "Snippet", snippet: s.name, previewText: s.text, copy: s.text }
  }

  function query(text) {
    var name = Snippets.nameFrom(text)
    if (name === null) return []
    var rows = root.snippets.filter(function(s) { return s.name.indexOf(name) === 0 }).map(rowFor)
    var exact = root.snippets.filter(function(s) { return s.name === name })
    if (!rows.length) {
      rows = [{ id: "create:" + name, title: name ? "Create ;" + name : "No snippets yet", subtitle: name ? "New snippet in ~/.config/omalaunch/snippets/" + name + ".txt" : "Create one with “New Snippet”", icon: "", type: "Snippet", create: name || "" }]
    }
    return rows
  }

  function actions(row) {
    if (row.id === "new") return [{ id: "new", title: "New Snippet" }]
    if (row.id === "folder") return [{ id: "open", title: "Open Folder" }]
    if (row.create !== undefined) return [{ id: "create", title: row.title }]
    return [{ id: "paste", title: "Paste" }, { id: "copy", title: "Copy" }, { id: "edit", title: "Edit Snippet" }]
  }

  function find(name) {
    for (var i = 0; i < root.snippets.length; i++) if (root.snippets[i].name === name) return root.snippets[i]
    return null
  }

  function edit(name) {
    var file = root.dir + "/" + name + ".txt"
    root.host.exec(["bash", "-c", 'mkdir -p "$(dirname "$1")" && touch "$1" && exec omarchy-launch-editor "$1"', "bash", file])
  }

  function run(row, actionId) {
    if (row.id === "folder") {
      root.host.exec(["bash", "-c", 'mkdir -p "$1" && exec xdg-open "$1"', "bash", root.dir])
      return { close: true }
    }
    if (row.id === "new") {
      root.host.ask("Name of the new snippet (typed as ;name)", function(name) {
        var n = String(name).trim().replace(/^;/, "").toLowerCase()
        if (!/^[^\s\/]+$/.test(n)) { root.host.toast("A snippet name is one word"); return }
        root.host.close()
        edit(n)
      })
      return { close: false }
    }
    if (row.create !== undefined) {
      if (!row.create) return run({ id: "new" }, "new")
      edit(row.create)
      return { close: true }
    }
    var s = find(row.snippet)
    if (!s) return { close: false, toast: "Snippet not found" }
    if (actionId === "edit") {
      root.host.exec(["omarchy-launch-editor", s.file])
      return { close: true }
    }
    var text = Snippets.inline(s.text, library())
    var need = Snippets.needs(text)
    var answers = ({})
    var mode = actionId === "copy" ? "copy" : "paste"
    // Ask the {input:…} questions one after the other, then expand.
    var askNext = function(i) {
      if (i >= need.inputs.length) { finish(s, text, need, answers, mode); return }
      root.host.ask(need.inputs[i] + "  (;" + s.name + ")", function(value) {
        answers[need.inputs[i]] = value
        askNext(i + 1)
      })
    }
    askNext(0)
    return { close: false }
  }

  function finish(s, text, need, answers, mode) {
    if (mode === "paste") root.host.close()
    var commands = s.trusted ? need.commands : []
    var argv = ["bash", root.pluginDir + "/values.sh"].concat(need.values)
    if (commands.length) argv = argv.concat(["--"]).concat(commands)
    root.host.capture(argv, function(code, out) {
      var got = { values: {}, commands: {} }
      try { got = JSON.parse(out) } catch (e) {}
      var r = Snippets.expand(text, { now: new Date(), values: got.values, inputs: answers, commands: got.commands })
      if (mode === "copy") {
        root.host.copy(r.text)
        root.host.toast("Copied ;" + s.name)
        return
      }
      // Paste with Shift+Insert, move the cursor back to {cursor}, then put
      // the previous text clipboard back.
      var script = 'old=$(wl-paste -n --type text 2>/dev/null); had=$?; printf "%s" "$1" | wl-copy; sleep 0.15; '
        + 'wtype -M shift -k Insert -m shift; n=$2; while (( n-- > 0 )); do wtype -k Left; done; '
        + 'sleep 0.4; (( had == 0 )) && printf "%s" "$old" | wl-copy'
      root.host.exec(["bash", "-c", script, "bash", r.text, String(r.cursor)])
    }, 15000)
  }
}
