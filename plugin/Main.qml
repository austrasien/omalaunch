import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "core/Rank.js" as Rank
import "core/State.js" as State
import "core/Sections.js" as Sections
import "services"
import "providers"
import "ui"

// omalaunch: a keyboard-first launcher for Omarchy (docs/SPEC.md).
//
// omarchy-shell loads this once (keepLoaded), injects `shell`, and calls
// open(payloadJson) / close(). The global shortcut and `qs ipc` route through
// show()/hide() so the shell's open/closed bookkeeping stays right.
Item {
  id: root

  readonly property string pluginId: "austraz.omalaunch"
  readonly property int keepStateMs: 90000

  // Injected by the shell's panel loader.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property bool started: false
  property double closedAt: 0
  property string query: ""
  property var stack: []               // pushed views: [{ id, title, rows }]
  property var sections: []
  property var flat: []
  property var itemsOnly: []           // flat minus headers
  property int selected: 0             // index into itemsOnly
  property string toastText: ""
  property bool actionPanelOpen: false
  property string promptMode: ""       // "" | "alias" | "hotkey"
  property var hotkeys: ({})           // row key -> combo, from `omalaunch hotkey`
  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/omalaunch"
  property var promptRow: null
  property int historyIndex: -1
  property string largeText: ""
  property bool previewOpen: false
  property var previewData: null
  property int previewSeq: 0
  readonly property string previewScript: String(Qt.resolvedUrl("services/preview.sh")).replace(/^file:\/\//, "")
  readonly property string previewCache: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omalaunch/preview"
  readonly property real zoom: store.state.zoom || 1
  readonly property var selectedRow: itemsOnly.length ? itemsOnly[Math.min(selected, itemsOnly.length - 1)].row : null
  readonly property var deps: ({ Rank: Rank, State: State })

  // ------------------------------------------------------------ services

  Exec { id: exec }
  Store { id: store }

  ProviderHost {
    id: host
    exec: exec
    launcher: root
    appLibrary: root.shell ? root.shell.appLibrary : null
    omarchyPath: root.omarchyPath
  }

  Apps { id: appsProvider }
  Omarchy { id: omarchyProvider }
  Scripts { id: scriptsProvider }
  Web { id: webProvider }
  ShellCommand { id: shellProvider }
  Builtin { id: builtinProvider; launcher: root }

  onShellChanged: if (root.shell) Qt.callLater(root.startOnce)
  Component.onCompleted: startTimer.start()

  // Outside omarchy-shell (or if injection is late) start anyway.
  Timer { id: startTimer; interval: 1500; onTriggered: root.startOnce() }

  function startOnce() {
    if (root.started) return
    root.started = true
    host.register("apps", appsProvider)
    host.register("omarchy", omarchyProvider)
    host.register("scripts", scriptsProvider)
    host.register("web", webProvider)
    host.register("shell", shellProvider)
    host.register("builtin", builtinProvider)
    host.loadUserPlugins()
  }

  function reloadPlugins() {
    host.loadUserPlugins()
  }

  // ------------------------------------------------------- open / close

  function open(payloadJson) {
    var payload = {}
    try { payload = payloadJson ? JSON.parse(payloadJson) : {} } catch (e) { payload = {} }
    if (Date.now() - root.closedAt > root.keepStateMs) resetView()
    if (typeof payload.query === "string") setQuery(payload.query)
    root.actionPanelOpen = false
    root.promptMode = ""
    root.historyIndex = -1
    root.opened = true
    host.opened()
    loadHotkeys()
    scheduleRebuild()
    window.focusSearch(true)
  }

  function close() {
    if (!root.opened) return
    root.opened = false
    root.closedAt = Date.now()
    root.actionPanelOpen = false
    root.promptMode = ""
    root.previewOpen = false
    store.flush()
  }

  function show(payloadJson) {
    if (root.shell && root.shell.summon(root.pluginId, payloadJson || "")) return
    open(payloadJson || "")
  }

  function hide() {
    if (root.shell && root.shell.hide(root.pluginId)) { close(); return }
    close()
  }

  function toggle() {
    if (root.opened) hide()
    else show("")
  }

  function resetView() {
    root.stack = []
    root.query = ""
    host.query("")
    root.selected = 0
  }

  // --------------------------------------------------------- the list

  function setQuery(text) {
    var t = String(text || "")
    if (t === root.query) return
    root.query = t
    root.selected = 0
    root.historyIndex = -1
    if (!root.stack.length) host.query(t)
    window.syncSearchText(t)
    scheduleRebuild()
  }

  property bool rebuildPending: false
  function scheduleRebuild() {
    if (root.rebuildPending) return
    root.rebuildPending = true
    Qt.callLater(root.rebuild)
  }

  function rebuild() {
    root.rebuildPending = false
    // Keep the selection across late provider replies only if the user moved it.
    var keepKey = root.selectedRow && root.selected > 0 ? root.selectedRow.key : ""
    var now = Date.now()
    var secs
    if (root.stack.length) {
      var top = root.stack[root.stack.length - 1]
      secs = Sections.submenuSections(top.rows, root.query, store.state, now, root.deps)
    } else {
      secs = Sections.rootSections(host.catalog(), host.dynamicList(), root.query, store.state, now, root.deps)
    }
    var flat = Sections.flatten(secs)
    var items = flat.filter(function(f) { return !f.header })
    root.sections = secs
    root.flat = flat
    root.itemsOnly = items
    var idx = 0
    if (keepKey && root.query === lastBuiltQuery) {
      for (var i = 0; i < items.length; i++) if (items[i].row.key === keepKey) { idx = i; break }
    }
    lastBuiltQuery = root.query
    root.selected = idx
  }
  property string lastBuiltQuery: ""

  Connections {
    target: host
    function onCatalogRevisionChanged() { root.scheduleRebuild() }
    function onDynamicRevisionChanged() { root.scheduleRebuild() }
  }
  Connections {
    target: store
    function onRevisionChanged() { root.scheduleRebuild() }
  }

  function move(delta) {
    var n = root.itemsOnly.length
    if (!n) return
    root.selected = (root.selected + delta + n) % n
  }

  function jumpSection(delta) {
    var items = root.itemsOnly
    if (!items.length) return
    var cur = items[root.selected].section
    var i = root.selected
    if (delta > 0) {
      while (i < items.length && items[i].section === cur) i++
      root.selected = i < items.length ? i : 0
    } else {
      while (i > 0 && items[i - 1].section === cur) i--
      if (i === 0) { root.selected = 0; return }
      var prev = items[i - 1].section
      while (i > 0 && items[i - 1].section === prev) i--
      root.selected = i
    }
  }

  function historyStep(delta) {
    var h = store.state.history
    if (!h.length) return false
    var next = Math.max(-1, Math.min(h.length - 1, root.historyIndex + delta))
    root.historyIndex = next
    var text = next < 0 ? "" : h[next]
    root.query = text
    if (!root.stack.length) host.query(text)
    window.syncSearchText(text)
    scheduleRebuild()
    return true
  }

  function back() {
    if (root.actionPanelOpen) { root.actionPanelOpen = false; window.focusSearch(false); return }
    if (root.previewOpen) { root.previewOpen = false; return }
    if (root.promptMode) { root.promptMode = ""; window.syncSearchText(root.query); return }
    if (root.stack.length) { popView(); return }
    if (root.query) { setQuery(""); return }
    hide()
  }

  function backToRoot() {
    root.actionPanelOpen = false
    root.promptMode = ""
    root.stack = []
    setQuery("")
    host.query("")
    scheduleRebuild()
  }

  function pushView(view) {
    root.stack = root.stack.concat([view])
    root.query = ""
    window.syncSearchText("")
    root.selected = 0
    scheduleRebuild()
  }

  function popView() {
    root.stack = root.stack.slice(0, -1)
    root.query = ""
    window.syncSearchText("")
    if (!root.stack.length) host.query("")
    scheduleRebuild()
  }

  readonly property string breadcrumb: root.stack.map(function(v) { return v.title }).join(" › ")

  // ----------------------------------------------------------- actions

  function isCatalogRow(row) { return row && !row.dynamic && !row.ephemeral }

  function actionsFor(row) {
    if (!row) return []
    var list = host.actionsFor(row).map(function(a) { return { id: a.id, title: a.title, shortcut: a.shortcut || "", own: true } })
    var keys = ["↵", "⌃↵", "⌃⇧↵"]
    for (var i = 0; i < list.length && i < 3; i++) if (!list[i].shortcut) list[i].shortcut = keys[i]
    if (row.dynamic && row.copy !== undefined) list.push({ id: "omalaunch.copy", title: "Copy", shortcut: "⌃⇧C" })
    list.push({ id: "omalaunch.large", title: "Show in Large Type", shortcut: "⌃L" })
    if (!isCatalogRow(row)) return list
    var fav = State.isFavorite(store.state, row.key)
    list.push({ id: "omalaunch.favorite", title: fav ? "Remove from Favorites" : "Add to Favorites", shortcut: "⌃⇧F" })
    if (fav) {
      list.push({ id: "omalaunch.fav-up", title: "Move Favorite Up", shortcut: "⌃⌥↑" })
      list.push({ id: "omalaunch.fav-down", title: "Move Favorite Down", shortcut: "⌃⌥↓" })
    }
    list.push({ id: "omalaunch.alias", title: row.alias ? "Change Alias (" + row.alias + ")" : "Set Alias", shortcut: "⌃⇧A" })
    var hk = root.hotkeys[row.key]
    list.push({ id: "omalaunch.hotkey", title: hk ? "Change Hotkey (" + hk + ")" : "Set Hotkey", shortcut: "⌃⇧H" })
    list.push({ id: "omalaunch.copy", title: "Copy", shortcut: "⌃⇧C" })
    list.push({ id: "omalaunch.reset", title: "Reset Ranking", shortcut: "" })
    list.push({ id: "omalaunch.disable", title: "Disable Item", shortcut: "⌥⇧D" })
    return list
  }

  // Run the n-th action (0 = primary) of a row.
  function runIndex(row, index) {
    var list = actionsFor(row)
    if (!list.length) return
    runAction(row, list[Math.min(index, list.length - 1)])
  }

  function runAction(row, action) {
    if (!row || !action) return
    root.actionPanelOpen = false
    switch (action.id) {
    case "omalaunch.favorite":
      var added = false
      store.update(function(s) { added = State.toggleFavorite(s, row.key) })
      toast(added ? "Added to Favorites" : "Removed from Favorites")
      return
    case "omalaunch.fav-up": store.update(function(s) { State.moveFavorite(s, row.key, -1) }); return
    case "omalaunch.fav-down": store.update(function(s) { State.moveFavorite(s, row.key, 1) }); return
    case "omalaunch.alias": beginAlias(row); return
    case "omalaunch.hotkey": beginHotkey(row); return
    case "omalaunch.copy":
      exec.detached(["wl-copy", "--", String(row.copy !== undefined && row.copy !== "" ? row.copy : row.title)])
      toast("Copied")
      return
    case "omalaunch.large":
      showLargeType(row.copy !== undefined && row.copy !== "" ? row.copy : row.title)
      return
    case "omalaunch.reset": store.update(function(s) { State.resetRanking(s, row.key) }); toast("Ranking reset"); return
    case "omalaunch.disable":
      store.update(function(s) { State.setDisabled(s, row.key, true) })
      toast("Disabled " + row.title + " (restore from “Show Disabled Items”)")
      return
    }
    if (row.disabled) { toast(row.title + " is unavailable"); return }
    var q = root.query
    var outcome = host.run(row, action.id, { query: q, alias: row.alias || "" })
    if (isCatalogRow(row) && action.own) {
      store.update(function(s) { State.recordUse(s, row.key, root.stack.length ? "" : q, Date.now()); State.pushHistory(s, q) })
    }
    if (outcome.push) {
      pushView({ id: outcome.push.id, title: outcome.push.title, rows: host.stampAll(row.provider, outcome.push.rows) })
    }
    if (outcome.toast) toast(outcome.toast)
    if (outcome.close) hide()
  }

  function runOrdinal(n) {
    if (n < root.itemsOnly.length) runIndex(root.itemsOnly[n].row, 0)
  }

  // Look a row up by key across the catalog (for `omalaunch run <key>`).
  function runKey(key) {
    var rows = host.catalog()
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].key === key) {
        var d = {}
        for (var k in rows[i]) d[k] = rows[i][k]
        d.alias = store.state.aliases[key] || ""
        runIndex(d, 0)
        return "ok"
      }
    }
    return "unknown"
  }

  function beginAlias(row) {
    root.promptRow = row
    root.promptMode = "alias"
    window.syncSearchText(row.alias || "")
    window.focusSearch(true)
  }

  function beginHotkey(row) {
    root.promptRow = row
    root.promptMode = "hotkey"
    window.syncSearchText(root.hotkeys[row.key] || "")
    window.focusSearch(true)
  }

  function loadHotkeys() {
    exec.capture(["cat", Quickshell.env("HOME") + "/.local/state/omalaunch/hotkeys.tsv"], function(code, out) {
      var map = ({})
      String(out || "").split("\n").forEach(function(line) {
        var f = line.split("\t")
        if (f.length >= 2 && f[0] && f[1]) map[f[1]] = f[0]
      })
      root.hotkeys = map
    })
  }

  // `omalaunch hotkey` validates the keys, checks Hyprland for conflicts
  // and rewrites the bindings file; its last line is the toast.
  function saveHotkey(row, combo) {
    var argv = String(combo).trim() ? [root.cli, "hotkey", "set", String(combo).trim(), row.key, row.title] : [root.cli, "hotkey", "unset", row.key]
    exec.capture(argv, function(code, out, err) {
      var msg = String((code === 0 ? out : err) || "").trim().split("\n").pop().replace(/^omalaunch: /, "")
      toast(msg || (code === 0 ? "Hotkey saved" : "Could not save the hotkey"))
      loadHotkeys()
    }, 10000)
  }

  function commitPrompt(text) {
    if (root.promptMode === "hotkey" && root.promptRow) saveHotkey(root.promptRow, text)
    if (root.promptMode === "alias" && root.promptRow) {
      var key = root.promptRow.key
      store.update(function(s) { State.setAlias(s, key, text) })
      toast(String(text).trim() ? "Alias saved" : "Alias removed")
    }
    root.promptMode = ""
    root.promptRow = null
    window.syncSearchText(root.query)
  }

  // ------------------------------------------------------- quick look

  function togglePreview() {
    root.previewOpen = !root.previewOpen
    if (root.previewOpen) updatePreview()
  }

  onSelectedRowChanged: if (root.previewOpen) previewTimer.restart()
  Timer { id: previewTimer; interval: 70; onTriggered: root.updatePreview() }

  // Rows preview `previewText`, else the file at `previewPath` / `path`.
  function updatePreview() {
    var row = root.selectedRow
    var seq = ++root.previewSeq
    if (!row) { root.previewData = { kind: "none" }; return }
    if (row.previewText !== undefined && row.previewText !== "") {
      root.previewData = { kind: "text", name: row.title, text: String(row.previewText), size: String(row.previewText).length, mime: "text/plain" }
      return
    }
    var path = row.previewPath || row.path || ""
    if (!path) { root.previewData = { kind: "none", name: row.title }; return }
    root.previewData = { kind: "loading", name: path.slice(path.lastIndexOf("/") + 1) }
    exec.capture(["bash", root.previewScript, path, root.previewCache], function(code, out) {
      if (seq !== root.previewSeq) return
      try { root.previewData = JSON.parse(out) } catch (e) { root.previewData = { kind: "info", name: path.slice(path.lastIndexOf("/") + 1) } }
    }, 15000)
  }

  function showLargeType(text) {
    var t = String(text || "").trim()
    if (!t) { closeLargeType(); return }
    hide()
    root.largeText = t
  }

  function closeLargeType() { root.largeText = "" }

  function setZoom(z) {
    store.update(function(s) { s.zoom = Math.max(0.7, Math.min(1.6, Math.round(z * 10) / 10)) })
  }

  function toast(text) {
    root.toastText = String(text)
    toastTimer.restart()
  }

  Timer { id: toastTimer; interval: 2600; onTriggered: root.toastText = "" }

  // Rows for the "Show Disabled Items" view.
  function disabledRows() {
    var rows = []
    var catalog = host.catalog()
    var titles = ({})
    for (var i = 0; i < catalog.length; i++) titles[catalog[i].key] = catalog[i]
    for (var key in store.state.disabled) {
      var c = titles[key]
      rows.push({ id: "restore:" + key, title: c ? c.title : key, subtitle: c ? (c.subtitle || key) : key, icon: c ? c.icon : "", iconSource: c ? c.iconSource : "", iconFont: c ? c.iconFont : "", type: "Disabled", ephemeral: true, target: key })
    }
    return rows
  }

  function enableKey(key) {
    store.update(function(s) { State.setDisabled(s, key, false) })
    if (root.stack.length && root.stack[root.stack.length - 1].id === "builtin:disabled") {
      var top = root.stack[root.stack.length - 1]
      var next = root.stack.slice(0, -1)
      next.push({ id: top.id, title: top.title, rows: host.stampAll("builtin", disabledRows()) })
      root.stack = next
      scheduleRebuild()
    }
  }

  function errorRows() {
    return host.loadErrors.map(function(e, i) { return { id: "error:" + i, title: e.dir.split("/").pop(), subtitle: e.error, icon: "\uf071", type: "Error", ephemeral: true, copy: e.dir + ": " + e.error } })
  }

  // -------------------------------------------------------------- ui

  LauncherWindow {
    id: window
    launcher: root
    shown: root.opened
    screen: {
      var name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
      var screens = Quickshell.screens
      for (var i = 0; i < screens.length; i++) if (screens[i].name === name) return screens[i]
      return screens.length ? screens[0] : null
    }
  }

  LargeType {
    launcher: root
    text: root.largeText
    screen: window.screen
  }

  // ------------------------------------------------------- entry points

  GlobalShortcut {
    appid: "omalaunch"
    name: "toggle"
    description: "Toggle omalaunch"
    onPressed: root.toggle()
  }

  IpcHandler {
    target: "omalaunch"

    function toggle(): string { root.toggle(); return root.opened ? "shown" : "hidden" }
    function show(): string { root.show(""); return "shown" }
    function hide(): string { root.hide(); return "hidden" }
    function isOpen(): string { return root.opened ? "true" : "false" }
    function ping(): string { return root.started ? "ok" : "starting" }
    function query(text: string): string { root.show(JSON.stringify({ query: text })); return "shown" }
    function run(key: string): string { return root.runKey(key) }
    function quicklook(): string { root.togglePreview(); return root.previewOpen ? "open" : "closed" }
    function large(text: string): string { root.showLargeType(text); return "ok" }
    function reload(): string { root.reloadPlugins(); return "ok" }
    function providers(): string {
      return JSON.stringify(host.providers.map(function(p) { return { id: p.id, builtin: p.builtin, items: (p.object.items || []).length } }))
    }
    function errors(): string { return JSON.stringify(host.loadErrors) }
    function debug(): string { return JSON.stringify({ shell: !!root.shell, appLibrary: !!(root.shell && root.shell.appLibrary), hostLib: !!host.appLibrary }) }
    // Send a query to the providers without opening the launcher; read the
    // rows back with search() once they answer (testing).
    function probe(text: string): string {
      if (root.opened) return "busy"
      host.query(text)
      return "ok"
    }
    // Rows the list shows for a query, as text (testing and scripting).
    function search(text: string): string {
      var secs = Sections.rootSections(host.catalog(), host.dynamicList(), text, store.state, Date.now(), root.deps)
      return secs.map(function(s) { return "## " + s.title + "\n" + s.rows.map(function(r) { return r.key + "\t" + r.title + (r.subtitle ? "\t" + r.subtitle : "") }).join("\n") }).join("\n")
    }
  }
}
