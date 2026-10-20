import QtQuick
import Quickshell
import Quickshell.Io

// Runs commands. `detached` fires and forgets; `capture` collects stdout and
// stderr and calls back(code, stdout, stderr). Each capture gets its own
// Process so concurrent calls never share state.
Item {
  id: root

  function detached(argv) {
    Quickshell.execDetached(argv)
  }

  // Run a bash command string detached, in a login shell so PATH matches a
  // terminal.
  function shell(command) {
    Quickshell.execDetached(["bash", "-lc", String(command)])
  }

  function capture(argv, callback, timeoutMs) {
    var proc = runner.createObject(root, { argv: argv, callback: callback || null, timeoutMs: timeoutMs || 15000 })
    proc.start()
    return proc
  }

  Component {
    id: runner

    Process {
      id: proc
      property var argv: []
      property var callback: null
      property int timeoutMs: 15000
      property bool finished: false
      property bool outDone: false
      property bool errDone: false
      property int code: -1
      property bool exitedFlag: false

      function start() {
        command = argv
        running = true
        guard.interval = timeoutMs
        guard.start()
      }

      function cancel() {
        callback = null
        if (running) running = false
      }

      function maybeFinish() {
        if (finished || !exitedFlag || !outDone || !errDone) return
        finished = true
        guard.stop()
        var cb = callback
        callback = null
        if (cb) {
          try { cb(code, out.text, err.text) } catch (e) { console.warn("[omalaunch] capture callback threw:", e) }
        }
        proc.destroy()
      }

      stdout: StdioCollector { id: out; onStreamFinished: { proc.outDone = true; proc.maybeFinish() } }
      stderr: StdioCollector { id: err; onStreamFinished: { proc.errDone = true; proc.maybeFinish() } }

      onExited: function(exitCode, exitStatus) {
        proc.code = exitCode
        proc.exitedFlag = true
        proc.maybeFinish()
      }

      property Timer guard: Timer {
        repeat: false
        onTriggered: {
          if (proc.finished) return
          proc.running = false
          proc.code = 124
          proc.exitedFlag = true
          proc.outDone = true
          proc.errDone = true
          proc.maybeFinish()
        }
      }
    }
  }
}
