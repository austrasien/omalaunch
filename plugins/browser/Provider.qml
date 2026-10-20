import QtQuick
import "Browser.js" as Browser

// Bookmarks of the most recently used Chromium-family profile (Brave,
// Chrome, Chromium, Vivaldi) as catalog rows, and "b term" over bookmarks
// and history. History is read in place (sqlite "immutable"), so the
// running browser is not disturbed.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Browser"
  property string sectionTitle: "Browser"
  property string placement: "inline"
  property int order: 22
  property string profile: ""
  property var marks: []
  property var items: []

  function start() { load() }
  function opened() { load() }

  // The profile whose History changed last.
  function load() {
    var script = 'shopt -s nullglob; for p in "$HOME"/.config/BraveSoftware/*/{Default,Profile*} "$HOME"/.config/{google-chrome,chromium,vivaldi}/{Default,Profile*}; do '
      + '[[ -f $p/History ]] && printf "%s %s\\n" "$(stat -c %Y "$p/History")" "$p"; done | sort -rn | head -n1 | cut -d" " -f2-'
    root.host.capture(["bash", "-c", script], function(code, out) {
      var p = String(out || "").trim()
      if (!p) return
      root.profile = p
      root.host.capture(["cat", p + "/Bookmarks"], function(c2, json) {
        if (c2 !== 0) return
        var list = []
        try { list = Browser.bookmarks(json) } catch (e) { return }
        if (JSON.stringify(list) === JSON.stringify(root.marks)) return
        root.marks = list
        root.items = list.map(function(b, i) {
          return { id: "bm:" + b.url, title: b.title, subtitle: (b.folder ? b.folder + "  ·  " : "") + Browser.host(b.url), icon: "", type: "Bookmark", url: b.url, copy: b.url, visibility: "search-only", keywords: [Browser.host(b.url)] }
        })
        root.host.changed()
      })
    })
  }

  function browserName() {
    var m = /\/(BraveSoftware\/[^\/]+|google-chrome|chromium|vivaldi)\//.exec(root.profile)
    return m ? m[1].replace("BraveSoftware/", "").replace(/-/g, " ") : "browser"
  }

  function query(text, reply) {
    var words = Browser.termsFrom(text)
    if (!words || !root.profile) return []
    root.sectionTitle = browserName()
    var marks = root.marks.filter(function(b) {
      var hay = (b.title + " " + b.url + " " + b.folder).toLowerCase()
      return words.every(function(w) { return hay.indexOf(w) >= 0 })
    }).slice(0, 8).map(function(b) {
      return { id: "bm:" + b.url, title: b.title, subtitle: (b.folder ? b.folder + "  ·  " : "") + Browser.host(b.url), icon: "", type: "Bookmark", url: b.url, copy: b.url }
    })
    var db = "file:" + root.profile + "/History?immutable=1"
    root.host.capture(["sqlite3", "-separator", "\t", db, Browser.historySql(words, 25)], function(code, out) {
      var seen = {}
      marks.forEach(function(m) { seen[m.url] = true })
      var rows = marks.slice()
      String(out || "").split("\n").forEach(function(line) {
        var f = line.split("\t")
        if (f.length < 4 || seen[f[0]]) return
        seen[f[0]] = true
        var when = Browser.chromeDate(f[3])
        rows.push({ id: "h:" + f[0], title: f[1] || f[0], subtitle: Browser.host(f[0]) + "  ·  " + f[2] + " visits  ·  " + ("0" + when.getDate()).slice(-2) + "/" + ("0" + (when.getMonth() + 1)).slice(-2) + "/" + when.getFullYear(), icon: "", type: "History", url: f[0], copy: f[0] })
      })
      if (!rows.length) rows = [{ id: "none", title: "Nothing in bookmarks or history matches", icon: "", type: "Browser", disabled: true }]
      reply(rows.slice(0, 25), "inline")
    }, 5000)
    return null
  }

  function actions(row) {
    if (!row.url) return [{ id: "none", title: "Nothing to do" }]
    return [{ id: "open", title: "Open" }, { id: "copy", title: "Copy URL" }, { id: "private", title: "Open in Private Window" }]
  }

  function run(row, actionId) {
    if (actionId === "copy") {
      root.host.copy(row.url)
      return { close: false, toast: "URL copied" }
    }
    if (actionId === "private") {
      root.host.exec(["omarchy-launch-browser", "--private", row.url])
      return { close: true }
    }
    root.host.browse(row.url)
    return { close: true }
  }
}
