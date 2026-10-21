import QtQuick

// Ask Claude from the launcher. Typing "? question" (or "ask question")
// puts the row at the top; a search that ends with "?" or has 5+ words
// offers it near the web fallbacks. Answers run in a floating terminal with the claude CLI.
// "cc" / "resume" [terms] lists recent Claude Code sessions; Enter resumes
// one in a terminal in its folder, Quick Look shows how it ended.
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
    { id: "chat", title: "Claude", subtitle: "Open a conversation in a floating terminal", icon: "󰚩", type: "Command", keywords: ["ai", "chat", "assistant", "anthropic"] },
    { id: "sessions", title: "Resume Claude Session", subtitle: "Type “cc” and a few words of its title", icon: "\uf1da", type: "Command", keywords: ["claude code", "resume", "conversation", "history", "cc"] }
  ]
  property var sessions: []
  property double sessionsAt: 0
  property bool loadingSessions: false
  property var waiting: []

  // The inline answer being written, and the conversation it belongs to:
  // a new question within 15 minutes continues it (claude --resume).
  property var job: null
  property string thread: ""
  property double threadAt: 0
  property string answerText: ""
  readonly property string prompt: "You are answering inside a desktop launcher, under its search field. Be concise and direct; use short Markdown (lists, bold, code). Answer in the language of the question."


  function start() {
    root.host.capture(["bash", "-lc", "command -v claude"], function(code) { root.available = code === 0 })
  }

  function questionFrom(text) {
    var q = String(text).trim()
    var m = /^(?:\?|ask\s+|claude\s+)(.+)$/i.exec(q)
    return m ? { text: m[1].trim(), explicit: true } : { text: q, explicit: false }
  }

  // ------------------------------------------------------------ sessions

  function sessionTerms(text) {
    var m = /^(?:cc|resume|\/resume)(?:\s+(.*?))?\s*$/i.exec(String(text || ""))
    return m ? (m[1] || "").toLowerCase().split(/\s+/).filter(function(w) { return w }) : null
  }

  function withSessions(callback) {
    if (Date.now() - root.sessionsAt < 30000) { callback(root.sessions); return }
    root.waiting = root.waiting.concat([callback])
    if (root.loadingSessions) return
    root.loadingSessions = true
    root.host.capture(["bash", root.pluginDir + "/sessions.sh", "200"], function(code, out) {
      root.loadingSessions = false
      root.sessions = String(out || "").split("\n").filter(function(l) { return l }).map(function(l) {
        var f = l.split("\t")
        return { mtime: +f[0], id: f[1], cwd: f[2], title: f.slice(3).join(" ") }
      })
      root.sessionsAt = Date.now()
      var w = root.waiting
      root.waiting = []
      w.forEach(function(cb) { cb(root.sessions) })
    }, 20000)
  }

  function ago(t) {
    var s = Math.max(0, Date.now() / 1000 - t)
    if (s < 3600) return Math.max(1, Math.round(s / 60)) + " min"
    if (s < 86400) return Math.round(s / 3600) + " h"
    var d = Math.round(s / 86400)
    return d + (d > 1 ? " jours" : " jour")
  }

  function sessionRow(x) {
    var project = x.cwd.replace(root.host.home, "~")
    return { id: "session:" + x.id, title: x.title, subtitle: project + "  ·  il y a " + ago(x.mtime), icon: "\uf086", type: "Session", session: x.id, cwd: x.cwd, copy: x.id }
  }

  function sessionFile(row) {
    // ~/.claude/projects/<cwd with / and . as ->/<id>.jsonl
    return root.host.home + "/.claude/projects/" + row.cwd.replace(/[\/.]/g, "-") + "/" + row.session + ".jsonl"
  }

  function preview(row, reply) {
    if (!row.session) { reply({ kind: "none", name: row.title }); return }
    root.host.capture(["bash", root.pluginDir + "/excerpt.sh", sessionFile(row), "12"], function(code, out) {
      reply({ kind: "markdown", name: row.title, text: String(out || "").trim() || "(no messages)", mime: "Claude Code session", size: undefined })
    }, 8000)
  }

  function query(text, reply) {
    var terms = sessionTerms(text)
    if (terms !== null) {
      root.sectionTitle = "Claude Code sessions"
      withSessions(function(list) {
        var rows = list.filter(function(x) {
          var hay = (x.title + " " + x.cwd).toLowerCase()
          return terms.every(function(w) { return hay.indexOf(w) >= 0 })
        }).slice(0, 40).map(sessionRow)
        if (!rows.length) rows = [{ id: "none", title: "No Claude session matches", icon: "\uf086", type: "Session", disabled: true }]
        reply(rows, "inline")
      })
      return null
    }
    root.sectionTitle = "Claude"
    if (!root.available) return []
    var q = questionFrom(text)
    if (!q.text) return []
    if (!q.explicit && !/\?$/.test(q.text) && q.text.split(/\s+/).length < 5) return []
    var follow = root.thread && Date.now() - root.threadAt < 15 * 60000
    var row = { id: "ask", title: "Ask Claude", subtitle: q.text + (follow ? "  ·  continues the last answer" : ""), icon: "󰚩", type: "Claude", question: q.text, copy: q.text }
    reply([row], q.explicit ? "inline" : "bottom")
    return null
  }

  function quote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

  function actions(row) {
    if (row.id === "chat") return [{ id: "open", title: "Open Claude" }]
    if (row.id === "sessions") return [{ id: "list", title: "List Sessions" }]
    if (row.session) return [{ id: "resume", title: "Resume in Terminal" }, { id: "folder", title: "Open Project Folder" }, { id: "copy-id", title: "Copy Session ID" }]
    if (row.id === "answer") return [{ id: "continue", title: "Continue in Claude Code" }, { id: "copy-answer", title: "Copy Answer" }, { id: "new", title: "New Question" }]
    return [
      { id: "answer", title: "Answer Here" },
      { id: "chat", title: "Ask in Claude Code" },
      { id: "fresh", title: "Answer Here, New Conversation" },
      { id: "copy-question", title: "Copy Question" }
    ]
  }

  function run(row, actionId) {
    if (row.id === "sessions") {
      root.host.setQuery("cc ")
      return { close: false }
    }
    if (row.id === "answer") {
      if (actionId === "copy-answer") {
        root.host.copy(root.answerText)
        return { close: false, toast: "Answer copied" }
      }
      if (actionId === "new") {
        root.thread = ""
        root.host.setQuery("? ")
        return { close: false }
      }
      if (!row.session) return { close: false, toast: "Wait for the answer first" }
      root.host.exec(["setsid", "uwsm-app", "--", "xdg-terminal-exec", "--dir=" + root.host.home, "-e", "claude", "--resume", row.session])
      return { close: true }
    }
    if (row.session) {
      if (actionId === "copy-id") {
        root.host.copy(row.session)
        return { close: false, toast: "Session id copied" }
      }
      if (actionId === "folder") {
        root.host.exec(["xdg-open", row.cwd])
        return { close: true }
      }
      if (!root.available) return { close: false, toast: "The claude CLI is not on PATH" }
      root.host.exec(["setsid", "uwsm-app", "--", "xdg-terminal-exec", "--dir=" + row.cwd, "-e", "claude", "--resume", row.session])
      return { close: true }
    }
    if (!root.available) return { close: false, toast: "The claude CLI is not on PATH" }
    if (row.id === "chat") {
      root.host.terminal("claude", false)
      return { close: true }
    }
    if (actionId === "answer" || actionId === "fresh") {
      ask(row.question, actionId === "fresh")
      return { close: false }
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

  // ------------------------------------------------------ inline answers

  function stop() {
    if (root.job) { root.job.cancel(); root.job = null }
  }

  function answerClosed() { stop() }

  function answerActions() {
    return [{ id: "continue", title: "Continue in Claude Code" }, { id: "copy-answer", title: "Copy Answer" }, { id: "new", title: "New Question" }]
  }

  function ask(question, fresh) {
    stop()
    var follow = !fresh && root.thread && Date.now() - root.threadAt < 15 * 60000
    var args = ["-p", question, "--output-format", "stream-json", "--verbose", "--include-partial-messages", "--append-system-prompt", root.prompt]
    if (follow) args = args.concat(["--resume", root.thread])
    root.answerText = ""
    var session = follow ? root.thread : ""
    var status = ""
    var show = function(busy) {
      var body = root.answerText || (status ? "_" + status + "_" : "")
      root.host.updateAnswer({ text: body, busy: busy, session: session })
    }
    root.host.showAnswer({ title: "Claude" + (follow ? " · same conversation" : ""), question: question, text: "", busy: true, session: session, actions: answerActions() })
    root.job = root.host.stream(["bash", "-c", 'cd "$HOME" && exec claude "$@"', "bash"].concat(args), function(line) {
      var ev
      try { ev = JSON.parse(line) } catch (e) { return }
      if (ev.session_id) session = ev.session_id
      if (ev.type === "stream_event" && ev.event) {
        var e = ev.event
        if (e.type === "content_block_delta" && e.delta && e.delta.type === "text_delta") {
          root.answerText += e.delta.text
          status = ""
          show(true)
        } else if (e.type === "content_block_start" && e.content_block && e.content_block.type === "tool_use") {
          status = "Using " + e.content_block.name + "…"
          if (root.answerText && !/\n$/.test(root.answerText)) root.answerText += "\n\n"
          show(true)
        }
      } else if (ev.type === "result") {
        if (ev.is_error && !root.answerText) root.answerText = "**Error:** " + (ev.result || ev.subtype || "unknown")
        else if (!root.answerText && ev.result) root.answerText = String(ev.result)
      }
    }, function(code, err) {
      root.job = null
      if (code !== 0 && !root.answerText) root.answerText = "**Claude failed** (exit " + code + ")" + (err ? "\n\n```\n" + String(err).trim().split("\n").slice(-6).join("\n") + "\n```" : "")
      if (session) { root.thread = session; root.threadAt = Date.now() }
      status = ""
      show(false)
    })
  }
}
