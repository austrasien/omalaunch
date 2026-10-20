import QtQuick
import "Keywords.js" as Keywords

// "<keyword> terms" searches a site (gh, yt, maps, wiki…). Keywords come
// from Keywords.js, extended or overridden by ~/.config/omalaunch/web.json.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Web Keywords"
  property string sectionTitle: "Web"
  property string placement: "inline"
  property int order: 30
  property var sites: Keywords.merge(null)
  property var items: []
  readonly property string configFile: (root.host ? root.host.home : "") + "/.config/omalaunch/web.json"

  function start() { publish(); load() }
  function opened() { load() }

  function load() {
    root.host.capture(["cat", root.configFile], function(code, out) {
      var user = null
      if (code === 0) {
        try { user = JSON.parse(out) } catch (e) { root.host.toast("web.json is not valid JSON; using the default keywords") }
      }
      var next = Keywords.merge(user)
      if (JSON.stringify(next) !== JSON.stringify(root.sites)) {
        root.sites = next
        publish()
      }
    })
  }

  function publish() {
    var rows = root.sites.map(function(s) {
      return { id: "site:" + s.keyword, title: s.title, subtitle: "“" + s.keyword + " …”  ·  search " + s.title, icon: s.icon, type: "Web Search", keyword: s.keyword, keywords: [s.keyword, "search"], visibility: "search-only" }
    })
    rows.push({ id: "edit", title: "Edit Web Keywords", subtitle: "~/.config/omalaunch/web.json", icon: "", type: "Command", keywords: ["web", "keywords", "search engines", "settings"] })
    if (JSON.stringify(rows) !== JSON.stringify(root.items)) {
      root.items = rows
      root.host.changed()
    }
  }

  function query(text) {
    var m = Keywords.match(text, root.sites)
    if (!m) return []
    root.sectionTitle = m.site.title
    if (!m.terms) {
      var home = m.site.url.replace(/^(https?:\/\/[^\/#?]+).*$/, "$1")
      return [{ id: "home:" + m.site.keyword, title: "Open " + m.site.title, subtitle: home, icon: m.site.icon, type: "Web", url: home, copy: home }]
    }
    var url = Keywords.urlFor(m.site, m.terms)
    return [{ id: "q:" + m.site.keyword, title: "Search " + m.site.title + " for “" + m.terms + "”", subtitle: url, icon: m.site.icon, type: "Web", url: url, copy: m.terms }]
  }

  function actions(row) {
    if (row.keyword) return [{ id: "use", title: "Search " + row.title }]
    if (row.id === "edit") return [{ id: "edit", title: "Edit Keywords" }]
    return [{ id: "open", title: "Open" }, { id: "copy-url", title: "Copy URL" }]
  }

  function run(row, actionId) {
    if (row.keyword) {
      root.host.setQuery(row.keyword + " ")
      return { close: false }
    }
    if (row.id === "edit") {
      var example = JSON.stringify({
        "_help": "keyword: { title, url with {query}, icon }. Set a default keyword to null to remove it.",
        "npm": { "title": "npm", "url": "https://www.npmjs.com/search?q={query}" }
      }, null, 2)
      var script = '[[ -e $1 ]] || { mkdir -p "$(dirname "$1")" && printf "%s\\n" "$2" > "$1"; }; exec omarchy-launch-editor "$1"'
      root.host.exec(["bash", "-c", script, "bash", root.configFile, example])
      return { close: true }
    }
    if (actionId === "copy-url") {
      root.host.copy(row.url)
      return { close: false, toast: "URL copied" }
    }
    root.host.browse(row.url)
    return { close: true }
  }
}
