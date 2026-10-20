import QtQuick
import Quickshell.Io
import "../core/Menu.js" as Menu

// Every Omarchy menu entry as a searchable command (docs/SPEC.md §3).
Item {
  id: root

  property var host: null
  property string title: "Omarchy"
  property var items: []

  readonly property string defaultPath: (root.host ? root.host.omarchyPath : "") + "/default/omarchy/omarchy-menu.jsonc"
  readonly property string userPath: (root.host ? root.host.home : "") + "/.config/omarchy/extensions/omarchy-menu.jsonc"

  property var defaultEntries: ({})
  property var userEntries: ({})
  property var entries: ({})
  property var providerEntries: ({})     // rows produced by runtime providers
  property var whenResults: ({})
  property var checkedResults: ({})
  property var disabledResults: ({})
  property double guardsAt: 0
  property bool guardsRunning: false

  // Runtime providers named by `provider:` in the menu file. Each lists
  // values and says which one is current.
  readonly property var runtimeProviders: ({
    "fonts": {
      list: "omarchy-font-list", current: "omarchy-font-current",
      action: function(v) { return "omarchy-font-set " + quote(v) }
    },
    "power-profiles": {
      list: "omarchy-powerprofiles-list", current: "powerprofilesctl get",
      action: function(v) { return "omarchy-powerprofiles-set autodetect " + quote(v) }
    }
  })

  function quote(v) { return "'" + String(v).replace(/'/g, "'\\''") + "'" }

  function start() {
    defaultFile.path = root.defaultPath
    userFile.path = root.userPath
  }

  function opened() {
    if (Date.now() - root.guardsAt > 2000) evaluateGuards()
  }

  function composeEntries() {
    var merged = Menu.merge([root.defaultEntries, root.userEntries])
    for (var id in root.providerEntries) merged[id] = root.providerEntries[id]
    root.entries = merged
  }

  function rebuildEntries() {
    composeEntries()
    rebuildRows()
    evaluateGuards()
    loadRuntimeProviders()
  }

  // Ids of the "apps" submenu and below: applications are listed by the apps
  // provider already.
  function skipped(e) {
    var cur = e
    var depth = 0
    while (cur && depth < 32) {
      if (cur.provider === "apps") return true
      cur = root.entries[cur.parent]
      depth++
    }
    return false
  }

  function rowFor(e) {
    var trail = Menu.trail(root.entries, e.id)
    var checked = e.checked && root.checkedResults[e.id] === true
    return {
      id: e.id,
      title: e.label + (checked ? "  ✓" : ""),
      subtitle: trail.length ? trail.join(" › ") : e.description,
      icon: e.icon,
      iconFont: e.iconFont,
      keywords: e.aliases.concat(e.description ? [e.description] : []).concat(trail),
      type: e.kind === "action" ? "Command" : "Menu",
      group: "commands",
      when: e.parent === "" ? "always" : "searching",
      disabled: !!(e.disabled && root.disabledResults[e.id] === true),
      boost: -25 * trail.length,
      checked: checked,
      copy: e.action || e.label
    }
  }

  function rebuildRows() {
    var hidden = Menu.hiddenIds(root.entries, root.whenResults)
    var rows = []
    var ordered = []
    for (var id in root.entries) ordered.push(root.entries[id])
    ordered.sort(function(a, b) { return a.order - b.order })
    for (var i = 0; i < ordered.length; i++) {
      var e = ordered[i]
      if (hidden[e.id] || skipped(e)) continue
      rows.push(rowFor(e))
    }
    root.items = rows
    if (root.host) root.host.changed()
  }

  function evaluateGuards() {
    if (root.guardsRunning) return
    var guards = []
    var refs = []
    for (var id in root.entries) {
      var e = root.entries[id]
      if (e.when) { guards.push(e.when); refs.push([id, "when"]) }
      if (e.checked) { guards.push(e.checked); refs.push([id, "checked"]) }
      if (e.disabled) { guards.push(e.disabled); refs.push([id, "disabled"]) }
    }
    if (!guards.length) return
    root.guardsRunning = true
    root.host.capture(["bash", "-lc", Menu.guardScript(guards)], function(code, out) {
      root.guardsRunning = false
      root.guardsAt = Date.now()
      var results = Menu.parseGuardOutput(out, guards.length)
      var w = ({}), c = ({}), d = ({})
      for (var i = 0; i < refs.length; i++) {
        var target = refs[i][1] === "when" ? w : (refs[i][1] === "checked" ? c : d)
        target[refs[i][0]] = results[i] === true
      }
      root.whenResults = w
      root.checkedResults = c
      root.disabledResults = d
      rebuildRows()
    }, 10000)
  }

  function loadRuntimeProviders() {
    for (var id in root.entries) {
      var e = root.entries[id]
      var spec = root.runtimeProviders[e.provider]
      if (!spec) continue
      ;(function(menuId, spec) {
        var script = "current=$(" + spec.current + " 2>/dev/null); printf '%s\\n' \"$current\"; " + spec.list + " 2>/dev/null"
        root.host.capture(["bash", "-lc", script], function(code, out) {
          var lines = String(out || "").split("\n")
          var current = lines.shift()
          var next = ({})
          for (var k in root.providerEntries) if (root.providerEntries[k].parent !== menuId) next[k] = root.providerEntries[k]
          var n = 0
          for (var i = 0; i < lines.length; i++) {
            var v = lines[i].trim()
            if (!v) continue
            var cid = menuId + "." + v.toLowerCase().replace(/[^a-z0-9]+/g, "-")
            next[cid] = {
              id: cid, parent: menuId, kind: "action", label: v + (v === current ? "  ✓" : ""), title: "",
              icon: root.entries[menuId].icon, iconFont: root.entries[menuId].iconFont, description: "",
              action: spec.action(v), target: "", provider: "", aliases: [], when: "", checked: "", disabled: "",
              order: 100000 + n++
            }
          }
          root.providerEntries = next
          composeEntries()
          rebuildRows()
        })
      })(id, spec)
    }
  }

  // Rows for a submenu: its children (shown) and deeper descendants (found
  // by search only).
  function submenuRows(menuId) {
    var hidden = Menu.hiddenIds(root.entries, root.whenResults)
    var rows = []
    var prefix = menuId + "."
    var ordered = []
    for (var id in root.entries) ordered.push(root.entries[id])
    ordered.sort(function(a, b) { return a.order - b.order })
    for (var i = 0; i < ordered.length; i++) {
      var e = ordered[i]
      if (hidden[e.id]) continue
      var under = e.parent === menuId || e.id.indexOf(prefix) === 0
      if (!under) continue
      var r = rowFor(e)
      r.when = e.parent === menuId ? "always" : "searching"
      if (e.parent === menuId) r.subtitle = e.description
      rows.push(r)
    }
    return rows
  }

  function actions(row) {
    var e = root.entries[row.id]
    if (!e) return []
    if (e.kind === "action") return [{ id: "run", title: "Run" }, { id: "copy-command", title: "Copy Command" }]
    return [{ id: "open", title: "Open Menu" }]
  }

  function run(row, actionId) {
    var e = root.entries[row.id]
    if (!e) return { close: false, toast: "This entry is gone" }
    if (actionId === "copy-command") {
      root.host.copy(e.action)
      return { close: false, toast: "Command copied" }
    }
    if (e.kind === "action") {
      if (row.disabled) return { close: false, toast: e.label + " is unavailable" }
      root.host.shell(e.action)
      return { close: true }
    }
    var menuId = e.kind === "link" ? e.target : e.id
    var m = root.entries[menuId]
    if (!m) return { close: false, toast: "Menu " + menuId + " not found" }
    return { close: false, push: { id: "omarchy:" + menuId, title: m.title || m.label, rows: submenuRows(menuId) } }
  }

  FileView {
    id: defaultFile
    watchChanges: true
    printErrors: false
    onLoaded: {
      var r = Menu.parseFile(text())
      if (r.error) console.warn("[omalaunch] " + root.defaultPath + ": " + r.error)
      root.defaultEntries = r.entries
      root.rebuildEntries()
    }
    onFileChanged: reload()
  }

  FileView {
    id: userFile
    watchChanges: true
    printErrors: false
    onLoaded: {
      var r = Menu.parseFile(text())
      if (r.error) console.warn("[omalaunch] " + root.userPath + ": " + r.error)
      root.userEntries = r.entries
      root.rebuildEntries()
    }
    onLoadFailed: { root.userEntries = ({}); root.rebuildEntries() }
    onFileChanged: reload()
  }
}
