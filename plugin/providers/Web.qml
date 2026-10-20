import QtQuick

// Web-search fallbacks at the bottom of every search.
Item {
  id: root

  property var host: null
  property string title: "Web"
  property string placement: "bottom"
  property int order: 1000
  property var engines: [
    { id: "google", name: "Google", icon: "\uf1a0", url: "https://www.google.com/search?q=%s" },
    { id: "duckduckgo", name: "DuckDuckGo", icon: "\uf002", url: "https://duckduckgo.com/?q=%s" }
  ]

  property string sectionTitle: ""

  function query(text) {
    var q = String(text).trim()
    root.sectionTitle = "Use “" + q + "” with…"
    return root.engines.map(function(e) {
      return { id: e.id, title: "Search " + e.name, subtitle: q, icon: e.icon, type: "Web", url: e.url.replace("%s", encodeURIComponent(q)), copy: q }
    })
  }

  function actions(row) {
    return [{ id: "open", title: "Search" }, { id: "copy-url", title: "Copy URL" }]
  }

  function run(row, actionId) {
    if (actionId === "copy-url") {
      root.host.copy(row.url)
      return { close: false, toast: "URL copied" }
    }
    root.host.browse(row.url)
    return { close: true }
  }
}
