import QtQuick

// One list entry: a section header or a result row.
Item {
  id: root

  property var entry: ({ header: true, title: "" })   // { header, title } or { row, ordinal }
  required property var theme           // LauncherWindow (colours, font, px)
  property bool selected: false
  property int rowHeight: 42
  property int headerHeight: 28

  signal clicked()
  signal hovered()

  readonly property var row: entry.header ? null : entry.row
  height: entry.header ? headerHeight : rowHeight

  // ---------------------------------------------------------- header
  Text {
    visible: !!root.entry.header
    anchors { left: parent.left; leftMargin: theme.px(12); bottom: parent.bottom; bottomMargin: theme.px(5) }
    text: root.entry.header ? root.entry.title : ""
    color: theme.muted
    font.family: theme.font
    font.pixelSize: theme.captionSize
    font.weight: Font.DemiBold
  }

  // ------------------------------------------------------------- row
  Rectangle {
    visible: !root.entry.header
    anchors.fill: parent
    radius: Math.max(0, Math.round(theme.px(6)))
    color: root.selected ? theme.selBg : "transparent"
    opacity: root.row && root.row.disabled ? 0.45 : 1

    // Alt+1…9, Alt+0 run the first ten rows, in keyboard order.
    Row {
      id: quickKey
      anchors { left: parent.left; leftMargin: theme.px(10); verticalCenter: parent.verticalCenter }
      width: theme.px(34)
      spacing: theme.px(3)
      visible: !root.entry.header && root.entry.ordinal < 10

      Text {
        anchors.baseline: quickDigit.baseline
        text: "Alt"
        color: root.selected ? theme.selFg : theme.muted
        opacity: 0.55
        font.family: theme.font
        font.pixelSize: Math.round(theme.captionSize * 0.85)
      }

      Text {
        id: quickDigit
        text: root.entry.header ? "" : String((root.entry.ordinal + 1) % 10)
        color: root.selected ? theme.selFg : theme.fg
        font.family: theme.font
        font.pixelSize: theme.captionSize
        font.weight: Font.DemiBold
      }
    }

    Item {
      id: iconBox
      anchors { left: quickKey.right; leftMargin: theme.px(6); verticalCenter: parent.verticalCenter }
      width: theme.px(26)
      height: theme.px(26)

      Image {
        anchors.fill: parent
        visible: !!(root.row && root.row.iconSource)
        source: root.row && root.row.iconSource ? root.row.iconSource : ""
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
      }

      Text {
        anchors.centerIn: parent
        visible: !!(root.row && !root.row.iconSource)
        text: root.row && root.row.icon ? root.row.icon : "•"
        color: root.selected ? theme.selFg : theme.fg
        font.family: root.row && root.row.iconFont ? root.row.iconFont : theme.font
        font.pixelSize: theme.iconSize
      }
    }

    Text {
      id: titleText
      anchors { left: iconBox.right; leftMargin: theme.px(12); verticalCenter: parent.verticalCenter }
      width: Math.min(implicitWidth, parent.width * 0.55)
      text: root.row ? root.row.title : ""
      color: root.selected ? theme.selFg : theme.fg
      font.family: theme.font
      font.pixelSize: theme.titleSize
      font.weight: Font.Medium
      elide: Text.ElideRight
    }

    Text {
      anchors { left: titleText.right; leftMargin: theme.px(10); right: typeText.left; rightMargin: theme.px(10); verticalCenter: parent.verticalCenter }
      text: root.row && root.row.subtitle ? root.row.subtitle : ""
      color: theme.muted
      font.family: theme.font
      font.pixelSize: theme.detailSize
      elide: Text.ElideRight
    }

    Text {
      id: typeText
      anchors { right: parent.right; rightMargin: theme.px(12); verticalCenter: parent.verticalCenter }
      text: root.row ? ((root.row.alias ? root.row.alias + "  ·  " : "") + (root.row.favorite ? "★  " : "") + (root.row.type || "")) : ""
      color: theme.muted
      font.family: theme.font
      font.pixelSize: theme.captionSize
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: root.clicked()
      onPositionChanged: root.hovered()
    }
  }
}
