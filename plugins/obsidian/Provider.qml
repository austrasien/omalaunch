import QtQuick
import "Obsidian.js" as Obsidian

// Obsidian vaults from ~/.config/obsidian/obsidian.json. "o term": notes by
// title, then by content (ripgrep); "o": the newest notes; "o+ text": a
// "- HH:mm text" line in today's daily note (under "## Notes" when the note
// has it); "on Title": a new note in the vault's new-note folder.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Obsidian"
  property string sectionTitle: "Obsidian"
  property string placement: "inline"
  property int order: 18
  property var vaultList: []
  property var daily: ({ folder: "", format: "YYYY-MM-DD", template: "" })
  property string newFolder: ""
  readonly property string journalHeading: "## Notes"
  readonly property var vault: root.vaultList.length ? root.vaultList[0] : null

  property var items: []

  function start() { load() }
  function opened() { load() }

  function load() {
    root.host.capture(["cat", root.host.home + "/.config/obsidian/obsidian.json"], function(code, out) {
      if (code !== 0) return
      try { root.vaultList = Obsidian.vaults(out) } catch (e) { return }
      if (!root.vault) return
      var v = root.vault.path
      // Daily-notes settings and the new-note folder, with Inbox/ as fallback.
      var script = 'cat "$1/.obsidian/daily-notes.json" 2>/dev/null || echo "{}"; printf "\\x1e"; cat "$1/.obsidian/app.json" 2>/dev/null || echo "{}"; printf "\\x1e"; [[ -d $1/Inbox ]] && echo Inbox'
      root.host.capture(["bash", "-c", script, "bash", v], function(c2, o2) {
        var parts = String(o2 || "").split("\x1e")
        try {
          var d = JSON.parse(parts[0] || "{}")
          root.daily = { folder: d.folder || "", format: d.format || "YYYY-MM-DD", template: d.template || "" }
        } catch (e) {}
        var folder = ""
        try { folder = JSON.parse(parts[1] || "{}").newFileFolderPath || "" } catch (e) {}
        root.newFolder = folder || String(parts[2] || "").trim()
        publish()
      })
    })
  }

  function publish() {
    var name = root.vault ? root.vault.name : ""
    var rows = root.vault ? [
      { id: "today", title: "Today's Note", subtitle: name + " · " + (root.daily.folder ? root.daily.folder + "/" : "") + Obsidian.formatMoment(new Date(), root.daily.format) + ".md", icon: "", type: "Obsidian", keywords: ["obsidian", "journal", "daily", "note du jour", "aujourd'hui"] },
      { id: "vault", title: "Open " + name + " in Obsidian", subtitle: root.vault.path, icon: "", type: "Obsidian", keywords: ["obsidian", "vault", "notes"] }
    ] : []
    if (JSON.stringify(rows) !== JSON.stringify(root.items)) {
      root.items = rows
      root.host.changed()
    }
  }

  function noteRow(path, id, detail) {
    var rel = path.indexOf(root.vault.path + "/") === 0 ? path.slice(root.vault.path.length + 1) : path
    var name = rel.slice(rel.lastIndexOf("/") + 1).replace(/\.md$/, "")
    return { id: id, title: name, subtitle: detail || rel, icon: "", type: "Note", path: path, copy: "[[" + name + "]]" }
  }

  function query(text, reply) {
    var q = Obsidian.parse(text)
    if (!q || !root.vault) return []
    root.sectionTitle = "Obsidian · " + root.vault.name
    if (q.mode === "journal") {
      return [{ id: "journal", title: q.text ? "Add to today's note: " + q.text : "Today's note", subtitle: (root.daily.folder ? root.daily.folder + "/" : "") + Obsidian.formatMoment(new Date(), root.daily.format) + ".md" + (q.text ? "  ·  under " + root.journalHeading : ""), icon: "", type: "Obsidian", text: q.text }]
    }
    if (q.mode === "new") {
      var file = Obsidian.fileName(q.text)
      if (!file) return []
      return [{ id: "new", title: "New note: " + file, subtitle: (root.newFolder ? root.newFolder + "/" : "") + file + ".md", icon: "", type: "Obsidian", file: file }]
    }
    var v = root.vault.path
    var words = q.text.toLowerCase().split(/\s+/).filter(function(w) { return w })
    if (!words.length) {
      root.host.capture(["bash", "-c", 'fd -0 -e md . "$1" | xargs -0 -r stat -c "%Y %n" -- | sort -rn | head -n 20 | cut -d" " -f2-', "bash", v], function(code, out) {
        reply(String(out || "").split("\n").filter(function(l) { return l }).map(function(p) { return root.noteRow(p, "note:" + p) }), "inline")
      }, 8000)
      return null
    }
    // Titles first, then notes whose text holds the words.
    var script = 'v=$1; shift; fd -i -F -e md -- "$1" "$v" | head -n 200; printf "\\x1e"; '
      + 'rg -i -F --max-count 1 --max-columns 200 -n -g "*.md" -- "$*" "$v" 2>/dev/null | head -n 40'
    root.host.capture(["bash", "-c", script, "bash", v].concat(words), function(code, out) {
      var parts = String(out || "").split("\x1e")
      var titles = (parts[0] || "").split("\n").filter(function(l) { return l })
      titles = titles.filter(function(p) {
        var low = p.toLowerCase()
        return words.every(function(w) { return low.indexOf(w) >= 0 })
      }).sort(function(a, b) { return a.length - b.length }).slice(0, 15)
      var seen = {}
      var rows = titles.map(function(p) { seen[p] = true; return root.noteRow(p, "note:" + p) })
      ;(parts[1] || "").split("\n").forEach(function(line) {
        var m = /^(.*?\.md):(\d+):(.*)$/.exec(line)
        if (!m || seen[m[1]] || rows.length >= 30) return
        seen[m[1]] = true
        rows.push(root.noteRow(m[1], "text:" + m[1], "“" + m[3].trim().slice(0, 120) + "”"))
      })
      if (!rows.length) rows = [{ id: "new-from-search", title: "New note: " + Obsidian.fileName(q.text), subtitle: "No note matches “" + q.text + "”", icon: "", type: "Obsidian", file: Obsidian.fileName(q.text) }]
      reply(rows, "inline")
    }, 8000)
    return null
  }

  function actions(row) {
    if (row.id === "journal") return [{ id: "add", title: row.text ? "Add to Today's Note" : "Open Today's Note" }, { id: "open-today", title: "Open Today's Note" }]
    if (row.file !== undefined) return [{ id: "create", title: "Create Note" }]
    if (row.path) return [{ id: "open", title: "Open in Obsidian" }, { id: "edit", title: "Open in Editor" }, { id: "link", title: "Copy [[Link]]" }]
    return [{ id: "open", title: "Open" }]
  }

  function obsidianOpen(path) {
    root.host.exec(["xdg-open", "obsidian://open?path=" + encodeURIComponent(path)])
  }

  function todayPath(now) {
    return root.vault.path + "/" + (root.daily.folder ? root.daily.folder + "/" : "") + Obsidian.formatMoment(now, root.daily.format) + ".md"
  }

  // Write a file through a temporary copy (and create its folder).
  function writeFile(path, text, then) {
    var script = 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1.omalaunch-tmp" && mv "$1.omalaunch-tmp" "$1"'
    root.host.capture(["bash", "-c", script, "bash", path, text], function(code) { if (then) then(code === 0) })
  }

  // Today's note: its content, or the daily template filled in when it does not exist yet.
  function withToday(now, callback) {
    var path = todayPath(now)
    var tpl = root.daily.template ? root.vault.path + "/" + root.daily.template.replace(/\.md$/, "") + ".md" : ""
    root.host.capture(["bash", "-c", 'if [[ -f $1 ]]; then echo old; cat "$1"; elif [[ -n $2 && -f $2 ]]; then echo new; cat "$2"; else echo new; fi', "bash", path, tpl], function(code, out) {
      var s = String(out || "")
      var nl = s.indexOf("\n")
      var fresh = s.slice(0, nl < 0 ? s.length : nl) === "new"
      var body = nl < 0 ? "" : s.slice(nl + 1)
      if (fresh) body = Obsidian.fillTemplate(body, Obsidian.formatMoment(now, root.daily.format), now)
      callback(path, body, fresh)
    })
  }

  function run(row, actionId) {
    if (!root.vault) return { close: false, toast: "No Obsidian vault found" }
    var now = new Date()
    if (row.id === "vault") {
      root.host.exec(["xdg-open", "obsidian://open?vault=" + encodeURIComponent(root.vault.name)])
      return { close: true }
    }
    if (row.id === "today" || actionId === "open-today" || (row.id === "journal" && !row.text)) {
      withToday(now, function(path, body, fresh) {
        if (fresh) writeFile(path, body, function() { obsidianOpen(path) })
        else obsidianOpen(path)
      })
      return { close: true }
    }
    if (row.id === "journal") {
      var line = "- " + Obsidian.formatMoment(now, "HH:mm") + " " + row.text
      withToday(now, function(path, body) {
        writeFile(path, Obsidian.insertLine(body, root.journalHeading, line), function(ok) {
          root.host.notify(ok ? "Added to today's note" : "Could not write today's note", row.text)
        })
      })
      return { close: true }
    }
    if (row.file !== undefined) {
      var path = root.vault.path + "/" + (root.newFolder ? root.newFolder + "/" : "") + row.file + ".md"
      root.host.capture(["test", "-e", path], function(code) {
        if (code === 0) { obsidianOpen(path); return }
        writeFile(path, "", function() { obsidianOpen(path) })
      })
      return { close: true }
    }
    if (actionId === "edit") {
      root.host.exec(["omarchy-launch-editor", row.path])
      return { close: true }
    }
    if (actionId === "link") {
      root.host.copy(row.copy)
      return { close: false, toast: "Copied " + row.copy }
    }
    obsidianOpen(row.path)
    return { close: true }
  }
}
