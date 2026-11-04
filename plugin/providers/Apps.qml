import QtQuick
import Quickshell
import Quickshell.Io

// Desktop applications. Reads Quickshell's DesktopEntries directly and
// applies the same hides Omarchy's launcher does (launcher.hides plus
// NoDisplay/Hidden/OnlyShowIn), so it does not depend on the shell's app
// library object, which the shell destroys when a plugin is reloaded.
Item {
  id: root

  property var host: null
  property string title: "Applications"
  property var items: []
  property var configuredHides: ({})
  property var desktopHides: ({})
  property var iconIndex: ({})
  property bool iconScanRunning: false

  readonly property string omarchyPath: root.host ? root.host.omarchyPath : Quickshell.env("OMARCHY_PATH")

  function start() {
    hidesFile.path = root.omarchyPath + "/default/omarchy/launcher.hides"
    scanHidden()
    scanIcons()
    rebuild()
  }

  function opened() {
    var lib = root.host ? root.host.appLibrary : null
    if (lib) lib.refreshIcons()
    scanIcons()
    // Rows keep the icon resolved at build time; the shell's index fills
    // asynchronously, so re-resolve once its rescan has had time to finish.
    iconRefreshTimer.restart()
  }

  // Own icon index, mirroring the shell's AppLibrary: the shell's app library
  // is often unavailable here (see above), and Qt's themed lookup can pick the
  // package icon in /usr/share over a user override in ~/.local/share/icons.
  // Earlier base dirs win; within one, scalable then the size closest to 256.
  function scanIcons() {
    if (!root.host || root.iconScanRunning) return
    root.iconScanRunning = true
    var cmd = [
      'dirs="$HOME/.icons ${XDG_DATA_HOME:-$HOME/.local/share}/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'i=0; for base in $dirs; do i=$((i+1));',
      '  [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) \\( -name "*.svg" -o -name "*.png" \\) -printf "$i\\t%p\\n" 2>/dev/null;',
      'done;',
      'find /usr/share/pixmaps -maxdepth 1 \\( -name "*.svg" -o -name "*.png" \\) -printf "999\\t%p\\n" 2>/dev/null'
    ].join(' ')
    root.host.capture(["bash", "-c", cmd], function(code, out) {
      root.iconScanRunning = false
      var best = ({})
      String(out || "").split("\n").forEach(function(line) {
        var tab = line.indexOf("\t")
        if (tab < 0) return
        var rank = parseInt(line.slice(0, tab), 10)
        var path = line.slice(tab + 1)
        var file = path.slice(path.lastIndexOf("/") + 1)
        var dot = file.lastIndexOf(".")
        var name = dot > 0 ? file.slice(0, dot) : file
        if (!name) return
        var score = rank * 100000 + root.iconSizeScore(path)
        var cur = best[name]
        if (!cur || score < cur.score) best[name] = { score: score, path: path }
      })
      var index = ({})
      for (var n in best) index[n] = best[n].path
      root.iconIndex = index
      root.refreshIconSources()
    })
  }

  function iconSizeScore(path) {
    if (path.slice(-4) === ".svg") return 0
    var m = /\/(\d+)x\d+(@\d+)?\//.exec(path)
    if (!m) return 5000
    return 1 + Math.abs(parseInt(m[1], 10) - 256)
  }

  function refreshIconSources() {
    var changed = false
    var rows = root.items.map(function(row) {
      var src = iconFor(row.iconName)
      if (src === row.iconSource) return row
      changed = true
      return Object.assign({}, row, { iconSource: src })
    })
    if (!changed) return
    root.items = rows
    if (root.host) root.host.changed()
  }

  function scanHidden() {
    var desktop = [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")]
      .filter(function(v) { return String(v || "").length > 0 }).join(":")
    var script = root.omarchyPath + "/shell/services/hidden-entries.sh"
    root.host.capture(["bash", script, desktop], function(code, out) {
      var hides = ({})
      String(out || "").split("\n").forEach(function(l) { var id = normalizeId(l); if (id) hides[id] = true })
      root.desktopHides = hides
      rebuild()
    })
  }

  function normalizeId(id) {
    var v = String(id || "").trim()
    return v.slice(-8) === ".desktop" ? v.slice(0, -8) : v
  }

  function iconFor(icon) {
    var lib = root.host ? root.host.appLibrary : null
    if (lib) return lib.iconSource(icon)
    var v = String(icon || "")
    if (!v) return Quickshell.iconPath("application-x-executable", true)
    if (v.charAt(0) === "/") return "file://" + v
    var found = root.iconIndex[v]
    if (found) return "file://" + found
    var themed = Quickshell.iconPath(v, true)
    return themed || Quickshell.iconPath("application-x-executable", true)
  }

  function rebuild() {
    var values = DesktopEntries.applications.values || []
    var rows = []
    var seen = ({})
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      var id = normalizeId(e.id)
      if (!id || seen[id] || e.noDisplay) continue
      if (root.configuredHides[id] || root.desktopHides[id]) continue
      seen[id] = true
      var keywords = []
      try { if (e.keywords) for (var k = 0; k < e.keywords.length; k++) keywords.push(String(e.keywords[k])) } catch (err) {}
      if (e.comment) keywords.push(String(e.comment))
      keywords.push(id)
      rows.push({
        id: id,
        title: String(e.name || id),
        subtitle: String(e.genericName || ""),
        keywords: keywords,
        iconName: String(e.icon || ""),
        iconSource: iconFor(e.icon),
        type: "Application",
        group: "apps",
        boost: 120,
        copy: id
      })
    }
    root.items = rows
    if (root.host) root.host.changed()
  }

  function actions(row) {
    return [
      { id: "open", title: "Open" },
      { id: "copy-id", title: "Copy Desktop ID" }
    ]
  }

  function run(row, actionId) {
    if (actionId === "copy-id") {
      root.host.copy(row.id)
      return { close: false, toast: "Copied " + row.id }
    }
    var lib = root.host.appLibrary
    if (lib) lib.launch(row.id, row.title)
    else root.host.exec(["uwsm-app", "--", "gtk-launch", row.id + ".desktop"])
    return { close: true }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { rebuildTimer.restart() }
  }

  Timer { id: rebuildTimer; interval: 300; onTriggered: root.rebuild() }
  Timer { id: iconRefreshTimer; interval: 1500; onTriggered: root.refreshIconSources() }

  FileView {
    id: hidesFile
    watchChanges: true
    printErrors: false
    onLoaded: {
      var hides = ({})
      String(text()).split("\n").forEach(function(l) {
        var v = l.replace(/#.*/, "").trim()
        if (v) hides[root.normalizeId(v)] = true
      })
      root.configuredHides = hides
      root.rebuild()
    }
    onFileChanged: reload()
  }
}
