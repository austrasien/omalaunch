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

  // Injected by the shell's panel loader.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property double openedAt: 0
  property bool started: false
  property string query: ""
  property string lastQuery: ""
  property var stack: []               // pushed views: [{ id, title, rows }]
  property var sections: []
  property var flat: []
  property var itemsOnly: []           // flat minus headers
  property int selected: 0             // index into itemsOnly
  property string toastText: ""
  property bool actionPanelOpen: false
  property string promptMode: ""       // "" | "alias" | "hotkey" | "input"
  property string promptLabel: ""
  property var promptCallback: null
  property var hotkeys: ({})           // row key -> combo, from `omalaunch hotkey`
  readonly property string cli: Quickshell.env("HOME") + "/.local/bin/omalaunch"
  property var promptRow: null
  property int historyIndex: -1
  property string largeText: ""
  property var answer: null            // see ProviderHost showAnswer()
  property bool previewOpen: false
  property string viewMode: "auto"     // "auto" | "list" | "grid" (Ctrl+G)
  property bool gridActive: false
  property var thumbs: ({})            // file path -> thumbnail path ("" when none)
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
    root.openedAt = Date.now()
    resetView()
    // Reopen on the last search, fully selected: typing replaces it.
    setQuery(typeof payload.query === "string" ? payload.query : root.lastQuery)
    root.actionPanelOpen = false
    root.promptMode = ""
    root.historyIndex = -1
    root.opened = true
    refreshTimer.restart()
    scheduleRebuild()
    window.focusSearch(true)
  }

  function close() {
    if (!root.opened) return
    root.lastQuery = root.stack.length ? "" : root.query
    root.opened = false
    if (root.answer) closeAnswer()
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
    root.viewMode = "auto"
    root.stack = []
    root.query = ""
    window.syncSearchText("")
    host.query("")
    root.selected = 0
  }

  // --------------------------------------------------------- the list

  function setQuery(text) {
    var t = String(text || "")
    if (t === root.query) return
    if (root.answer) closeAnswer()
    root.query = t
    root.selected = 0
    root.historyIndex = -1
    if (!root.stack.length) host.query(t)
    window.syncSearchText(t)
    scheduleRebuild()
  }

  // Ranking the catalog takes tens of milliseconds in the QML JS engine and
  // each query-provider reply rebuilds the list, so the ranked rows are kept
  // until the query, the catalog or the user's state changes.
  property string resultsKey: ""
  property var resultsCache: null

  function cachedResults(now) {
    var q = root.query.trim()
    if (!q) return null
    var key = [q, host.catalogRevision, store.revision, root.openedAt].join("\u0000")
    if (key !== root.resultsKey) {
      root.resultsCache = Sections.searchResults(host.catalog(), q, store.state, now, root.deps)
      root.resultsKey = key
    }
    return root.resultsCache
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
      secs = Sections.rootSections(host.catalog(), host.dynamicList(), root.query, store.state, now, root.deps, cachedResults(now))
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
    root.gridActive = root.viewMode === "grid" || (root.viewMode === "auto" && wantsGrid(items))
  }

  // ----------------------------------------------------------- grid view

  readonly property int gridColumns: 5
  readonly property var tileExtensions: /\.(png|jpe?g|gif|webp|svg|bmp|heic|avif|tiff?|pdf|mp4|mkv|mov|webm|avi|pptx?|key|odp)$/i

  function isTile(row) {
    if (!row) return false
    if (row.emoji || row.tile) return true
    if (row.iconSource && row.type === "Image") return true
    var p = row.previewPath || row.path || ""
    return !!p && root.tileExtensions.test(p)
  }

  // Images, emojis and the like show as a grid when they make up most of
  // the results.
  function wantsGrid(items) {
    if (items.length < 4) return false
    var tiles = 0
    for (var i = 0; i < items.length; i++) if (isTile(items[i].row)) tiles++
    return tiles / items.length >= 0.6
  }

  function toggleGrid() {
    root.viewMode = root.gridActive ? "list" : "grid"
    root.gridActive = !root.gridActive
  }

  // A small thumbnail for a file (cached for the session).
  function thumbnail(path, callback) {
    if (root.thumbs[path] !== undefined) { callback(root.thumbs[path]); return }
    exec.capture(["bash", root.previewScript, path, root.previewCache, "320"], function(code, out) {
      var image = ""
      try { var d = JSON.parse(out); if (d.kind === "image") image = d.image } catch (e) {}
      var next = root.thumbs
      next[path] = image
      root.thumbs = next
      callback(image)
    }, 30000)
  }
  property string lastBuiltQuery: ""

  // Providers refresh only once the open fade (Hyprland layersIn, 0.4 s) is
  // over: their replies each rebuild the list, and a dozen rebuilds on the
  // shell's thread during the fade leave Hyprland nothing new to animate.
  Timer {
    id: refreshTimer
    interval: 450
    onTriggered: if (root.opened) { host.opened(); root.loadHotkeys() }
  }

  // Provider replies arrive one event-loop turn apart; gather them so they
  // cost one rebuild instead of one each.
  Timer {
    id: replyTimer
    interval: 50
    onTriggered: root.scheduleRebuild()
  }
  function scheduleReplyRebuild() {
    if (!replyTimer.running) replyTimer.start()
  }

  Connections {
    target: host
    function onCatalogRevisionChanged() { root.scheduleReplyRebuild() }
    function onDynamicRevisionChanged() { root.scheduleReplyRebuild() }
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
    if (root.answer) { closeAnswer(); return }
    if (root.previewOpen) { root.previewOpen = false; return }
    if (root.promptMode) { root.promptMode = ""; window.syncSearchText(root.query); return }
    if (root.stack.length) { popView(); return }
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

  // A plugin's question (host.ask): the answer goes to its callback.
  function askInput(label, callback, initial) {
    root.promptLabel = label
    root.promptCallback = callback
    root.promptRow = null
    root.promptMode = "input"
    window.syncSearchText(initial !== undefined ? String(initial) : "")
    window.focusSearch(true)
  }

  function commitPrompt(text) {
    if (root.promptMode === "input") {
      var cb = root.promptCallback
      root.promptMode = ""
      root.promptCallback = null
      window.syncSearchText(root.query)
      if (typeof cb === "function") {
        try { cb(String(text)) } catch (e) { console.warn("[omalaunch] ask() callback threw:", e) }
      }
      return
    }
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

  // ----------------------------------------------------------- answers

  function showAnswer(providerId, a) {
    var next = {}
    for (var k in a) next[k] = a[k]
    next.provider = providerId
    root.answer = next
    root.actionPanelOpen = false
  }

  function updateAnswer(providerId, patch) {
    if (!root.answer || root.answer.provider !== providerId) return
    var next = {}
    for (var k in root.answer) next[k] = root.answer[k]
    for (var j in patch) next[j] = patch[j]
    root.answer = next
  }

  function copyText(text) {
    exec.detached(["wl-copy", "--", String(text)])
    toast("Copied")
  }

  function closeAnswer() {
    var a = root.answer
    root.answer = null
    var p = a ? host.providerById(a.provider) : null
    if (p && p.object && typeof p.object.answerClosed === "function") {
      try { p.object.answerClosed(a) } catch (e) { console.warn("[omalaunch] answerClosed() threw:", e) }
    }
  }

  // Enter (0), Ctrl+Enter (1), Ctrl+Shift+Enter (2) on the answer.
  function answerAction(index) {
    var a = root.answer
    if (!a || !a.actions || !a.actions.length) return
    var act = a.actions[Math.min(index, a.actions.length - 1)]
    var row = {}
    for (var k in a) row[k] = a[k]
    row.id = "answer"
    var outcome = host.run(row, act.id, { query: root.query })
    if (outcome.toast) toast(outcome.toast)
    if (outcome.close) { root.answer = null; hide() }
  }

  // ------------------------------------------------------- quick look

  // Whether Quick Look has something to show for a row.
  function canPreview(row) {
    if (!row) return false
    return !!(row.previewText || row.previewPath || row.path) || host.hasPreview(row)
  }

  function togglePreview() {
    root.previewOpen = !root.previewOpen
    root.previewData = null
    if (root.previewOpen) updatePreview()
  }

  onSelectedRowChanged: if (root.previewOpen) previewTimer.restart()
  Timer { id: previewTimer; interval: 70; onTriggered: root.updatePreview() }

  // Rows preview `previewText`, else the file at `previewPath` / `path`.
  function updatePreview() {
    var row = root.selectedRow
    var seq = ++root.previewSeq
    if (!row) { root.previewData = { kind: "none" }; return }
    if (host.previewFor(row, function(data) { if (seq === root.previewSeq) root.previewData = data })) {
      if (!root.previewData) root.previewData = { kind: "loading", name: row.title }
      return
    }
    if (row.previewText !== undefined && row.previewText !== "") {
      root.previewData = { kind: "text", name: row.title, text: String(row.previewText), size: String(row.previewText).length, mime: "text/plain" }
      return
    }
    var path = row.previewPath || row.path || ""
    if (!path) { root.previewData = { kind: "none", name: row.title }; return }
    // Keep showing the previous file until the new one is ready, so the pane
    // does not flicker between sizes.
    if (!root.previewData) root.previewData = { kind: "loading", name: path.slice(path.lastIndexOf("/") + 1) }
    exec.capture(["bash", root.previewScript, path, root.previewCache], function(code, out) {
      if (seq !== root.previewSeq) return
      try { root.previewData = JSON.parse(out) } catch (e) { root.previewData = { kind: "info", name: path.slice(path.lastIndexOf("/") + 1) } }
    }, 30000)
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
    // Testing: ask the claude plugin directly, then read the answer view.
    function askClaude(question: string): string {
      var p = host.providerById("claude")
      if (!p || typeof p.object.ask !== "function") return "no claude plugin"
      p.object.ask(question, false)
      return "asked"
    }
    function answerState(): string { return JSON.stringify(root.answer) }
    function grid(): string { root.toggleGrid(); return root.gridActive ? "grid" : "list" }
    function quicklook(): string { root.togglePreview(); return root.previewOpen ? "open" : "closed" }
    function large(text: string): string { root.showLargeType(text); return "ok" }
    function reload(): string { root.reloadPlugins(); return "ok" }
    function providers(): string {
      return JSON.stringify(host.providers.map(function(p) { return { id: p.id, builtin: p.builtin, items: (p.object.items || []).length } }))
    }
    function errors(): string { return JSON.stringify(host.loadErrors) }
    function debug(): string {
      return JSON.stringify({ shell: !!root.shell, appLibrary: !!(root.shell && root.shell.appLibrary), hostLib: !!host.appLibrary,
        sizes: { title: window.titleSize, detail: window.detailSize, caption: window.captionSize, base: window.fontSize, zoom: window.z }, muted: String(window.muted) })
    }
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
