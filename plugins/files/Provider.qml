import QtQuick
import "Files.js" as Files

// Files in the home folder ("'term" or "find term", via fd) and recently
// used documents (recently-used.xbel), searchable like any other row.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Files"
  property string placement: "inline"
  property int order: 20
  property var items: []
  property bool haveFd: false
  readonly property int recentLimit: 40

  function start() {
    root.host.capture(["bash", "-c", "command -v fd"], function(code) { root.haveFd = code === 0 })
    loadRecent()
  }

  function opened() { loadRecent() }

  function fileRow(path, id, type) {
    var dir = /\/$/.test(path)
    var clean = path.replace(/\/+$/, "") || "/"
    return {
      id: id,
      title: Files.basename(clean) || clean,
      subtitle: Files.tilde(clean, root.host.home),
      icon: dir ? "" : "",
      type: type || (dir ? "Folder" : "File"),
      path: clean,
      folder: dir,
      copy: clean
    }
  }

  // ------------------------------------------------------------ search

  function query(text, reply) {
    var words = Files.termsFrom(text)
    if (!words) return []
    if (!root.haveFd) return [{ id: "missing", title: "File search needs fd", subtitle: "sudo pacman -S fd", icon: "", type: "Files", disabled: true }]
    root.host.capture(["fd", "-i", "-F", "--max-results", "400", "--absolute-path", "--", words[0], root.host.home], function(code, out) {
      var paths = Files.rank(String(out || "").split("\n"), words, 30)
      var rows = paths.map(function(p, i) { return root.fileRow(p, "find:" + p) })
      if (!rows.length) rows = [{ id: "none", title: "No files match “" + words.join(" ") + "”", icon: "", type: "Files", disabled: true }]
      reply(rows, "inline")
    }, 8000)
    return null
  }

  // ------------------------------------------------------------ recent

  function loadRecent() {
    var xbel = root.host.home + "/.local/share/recently-used.xbel"
    root.host.capture(["cat", xbel], function(code, out) {
      if (code !== 0) return
      var recent = Files.parseRecent(out).slice(0, root.recentLimit * 2)
      if (!recent.length) return
      // Keep the ones that still exist; mark folders with a trailing slash.
      var script = 'for p; do if [[ -d $p ]]; then printf "%s/\\n" "$p"; elif [[ -e $p ]]; then printf "%s\\n" "$p"; fi; done'
      root.host.capture(["bash", "-c", script, "bash"].concat(recent.map(function(r) { return r.path })), function(c2, existing) {
        var rows = String(existing || "").split("\n").filter(function(l) { return l }).slice(0, root.recentLimit)
          .map(function(p) {
            var r = root.fileRow(p, "recent:" + p.replace(/\/+$/, ""), "Recent")
            r.visibility = "search-only"
            r.keywords = ["recent"]
            r.boost = -40
            return r
          })
        rows.unshift({ id: "recent-list", title: "Recent Documents", subtitle: rows.length + " recently used files", icon: "", type: "Command", keywords: ["recent", "files", "history"] })
        if (JSON.stringify(rows) !== JSON.stringify(root.items)) {
          root.items = rows
          root.host.changed()
        }
      })
    })
  }

  // ----------------------------------------------------------- actions

  function actions(row) {
    if (row.id === "recent-list") return [{ id: "show", title: "Show Recent Documents" }]
    if (!row.path) return [{ id: "none", title: "Nothing to do" }]
    return [
      { id: "open", title: row.folder ? "Open Folder" : "Open" },
      { id: "reveal", title: "Open Containing Folder" },
      { id: "terminal", title: "Open Terminal Here" },
      { id: "copy-path", title: "Copy Path" }
    ]
  }

  function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  function run(row, actionId) {
    if (row.id === "recent-list") {
      var list = root.items.filter(function(r) { return r.path }).map(function(r) {
        var c = {}
        for (var k in r) c[k] = r[k]
        c.visibility = "always"
        return c
      })
      return { close: false, push: { id: "files:recent", title: "Recent Documents", rows: list } }
    }
    if (!row.path) return { close: false }
    var dir = row.folder ? row.path : row.path.slice(0, row.path.lastIndexOf("/")) || "/"
    switch (actionId) {
    case "reveal":
      root.host.exec(["xdg-open", dir])
      return { close: true }
    case "terminal":
      root.host.exec(["setsid", "uwsm-app", "--", "xdg-terminal-exec", "--dir=" + dir])
      return { close: true }
    case "copy-path":
      root.host.copy(row.path)
      return { close: false, toast: "Path copied" }
    }
    root.host.exec(["xdg-open", row.path])
    return { close: true }
  }
}
