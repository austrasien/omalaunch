import QtQuick
import "Files.js" as Files

// Files in the home folder ("'term" or "find term", via fd), search
// filters ("pdf term": a keyword tied to extensions and folders, from
// ~/.config/omalaunch/file-filters.json) and recently used documents
// (recently-used.xbel), searchable like any other row.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Files"
  property string placement: "inline"
  property int order: 20
  property var items: []
  property string sectionTitle: "Files"
  property var recentRows: []
  property var filters: Files.normalizeFilters(Files.DEFAULT_FILTERS)
  readonly property string filtersFile: (root.host ? root.host.home : "") + "/.config/omalaunch/file-filters.json"
  property bool haveFd: false
  readonly property int recentLimit: 40

  function start() {
    root.host.capture(["bash", "-c", "command -v fd"], function(code) { root.haveFd = code === 0 })
    loadFilters()
    loadRecent()
  }

  function opened() { loadFilters(); loadRecent() }

  function loadFilters() {
    root.host.capture(["cat", root.filtersFile], function(code, out) {
      var list = Files.DEFAULT_FILTERS
      if (code === 0) {
        try { list = JSON.parse(out) } catch (e) { root.host.toast("file-filters.json is not valid JSON; using the defaults") }
      }
      var next = Files.normalizeFilters(list)
      if (JSON.stringify(next) !== JSON.stringify(root.filters)) {
        root.filters = next
        publish()
      }
    })
  }

  // Catalog rows: one command per filter, the filters file, recent files.
  function publish() {
    var rows = root.filters.map(function(f) {
      var where = f.folders.join(", ")
      var what = f.extensions.length ? f.extensions.slice(0, 6).join(", ") + (f.extensions.length > 6 ? "…" : "") : (f.type === "folder" ? "folders" : "everything")
      return { id: "filter:" + f.keyword, title: "Search " + f.title, subtitle: "“" + f.keyword + " …”  ·  " + what + " in " + where, icon: "\uf002", type: "Filter", keyword: f.keyword, keywords: [f.keyword, "find", "files"] }
    })
    rows.push({ id: "edit-filters", title: "Edit File Search Filters", subtitle: "~/.config/omalaunch/file-filters.json", icon: "\uf013", type: "Command", keywords: ["files", "filters", "settings"] })
    rows = rows.concat(root.recentRows)
    if (JSON.stringify(rows) !== JSON.stringify(root.items)) {
      root.items = rows
      root.host.changed()
    }
  }

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
    var f = Files.filterFor(text, root.filters)
    if (f) return filterQuery(f.filter, f.words, reply)
    root.sectionTitle = "Files"
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

  function filterQuery(filter, words, reply) {
    if (!root.haveFd) return [{ id: "missing", title: "File search needs fd", subtitle: "sudo pacman -S fd", icon: "\uf071", type: "Files", disabled: true }]
    var args = Files.fdArgs(filter, words, root.host.home)
    var argv
    if (words.length) {
      argv = ["fd", "--max-results", "400"].concat(args)
    } else {
      // No terms: the newest matches first.
      argv = ["bash", "-c", 'fd -0 --changed-within 365d "$@" | head -z -n 4000 | xargs -0 -r stat -c "%Y %n" -- 2>/dev/null | sort -rn | head -n 30 | cut -d" " -f2-', "bash"].concat(args)
    }
    root.host.capture(argv, function(code, out) {
      var lines = String(out || "").split("\n").filter(function(l) { return l })
      var paths = words.length ? Files.rank(lines, words, 30) : lines
      var rows = paths.map(function(p) { return root.fileRow(p, "find:" + p) })
      if (!rows.length) rows = [{ id: "none", title: "No " + filter.title.toLowerCase() + " match" + (words.length ? " “" + words.join(" ") + "”" : ""), icon: "\uf15b", type: "Files", disabled: true }]
      root.sectionTitle = filter.title
      reply(rows, "inline")
    }, 10000)
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
        root.recentRows = rows
        root.publish()
      })
    })
  }

  // ----------------------------------------------------------- actions

  function actions(row) {
    if (row.id === "recent-list") return [{ id: "show", title: "Show Recent Documents" }]
    if (row.keyword) return [{ id: "search", title: row.title }]
    if (row.id === "edit-filters") return [{ id: "edit", title: "Edit Filters" }]
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
    if (row.keyword) {
      root.host.setQuery(row.keyword + " ")
      return { close: false }
    }
    if (row.id === "edit-filters") {
      // Write the defaults first so there is something to edit.
      var script = '[[ -e $1 ]] || { mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1"; }; exec omarchy-launch-editor "$1"'
      root.host.exec(["bash", "-c", script, "bash", root.filtersFile, JSON.stringify(Files.DEFAULT_FILTERS, null, 2)])
      return { close: true }
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
