import QtQuick

// Ask Claude from the launcher. Typing "? question" (or "ask question")
// puts the row at the top; a search that ends with "?" or has 5+ words
// offers it near the web fallbacks. Answers run in a floating terminal with the claude CLI.
Item {
  id: root

  property var host: null
  property string pluginDir: ""
  property string title: "Claude"
  property string sectionTitle: "Claude"
  property string placement: "bottom"
  property int order: 500
  property bool available: false

  property var items: [
    { id: "chat", title: "Claude", subtitle: "Open a conversation in a floating terminal", icon: "󰚩", type: "Command", keywords: ["ai", "chat", "assistant", "anthropic"] }
  ]

  function start() {
    root.host.capture(["bash", "-lc", "command -v claude"], function(code) { root.available = code === 0 })
  }

  function questionFrom(text) {
    var q = String(text).trim()
    var m = /^(?:\?|ask\s+|claude\s+)(.+)$/i.exec(q)
    return m ? { text: m[1].trim(), explicit: true } : { text: q, explicit: false }
  }

  function query(text, reply) {
    if (!root.available) return []
    var q = questionFrom(text)
    if (!q.text) return []
    if (!q.explicit && !/\?$/.test(q.text) && q.text.split(/\s+/).length < 5) return []
    var row = { id: "ask", title: "Ask Claude", subtitle: q.text, icon: "󰚩", type: "Claude", question: q.text, copy: q.text }
    reply([row], q.explicit ? "inline" : "bottom")
    return null
  }

  function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  function actions(row) {
    if (row.id === "chat") return [{ id: "open", title: "Open Claude" }]
    return [
      { id: "answer", title: "Quick Answer" },
      { id: "chat", title: "Continue as Conversation" },
      { id: "copy-question", title: "Copy Question" }
    ]
  }

  function run(row, actionId) {
    if (!root.available) return { close: false, toast: "The claude CLI is not on PATH" }
    if (row.id === "chat") {
      root.host.terminal("claude", false)
      return { close: true }
    }
    if (actionId === "copy-question") {
      root.host.copy(row.question)
      return { close: false, toast: "Question copied" }
    }
    if (actionId === "chat") {
      root.host.terminal("claude " + quote(row.question), false)
      return { close: true }
    }
    root.host.terminal("printf '\\033[1m%s\\033[0m\\n\\n' " + quote(row.question) + "; claude -p " + quote(row.question), true)
    return { close: true }
  }
}
