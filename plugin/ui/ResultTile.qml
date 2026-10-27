import QtQuick
import qs.Commons

// One cell of the grid view (docs/SPEC.md §4): a square thumbnail (emoji,
// image, or a rendered PDF page / video frame / office page) with the
// row's title under it.
Item {
  id: root

  required property var theme
  required property var launcher
  property var row: null
  property int ordinal: 0
  property bool selected: false
  property string thumb: ""

  signal clicked()
  signal hovered()

  readonly property bool isEmoji: !!(row && row.emoji)
  readonly property string filePath: row ? (row.previewPath || row.path || "") : ""

  function load() {
    root.thumb = ""
    if (!root.row || root.isEmoji) return
    if (root.row.iconSource) { root.thumb = root.row.iconSource; return }
    if (!root.filePath) return
    var want = root.filePath
    root.launcher.thumbnail(want, function(image) { if (root.filePath === want) root.thumb = image ? "file://" + image : "" })
  }

  onRowChanged: load()
  Component.onCompleted: load()

  Rectangle {
    anchors { fill: parent; margins: theme.px(4) }
    radius: Math.max(0, Math.round(theme.px(8)))
    color: root.selected ? theme.selBg : Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.03)
    opacity: root.row && root.row.disabled ? 0.45 : 1

    Item {
      id: art
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: theme.px(8) }
      height: width * 0.78

      Image {
        anchors.fill: parent
        visible: root.thumb !== ""
        source: root.thumb
        sourceSize.width: Math.max(1, width * 2)
        sourceSize.height: Math.max(1, height * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
      }

      Text {
        anchors.centerIn: parent
        visible: root.thumb === ""
        text: root.isEmoji ? root.row.emoji : (root.row && root.row.icon ? root.row.icon : "")
        color: root.selected ? theme.selFg : theme.muted
        font.family: root.isEmoji ? "" : (root.row && root.row.iconFont ? root.row.iconFont : theme.font)
        font.pixelSize: root.isEmoji ? art.height * 0.62 : art.height * 0.42
      }
    }

    // Alt+0…9 run the first ten tiles.
    Rectangle {
      visible: root.ordinal < 10
      anchors { left: art.left; top: art.top }
      width: Math.max(height, tileKeyText.implicitWidth + theme.px(8))
      height: tileKeyText.implicitHeight + theme.px(2)
      radius: Math.round(theme.px(4))
      color: theme.bg
      border.width: 1
      border.color: theme.muted
      opacity: 0.85

      Text {
        id: tileKeyText
        anchors.centerIn: parent
        text: root.ordinal
        color: theme.muted
        font.family: theme.font
        font.pixelSize: theme.captionSize
      }
    }

    Text {
      anchors { left: parent.left; right: parent.right; top: art.bottom; topMargin: theme.px(6); leftMargin: theme.px(6); rightMargin: theme.px(6) }
      text: root.row ? root.row.title : ""
      color: root.selected ? theme.selFg : theme.fg
      font.family: theme.font
      font.pixelSize: theme.detailSize
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideMiddle
      maximumLineCount: 1
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: root.clicked()
      onPositionChanged: root.hovered()
    }
  }
}
