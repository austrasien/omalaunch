import QtQuick
import "Dictionary.js" as Dictionary

// "define word" looks the word up on Wiktionary (any language, English
// glosses); "spell word" checks it with hunspell and lists suggestions.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Dictionary"
  property string placement: "inline"
  property int order: 25
  property var dicts: []

  function start() {
    root.host.capture(["bash", "-c", "hunspell -D </dev/null 2>&1"], function(code, out) {
      var all = Dictionary.dictionaries(out)
      var pick = ["fr_FR", "en_US", "en_GB"].filter(function(d) { return all.indexOf(d) >= 0 })
      root.dicts = pick.length ? pick : all.slice(0, 2)
    })
  }

  function query(text, reply) {
    var q = Dictionary.parse(text)
    if (!q) return []
    return q.mode === "spell" ? spell(q.word, reply) : define(q.word, reply)
  }

  function define(word, reply) {
    var url = "https://en.wiktionary.org/api/rest_v1/page/definition/" + encodeURIComponent(word.replace(/ /g, "_"))
    var page = "https://en.wiktionary.org/wiki/" + encodeURIComponent(word.replace(/ /g, "_"))
    root.host.capture(["curl", "-fsS", "--max-time", "6", "-A", "omalaunch (https://github.com/austrasien/omalaunch)", url], function(code, out) {
      var defs = []
      if (code === 0) { try { defs = Dictionary.definitions(out, ["fr", "en"], 6) } catch (e) { defs = [] } }
      var rows = defs.map(function(d, i) {
        return { id: "def:" + i, title: d.definition, subtitle: word + "  ·  " + [d.partOfSpeech, d.language].filter(function(x) { return x }).join(", "), icon: "", type: "Definition", copy: d.definition, page: page }
      })
      if (!rows.length) rows = [{ id: "none", title: "No definition found for “" + word + "”", subtitle: "Open Wiktionary", icon: "", type: "Dictionary", page: page, copy: word }]
      reply(rows, "inline")
    }, 8000)
    return null
  }

  function spell(word, reply) {
    if (!root.dicts.length) return [{ id: "nodict", title: "Spell checking needs a hunspell dictionary", subtitle: "sudo pacman -S hunspell-fr hunspell-en_us", icon: "", type: "Dictionary", disabled: true }]
    var first = word.split(/\s+/)[0]
    root.host.capture(["bash", "-c", 'printf "%s\\n" "$2" | hunspell -a -d "$1"', "bash", root.dicts.join(","), first], function(code, out) {
      var r = Dictionary.spellResult(out)
      var rows = r.correct
        ? [{ id: "ok", title: first, subtitle: "Spelled correctly (" + root.dicts.join(", ") + ")", icon: "", type: "Spelling", copy: first }]
        : r.suggestions.slice(0, 8).map(function(s, i) { return { id: "sug:" + i, title: s, subtitle: "Suggestion for “" + first + "”", icon: "", type: "Spelling", copy: s } })
      if (!rows.length) rows = [{ id: "none", title: "No suggestions for “" + first + "”", icon: "", type: "Spelling", disabled: true }]
      reply(rows, "inline")
    }, 5000)
    return null
  }

  function actions(row) {
    if (row.page && row.id === "none") return [{ id: "open", title: "Open Wiktionary" }]
    if (row.page) return [{ id: "copy", title: "Copy Definition" }, { id: "open", title: "Open Wiktionary" }]
    return [{ id: "copy", title: "Copy" }]
  }

  function run(row, actionId) {
    if (actionId === "open") {
      root.host.browse(row.page)
      return { close: true }
    }
    root.host.copy(row.copy)
    return { close: false, toast: "Copied" }
  }
}
