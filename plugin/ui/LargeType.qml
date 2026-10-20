import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Large Type (docs/SPEC.md §6): a text shown as big as the screen allows,
// over a dimmed desktop. Any key or click closes it.
PanelWindow {
  id: window

  required property var launcher
  property string text: ""
  readonly property bool shown: text !== ""

  visible: shown
  color: "transparent"
  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omalaunch-large"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  Rectangle {
    anchors.fill: parent
    color: Color.menu.scrim
  }

  MouseArea {
    anchors.fill: parent
    onClicked: window.launcher.closeLargeType()
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.round(parent.width * 0.8)
    height: Math.round(parent.height * 0.4)
    color: Color.menu.background
    border.color: window.borderSpec.color
    border.width: Math.round(Border.top(window.borderSpec))
    radius: Style.cornerRadius

    Text {
      id: label
      anchors { fill: parent; margins: Style.space(40) }
      text: window.text
      color: Color.menu.text
      font.family: Style.resolvedFontFamily
      font.pixelSize: Style.space(160)
      minimumPixelSize: Style.font.heading
      fontSizeMode: Text.Fit
      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }

  Item {
    id: keys
    focus: window.shown
    Keys.onPressed: function(event) { event.accepted = true; window.launcher.closeLargeType() }
  }

  onShownChanged: if (shown) keys.forceActiveFocus()
}
