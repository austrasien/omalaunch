import QtQuick
import Quickshell
import Quickshell.Io
import "../core/State.js" as State

// Owns the persistent state object (docs/SPEC.md §8). Mutate through
// `update(fn)` so every change bumps `revision` and schedules a save.
Item {
  id: root

  property string dir: Quickshell.env("HOME") + "/.local/share/omalaunch"
  readonly property string path: dir + "/state.json"
  property var state: State.empty()
  property int revision: 0
  property bool ready: false

  function update(fn) {
    fn(root.state)
    root.revision += 1
    saveTimer.restart()
  }

  function flush() {
    if (!saveTimer.running) return
    saveTimer.stop()
    write()
  }

  function write() {
    file.setText(JSON.stringify(root.state))
  }

  Component.onCompleted: mkdir.running = true

  Process {
    id: mkdir
    command: ["mkdir", "-p", root.dir]
    onExited: file.path = root.path
  }

  Timer {
    id: saveTimer
    interval: 400
    onTriggered: root.write()
  }

  FileView {
    id: file
    watchChanges: false
    printErrors: false
    atomicWrites: true
    onLoaded: {
      var raw = null
      try {
        raw = JSON.parse(text())
      } catch (e) {
        console.warn("[omalaunch] state.json is not valid JSON; moving it aside")
        Quickshell.execDetached(["mv", root.path, root.path + ".broken-" + Date.now()])
      }
      root.state = State.upgrade(raw)
      root.revision += 1
      root.ready = true
    }
    onLoadFailed: {
      root.state = State.empty()
      root.revision += 1
      root.ready = true
    }
  }
}
