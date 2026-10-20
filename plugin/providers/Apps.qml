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

  readonly property string omarchyPath: root.host ? root.host.omarchyPath : Quickshell.env("OMARCHY_PATH")

  function start() {
    hidesFile.path = root.omarchyPath + "/default/omarchy/launcher.hides"
    scanHidden()
    rebuild()
  }

  function opened() {
    var lib = root.host ? root.host.appLibrary : null
    if (lib) lib.refreshIcons()
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
