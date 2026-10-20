import QtQuick
import Quickshell
import Quickshell.Io

// Loads providers and fans queries out to them (docs/PLUGINS.md).
//
// Built-in providers are declared by Main.qml and registered with
// `register()`. User plugins are discovered under
// ~/.config/omalaunch/plugins/<dir>/manifest.json and created from their
// QML entry point.
Item {
  id: root

  required property var exec
  required property var launcher        // Main.qml: close(), toast(), setQuery(), refresh()
  property var appLibrary: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginsDir: home + "/.config/omalaunch/plugins"
  readonly property string dataRoot: home + "/.local/share/omalaunch/plugins"

  property var providers: []            // [{ id, object, builtin, manifest }]
  property int catalogRevision: 0
  property var dynamicSections: ({})    // providerId -> { title, placement, order, rows }
  property int dynamicRevision: 0
  property var loadErrors: []
  property int generation: 0
  property int querySeq: 0
  property string lastQuery: ""

  signal catalogChanged()

  // ---------------------------------------------------------- registration

  function register(id, object, manifest) {
    var list = root.providers.filter(function(p) { return p.id !== id })
    list.push({ id: id, object: object, builtin: !manifest, manifest: manifest || null })
    root.providers = list
    object.host = apiFor(id)
    if (typeof object.start === "function") {
      try { object.start() } catch (e) { console.warn("[omalaunch] provider " + id + " start() threw:", e) }
    }
    changed()
  }

  function unregisterUserPlugins() {
    var keep = []
    for (var i = 0; i < root.providers.length; i++) {
      var p = root.providers[i]
      if (p.builtin) keep.push(p)
      else if (p.object) p.object.destroy()
    }
    root.providers = keep
    var dyn = ({})
    for (var k in root.dynamicSections) if (providerById(k)) dyn[k] = root.dynamicSections[k]
    root.dynamicSections = dyn
    changed()
  }

  function providerById(id) {
    for (var i = 0; i < root.providers.length; i++) if (root.providers[i].id === id) return root.providers[i]
    return null
  }

  function changed() {
    root.catalogRevision += 1
    root.catalogChanged()
  }

  // ------------------------------------------------------------- catalog

  // Every catalog row, keyed "<provider>:<row id>".
  function catalog() {
    var out = []
    for (var i = 0; i < root.providers.length; i++) {
      var p = root.providers[i]
      var items = p.object && p.object.items ? p.object.items : []
      for (var j = 0; j < items.length; j++) out.push(stamp(p.id, items[j]))
    }
    return out
  }

  function stamp(providerId, row) {
    var r = {}
    for (var k in row) r[k] = row[k]
    r.provider = providerId
    r.key = providerId + ":" + row.id
    if (!r.group) r.group = "commands"
    if (!r.visibility) r.visibility = "always"
    return r
  }

  function stampAll(providerId, rows) {
    return (rows || []).map(function(r) { return stamp(providerId, r) })
  }

  // --------------------------------------------------------------- query

  function query(text) {
    root.lastQuery = String(text || "")
    root.querySeq += 1
    if (!root.lastQuery.trim()) {
      root.dynamicSections = ({})
      root.dynamicRevision += 1
      queryTimer.stop()
      return
    }
    queryTimer.restart()
  }

  function dispatchQuery() {
    var seq = root.querySeq
    var text = root.lastQuery
    for (var i = 0; i < root.providers.length; i++) {
      var p = root.providers[i]
      if (!p.object || typeof p.object.query !== "function") continue
      ;(function(provider) {
        var reply = function(rows, placement) {
          if (seq !== root.querySeq) return
          deliver(provider, rows, placement)
        }
        try {
          var direct = provider.object.query(text, reply)
          if (Array.isArray(direct)) reply(direct)
        } catch (e) {
          console.warn("[omalaunch] provider " + provider.id + " query() threw:", e)
        }
      })(p)
    }
  }

  function deliver(provider, rows, placement) {
    var next = ({})
    for (var k in root.dynamicSections) next[k] = root.dynamicSections[k]
    var o = provider.object
    next[provider.id] = {
      id: "dyn:" + provider.id,
      title: o.sectionTitle || o.title || provider.id,
      placement: placement || o.placement || "bottom",
      order: o.order !== undefined ? o.order : 50,
      rows: stampAll(provider.id, rows).map(function(r) { r.dynamic = true; return r })
    }
    root.dynamicSections = next
    root.dynamicRevision += 1
  }

  function dynamicList() {
    var out = []
    for (var k in root.dynamicSections) out.push(root.dynamicSections[k])
    return out
  }

  Timer {
    id: queryTimer
    interval: 110
    onTriggered: root.dispatchQuery()
  }

  // --------------------------------------------------------- lifecycle

  function opened() {
    for (var i = 0; i < root.providers.length; i++) {
      var o = root.providers[i].object
      if (o && typeof o.opened === "function") {
        try { o.opened() } catch (e) { console.warn("[omalaunch] provider " + root.providers[i].id + " opened() threw:", e) }
      }
    }
  }

  // Actions for a row. The provider's own come first; the first is primary.
  function actionsFor(row) {
    var p = providerById(row.provider)
    var own = []
    if (p && p.object && typeof p.object.actions === "function") {
      try { own = p.object.actions(row) || [] } catch (e) { console.warn("[omalaunch] actions() threw:", e) }
    }
    if (!own.length) own = [{ id: "run", title: "Open" }]
    return own
  }

  // Returns the provider's outcome: { close?, toast?, push? }.
  function run(row, actionId, ctx) {
    var p = providerById(row.provider)
    if (!p || !p.object || typeof p.object.run !== "function") return { close: false, toast: "Nothing to run" }
    try {
      return p.object.run(row, actionId, ctx || {}) || { close: true }
    } catch (e) {
      console.warn("[omalaunch] provider " + row.provider + " run() threw:", e)
      return { close: false, toast: "Error: " + e }
    }
  }

  // ------------------------------------------------------- user plugins

  function loadUserPlugins() {
    root.generation += 1
    unregisterUserPlugins()
    root.loadErrors = []
    // Quickshell caches QML and JS by file path for the life of the shell, so
    // each load reaches the plugins through a fresh directory of symlinks.
    var runDir = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omalaunch/load-" + Date.now()
    var script = 'shopt -s nullglob; base=$(dirname "$2"); rm -rf "$base"/load-*; mkdir -p "$2"; '
      + 'for f in "$1"/*/manifest.json; do d=$(dirname "$f"); n=$(basename "$d"); ln -s "$(readlink -f "$d")" "$2/$n"; '
      + 'printf "%s\\x1f%s\\x1f" "$d" "$2/$n"; cat "$f"; printf "\\x1e"; done'
    root.exec.capture(["bash", "-c", script, "bash", root.pluginsDir, runDir], function(code, out) {
      var chunks = String(out || "").split("\x1e")
      for (var i = 0; i < chunks.length; i++) {
        var parts = chunks[i].split("\x1f")
        if (parts.length < 3) continue
        loadOne(parts[0].trim(), parts[1], parts[2])
      }
    })
  }

  function loadOne(dir, loadDir, manifestText) {
    var manifest
    try { manifest = JSON.parse(manifestText) } catch (e) { return fail(dir, "manifest.json is not valid JSON") }
    var id = String(manifest.id || "")
    if (!/^[a-z0-9][a-z0-9._-]*$/.test(id)) return fail(dir, "manifest id must be lower-case letters, digits, . _ -")
    if (providerById(id)) return fail(dir, "id " + id + " is already taken")
    var entry = String(manifest.entry || "Provider.qml")
    var url = "file://" + loadDir + "/" + entry
    var component = Qt.createComponent(url)
    var finish = function() {
      if (component.status === Component.Error) return fail(dir, component.errorString())
      var obj = component.createObject(root, {})
      if (!obj) return fail(dir, "could not create the provider object")
      if ("pluginDir" in obj) obj.pluginDir = dir
      if (!("host" in obj)) { obj.destroy(); return fail(dir, "the provider must declare `property var host`") }
      register(id, obj, manifest)
    }
    if (component.status === Component.Loading) component.statusChanged.connect(function() { if (component.status !== Component.Loading) finish() })
    else finish()
  }

  function fail(dir, message) {
    console.warn("[omalaunch] plugin " + dir + ": " + message)
    root.loadErrors = root.loadErrors.concat([{ dir: dir, error: message }])
  }

  // --------------------------------------------------------------- API

  function apiFor(id) {
    return apiComponent.createObject(root, { providerId: id })
  }

  Component {
    id: apiComponent

    QtObject {
      property string providerId: ""
      readonly property var appLibrary: root.appLibrary
      readonly property string omarchyPath: root.omarchyPath
      readonly property string home: root.home
      readonly property string dataDir: root.dataRoot + "/" + providerId

      function exec(argv) { root.exec.detached(argv) }
      function shell(command) { root.exec.shell(command) }
      function capture(argv, callback, timeoutMs) { return root.exec.capture(argv, callback, timeoutMs) }
      function copy(text) { root.exec.detached(["wl-copy", "--", String(text)]) }
      function browse(url) { root.exec.detached(["omarchy-launch-browser", String(url)]) }
      function notify(title, body) { root.exec.detached(["notify-send", "-a", "omalaunch", String(title), String(body || "")]) }
      // A floating terminal running `command` in bash; waits for a key when hold is true.
      function terminal(command, hold) {
        var cmd = String(command) + (hold === false ? "" : '; echo; read -rsn1 -p "Press any key to close"')
        root.exec.detached(["setsid", "uwsm-app", "--", "xdg-terminal-exec", "--app-id=TUI.float", "--title=omalaunch", "-e", "bash", "-lc", cmd])
      }
      function toast(text) { root.launcher.toast(String(text)) }
      // Ask for one line of text in the search field; callback(text) on
      // Enter, nothing on Esc.
      function ask(label, callback, initial) { root.launcher.askInput(String(label), callback, initial) }
      function close() { root.launcher.hide() }
      function setQuery(text) { root.launcher.setQuery(String(text)) }
      function changed() { root.changed() }
      function refresh() { root.query(root.lastQuery) }
      function reply(rows, placement) {
        var p = root.providerById(providerId)
        if (p) root.deliver(p, rows, placement)
      }
    }
  }
}
