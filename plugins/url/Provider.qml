import QtQuick
import Quickshell
import "Url.js" as Url

// A typed or pasted URL comes first: Enter opens it in the default browser.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "URL"
  property string sectionTitle: "Open URL"
  property string placement: "inline"
  property int order: -10
  property var items: []
  property string browserName: "Default browser"
  property string browserIcon: ""

  function start() { resolveBrowser() }
  function opened() { resolveBrowser() }

  function resolveBrowser() {
    root.host.capture([root.pluginDir + "/browser.sh"], function(code, out) {
      var f = code === 0 ? String(out).trim().split("\t") : []
      root.browserName = f[0] || "Default browser"
      root.browserIcon = f[1] ? (f[1].charAt(0) === "/" ? "file://" + f[1] : Quickshell.iconPath(f[1], true)) : ""
    })
  }

  function query(text) {
    var url = Url.parse(text)
    if (!url) return []
    return [{ id: "open", title: "Open " + url, subtitle: root.browserName, icon: "\uf0ac", iconSource: root.browserIcon, type: "URL", url: url, copy: url }]
  }

  function actions(row) {
    return [{ id: "open", title: "Open" }, { id: "private", title: "Open in Private Window" }, { id: "copy", title: "Copy URL" }]
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
