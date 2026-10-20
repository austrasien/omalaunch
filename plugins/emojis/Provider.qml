import QtQuick
import "Emoji.js" as Emoji

// ":name" finds emojis by French or English name (Unicode CLDR); Enter
// pastes into the focused window, Ctrl+Enter copies. A bare ":" lists the
// ones used last.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Emojis"
  property string placement: "inline"
  property int order: 12
  property var emojis: []
  property var recent: []
  readonly property string recentFile: (root.host ? root.host.dataDir : "") + "/recent.json"

  property var items: [
    { id: "picker", title: "Emojis", subtitle: "Type “:” and a name, in French or English", icon: "😀", type: "Command", keywords: ["emoji", "smiley", "symbole"] }
  ]

  function start() {
    root.host.capture(["cat", root.pluginDir + "/emojis.json"], function(code, out) {
      if (code !== 0) return
      try { root.emojis = Emoji.prepare(JSON.parse(out)) } catch (e) { console.warn("[omalaunch] emojis.json:", e) }
    })
    root.host.capture(["cat", root.recentFile], function(code, out) {
      if (code === 0) { try { root.recent = JSON.parse(out) } catch (e) { root.recent = [] } }
    })
  }

  function rowFor(x) {
    return { id: "e:" + x.e, title: x.fr || x.en, subtitle: (x.fr ? x.en + "  ·  " : "") + x.g, icon: x.e, type: "Emoji", emoji: x.e, copy: x.e }
  }

  function query(text) {
    var words = Emoji.termsFrom(text)
    if (words === null) return []
    if (!words.length) {
      var byEmoji = {}
      root.emojis.forEach(function(x) { byEmoji[x.e] = x })
      return root.recent.map(function(e) { return byEmoji[e] }).filter(function(x) { return x }).map(rowFor)
    }
    var found = Emoji.search(root.emojis, words, 40)
    return found.length ? found.map(rowFor) : [{ id: "none", title: "No emoji for “" + words.join(" ") + "”", icon: "", type: "Emoji", disabled: true }]
  }

  function actions(row) {
    if (row.id === "picker") return [{ id: "start", title: "Search Emojis" }]
    return [{ id: "paste", title: "Paste " + row.emoji }, { id: "copy", title: "Copy " + row.emoji }]
  }

  function remember(e) {
    root.recent = [e].concat(root.recent.filter(function(x) { return x !== e })).slice(0, 24)
    root.host.exec(["bash", "-c", 'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1"', "bash", root.recentFile, JSON.stringify(root.recent)])
  }

  function run(row, actionId) {
    if (row.id === "picker") {
      root.host.setQuery(":")
      return { close: false }
    }
    if (!row.emoji) return { close: false }
    remember(row.emoji)
    if (actionId === "copy") {
      root.host.copy(row.emoji)
      return { close: false, toast: "Copied " + row.emoji }
    }
    root.host.exec([root.host.omarchyPath + "/bin/omarchy-clipboard-paste-text", "--shift-insert", row.emoji])
    return { close: true }
  }
}
