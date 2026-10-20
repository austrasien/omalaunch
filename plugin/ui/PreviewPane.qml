import QtQuick
import qs.Commons

// Quick Look pane (docs/SPEC.md §6): shows `preview` (Main.previewData) —
// { kind: image|text|markdown|dir|info|missing|none|loading, name, mime,
//   size, mtime, image, text, count }.
Rectangle {
  id: root

  required property var theme
  property var preview: null
  readonly property string kind: preview ? String(preview.kind || "none") : "none"

  color: theme.bg
  border.color: theme.border
  border.width: theme.borderWidth
  radius: Style.cornerRadius
  clip: true

  MouseArea { anchors.fill: parent; onWheel: function(wheel) { root.scroll(-wheel.angleDelta.y / 40) } }

  function humanSize(n) {
    if (!n && n !== 0) return ""
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    var v = Number(n)
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
    return (i ? v.toFixed(v < 10 ? 1 : 0) : v) + " " + units[i]
  }

  function details() {
    if (!root.preview) return ""
    var parts = []
    if (root.preview.mime) parts.push(root.preview.mime)
    if (root.kind === "dir" && root.preview.count !== undefined) parts.push(root.preview.count + " items")
    else if (root.preview.size !== undefined && root.kind !== "none") parts.push(humanSize(root.preview.size))
    if (root.preview.mtime) parts.push(new Date(root.preview.mtime * 1000).toLocaleString(Qt.locale(), Locale.ShortFormat))
    return parts.join("  ·  ")
  }

  // ------------------------------------------------------------ header
  Item {
    id: header
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: theme.borderWidth }
    height: theme.searchHeight

    Column {
      anchors { left: parent.left; right: parent.right; leftMargin: theme.px(20); rightMargin: theme.px(20); verticalCenter: parent.verticalCenter }
      spacing: theme.px(2)
      Text {
        width: parent.width
        text: root.preview && root.preview.name ? root.preview.name : "Quick Look"
        color: theme.fg
        font.family: theme.font
        font.pixelSize: theme.titleSize
        font.weight: Font.Medium
        elide: Text.ElideMiddle
      }
      Text {
        width: parent.width
        visible: text !== ""
        text: root.details()
        color: theme.muted
        font.family: theme.font
        font.pixelSize: theme.detailSize
        elide: Text.ElideRight
      }
    }
  }

  Rectangle {
    id: rule
    anchors { left: parent.left; right: parent.right; top: header.bottom; leftMargin: theme.borderWidth; rightMargin: theme.borderWidth }
    height: 1
    color: Qt.rgba(theme.fg.r, theme.fg.g, theme.fg.b, 0.10)
  }

  // -------------------------------------------------------------- body
  Item {
    id: body
    anchors { left: parent.left; right: parent.right; top: rule.bottom; bottom: parent.bottom; margins: theme.borderWidth + theme.px(16) }

    Image {
      anchors.fill: parent
      visible: root.kind === "image"
      source: root.kind === "image" && root.preview.image ? "file://" + root.preview.image : ""
      sourceSize.width: Math.max(1, width * 2)
      sourceSize.height: Math.max(1, height * 2)
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true
      mipmap: true
    }

    Flickable {
      id: flick
      anchors.fill: parent
      visible: root.kind === "text" || root.kind === "markdown" || root.kind === "dir"
      contentWidth: width
      contentHeight: textView.paintedHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Text {
        id: textView
        width: flick.width
        text: root.preview && root.preview.text !== undefined ? root.preview.text : ""
        textFormat: root.kind === "markdown" ? Text.MarkdownText : Text.PlainText
        wrapMode: root.kind === "markdown" ? Text.Wrap : Text.WrapAnywhere
        color: theme.fg
        linkColor: theme.accent
        font.family: root.kind === "markdown" ? theme.font : "monospace"
        font.pixelSize: root.kind === "markdown" ? theme.fontSize : theme.detailSize
        lineHeight: 1.15
      }
    }

    Column {
      anchors.centerIn: parent
      visible: root.kind === "info" || root.kind === "missing" || root.kind === "none" || root.kind === "loading"
      spacing: theme.px(10)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.kind === "loading" ? "" : (root.kind === "info" ? "" : "")
        color: theme.muted
        font.family: theme.font
        font.pixelSize: theme.px(64)
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.kind === "missing" ? "This file no longer exists"
          : root.kind === "none" ? "Nothing to preview"
          : root.kind === "loading" ? "…" : ""
        color: theme.muted
        font.family: theme.font
        font.pixelSize: theme.fontSize
      }
    }
  }

  // Scroll the text with the keyboard while the list keeps focus.
  function scroll(lines) {
    if (!flick.visible) return
    flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + lines * theme.px(18)))
  }

  onPreviewChanged: flick.contentY = 0
}
