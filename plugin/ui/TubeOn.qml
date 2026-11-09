import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// The first window launched on an empty workspace or scratchpad comes up like
// a tube warming: a black mask placed exactly over it, a dot, a line, then the
// picture opening from the line, still burnt and worn for a moment.
//
// The surface is mapped, empty and click-through, for as long as the launcher
// is open over an empty place: mapping it only when the window shows up would
// put it behind Hyprland's layer fade-in.
PanelWindow {
  id: tube

  property bool launcherOpen: false
  // The empty place under the open launcher, "" when it is not empty.
  property string place: ""
  // The place a window is awaited on.
  property string armed: ""
  property bool playing: false
  property rect target: Qt.rect(0, 0, 0, 0)
  property string awaited: ""

  property real heat: 0
  property real spread: 0
  property real opened: 0
  property real settle: 0

  readonly property color off: Qt.darker(Color.background, 1.6)
  readonly property color bright: Qt.tint(Color.accent, Qt.alpha("#ffffff", 0.45))
  readonly property real tear: Math.sin(spread * 40) * 8 * (1 - spread)
  readonly property int aperture: Math.round(target.height * opened)

  visible: (launcherOpen && place !== "") || armed !== "" || playing
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  mask: Region {}
  WlrLayershell.namespace: "omalaunch-tube"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  onLauncherOpenChanged: {
    if (launcherOpen) {
      place = ""
      placeProbe.running = false
      placeProbe.running = true
    } else if (armed === "") {
      place = ""
    }
  }

  // Await a window on the empty place, if the launcher is over one. Called
  // when a row is run, before the launcher closes.
  function arm() {
    if (place === "" || Style.reduceMotion) return
    armed = place
    armTimeout.restart()
  }

  function disarm() {
    armTimeout.stop()
    armed = ""
    if (!launcherOpen) place = ""
  }

  // Not everything run opens a window.
  Timer { id: armTimeout; interval: 12000; onTriggered: tube.disarm() }

  Process {
    id: placeProbe
    command: ["bash", "-c", "n=$(hyprctl -j monitors | jq -r '.[] | select(.focused) | if .specialWorkspace.name != \"\" then .specialWorkspace.name else .activeWorkspace.name end'); "
      + "[ \"$(hyprctl -j workspaces | jq --arg n \"$n\" '[.[] | select(.name == $n) | .windows] | add // 0')\" = 0 ] && printf %s \"$n\""]
    stdout: StdioCollector {
      onStreamFinished: if (tube.launcherOpen) tube.place = text.trim()
    }
  }

  Connections {
    target: Hyprland
    enabled: tube.armed !== ""
    function onRawEvent(event) {
      var name = String(event.name)
      if (name === "workspace" || name === "workspacev2" || name === "activespecial" || name === "activespecialv2") {
        tube.disarm()
      } else if (name === "openwindow") {
        var fields = String(event.data).split(",")
        if (fields[1] !== tube.armed) return
        tube.awaited = fields[0]
        armTimeout.stop()
        tube.armed = ""
        tube.playing = true   // keeps the surface up while the geometry comes
        geometryProbe.running = false
        geometryProbe.running = true
      }
    }
  }

  Process {
    id: geometryProbe
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: {
        var found = null
        try {
          var clients = JSON.parse(text)
          for (var i = 0; i < clients.length; i++)
            if (String(clients[i].address).replace(/^0x/, "") === tube.awaited.replace(/^0x/, "")) found = clients[i]
        } catch (e) {}
        if (found && tube.screen) tube.play(found.at[0] - tube.screen.x, found.at[1] - tube.screen.y, found.size[0], found.size[1])
        else tube.finish()
      }
    }
  }

  function play(x, y, w, h) {
    target = Qt.rect(x, y, w, h)
    heat = 0
    spread = 0
    opened = 0
    settle = 0
    playing = true
    ignition.restart()
  }

  function finish() {
    playing = false
    target = Qt.rect(0, 0, 0, 0)
    if (!launcherOpen) place = ""
  }

  SequentialAnimation {
    id: ignition
    onFinished: tube.finish()
    NumberAnimation { target: tube; property: "heat"; to: 1; duration: 60 }
    NumberAnimation { target: tube; property: "spread"; to: 1; duration: 100; easing.type: Easing.OutCubic }
    NumberAnimation { target: tube; property: "opened"; to: 1; duration: 150; easing.type: Easing.OutCubic }
    NumberAnimation { target: tube; property: "settle"; to: 1; duration: 280 }
  }

  Item {
    id: screenArea
    visible: tube.playing
    x: tube.target.x
    y: tube.target.y
    width: tube.target.width
    height: tube.target.height

    // The off screen, drawn back from the line.
    Rectangle {
      id: upper
      width: parent.width
      height: Math.ceil((parent.height - tube.aperture) / 2)
      color: tube.off
    }
    Rectangle {
      id: lower
      y: parent.height - height
      width: parent.width
      height: Math.ceil((parent.height - tube.aperture) / 2)
      color: tube.off
    }

    // The picture, burnt and worn until it settles.
    Item {
      y: upper.height
      width: parent.width
      height: Math.max(0, lower.y - upper.height)
      clip: true

      Rectangle {
        anchors.fill: parent
        color: tube.bright
        opacity: Math.max(0, 1 - tube.settle * 1.7)
      }
      TapeLines { pitch: 4; ink: Color.accent; strength: 0.3; opacity: 1 - tube.settle }
      TapeLines { ink: tube.off; strength: 0.6; opacity: 1 - tube.settle }

      // The scan line and its trail, passing once.
      Rectangle {
        visible: tube.settle > 0 && tube.settle < 1
        y: parent.height * tube.settle - height
        width: parent.width
        height: 60
        gradient: Gradient {
          GradientStop { position: 0; color: Qt.alpha(Color.accent, 0) }
          GradientStop { position: 1; color: Qt.alpha(Color.accent, 0.4) }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 2; color: tube.bright }
      }
    }

    // The glow around the line.
    Rectangle {
      visible: tube.heat > 0 && tube.opened < 1
      width: 6 + (parent.width - 6) * tube.spread
      height: 10 + 38 * tube.spread
      x: (parent.width - width) / 2 + tube.tear
      y: (parent.height - height) / 2
      opacity: tube.heat * (1 - tube.opened)
      gradient: Gradient {
        GradientStop { position: 0; color: Qt.alpha(Color.accent, 0) }
        GradientStop { position: 0.5; color: Qt.alpha(Color.accent, 0.45) }
        GradientStop { position: 1; color: Qt.alpha(Color.accent, 0) }
      }
    }

    // The dot, then the line, then the two edges of the opening picture.
    Rectangle {
      visible: tube.heat > 0 && tube.opened < 1
      width: 6 + (parent.width - 6) * tube.spread
      height: 3
      x: (parent.width - width) / 2 + tube.tear
      y: upper.height - 2
      color: tube.bright
      opacity: tube.heat * (1 - tube.opened)
    }
    Rectangle {
      visible: tube.heat > 0 && tube.opened < 1
      width: 6 + (parent.width - 6) * tube.spread
      height: 3
      x: (parent.width - width) / 2 + tube.tear
      y: lower.y - 1
      color: tube.bright
      opacity: tube.heat * (1 - tube.opened)
    }
  }
}
