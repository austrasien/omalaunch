import QtQuick
import qs.Commons

// Ctrl+K: every action of the selected row, filterable.
Rectangle {
  id: panel

  required property var theme
  required property var launcher
  property var row: null
  property string filter: ""
  property int index: 0

  readonly property var all: row ? launcher.actionsFor(row) : []
  readonly property var shown: all.filter(function(a) { return !filter || a.title.toLowerCase().indexOf(filter.toLowerCase()) >= 0 })

  width: theme.px(360)
  height: Math.min(theme.px(380), header.height + listCol.implicitHeight + theme.px(16))
  color: theme.bg
  border.color: theme.border
  border.width: theme.borderWidth
  radius: Style.cornerRadius
  clip: true

  function reset() {
    panel.filter = ""
    panel.index = 0
  }

  function handleKey(event) {
    var k = event.key
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    if (k === Qt.Key_Escape || (ctrl && k === Qt.Key_K)) { launcher.actionPanelOpen = false; return true }
    if (k === Qt.Key_Down || (ctrl && k === Qt.Key_N)) { panel.index = Math.min(panel.shown.length - 1, panel.index + 1); return true }
    if (k === Qt.Key_Up || (ctrl && k === Qt.Key_P)) { panel.index = Math.max(0, panel.index - 1); return true }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      var a = panel.shown[panel.index]
      if (a) launcher.runAction(panel.row, a)
      return true
    }
    if (k === Qt.Key_Backspace) { panel.filter = panel.filter.slice(0, -1); panel.index = 0; return true }
    if (event.text && event.text.length === 1 && event.text >= " " && !ctrl) {
      panel.filter += event.text
      panel.index = 0
      return true
    }
    return true
  }

  Text {
    id: header
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: theme.px(10) }
    height: theme.px(26)
    verticalAlignment: Text.AlignVCenter
    text: panel.filter ? "Filter: " + panel.filter : (panel.row ? panel.row.title : "")
    color: panel.filter ? theme.accent : theme.muted
    font.family: theme.font
    font.pixelSize: theme.detailSize
    elide: Text.ElideRight
  }

  Column {
    id: listCol
    anchors { left: parent.left; right: parent.right; top: header.bottom; margins: theme.px(6) }

    Repeater {
      model: panel.shown

      Rectangle {
        required property var modelData
        required property int index
        width: listCol.width
        height: theme.px(32)
        radius: Math.round(theme.px(5))
        color: index === panel.index ? theme.selBg : "transparent"

        Text {
          anchors { left: parent.left; leftMargin: theme.px(10); verticalCenter: parent.verticalCenter; right: sc.left; rightMargin: theme.px(8) }
          text: modelData.title
          color: index === panel.index ? theme.selFg : theme.fg
          font.family: theme.font
          font.pixelSize: theme.fontSize
          elide: Text.ElideRight
        }
        Text {
          id: sc
          anchors { right: parent.right; rightMargin: theme.px(10); verticalCenter: parent.verticalCenter }
          text: modelData.shortcut || ""
          color: theme.muted
          font.family: theme.font
          font.pixelSize: theme.captionSize
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: panel.index = index
          onClicked: launcher.runAction(panel.row, modelData)
        }
      }
    }
  }
}
