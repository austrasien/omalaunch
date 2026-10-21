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
  readonly property string captionText: root.preview && root.preview.caption ? root.preview.caption : ""
  readonly property bool scrolls: root.kind === "text" || root.kind === "markdown" || root.kind === "dir" || root.kind === "rich" || root.kind === "pages"
  readonly property var activeFlick: root.kind === "pages" ? pagesFlick : flick

  Item {
    id: body
    anchors { left: parent.left; right: parent.right; top: rule.bottom; bottom: captionBox.top; margins: theme.borderWidth + theme.px(16) }

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

    // PDF pages, one under the other.
    Flickable {
      id: pagesFlick
      anchors.fill: parent
      visible: root.kind === "pages"
      contentWidth: width
      contentHeight: pagesColumn.height
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: pagesColumn
        width: pagesFlick.width
        spacing: theme.px(12)
        Repeater {
          model: root.kind === "pages" && root.preview.pages ? root.preview.pages : []
          delegate: Image {
            required property var modelData
            width: pagesColumn.width
            height: root.preview && root.preview.width ? Math.round(width * root.preview.height / root.preview.width) : width * 1.414
            source: "file://" + modelData
            sourceSize.width: Math.max(1, width * 2)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
          }
        }
      }
    }

    Flickable {
      id: flick
      anchors.fill: parent
      visible: root.kind === "text" || root.kind === "markdown" || root.kind === "dir" || root.kind === "rich"
      contentWidth: width
      contentHeight: textView.paintedHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Text {
        id: textView
        readonly property bool code: root.kind === "rich" && /^<pre>/.test(root.preview.html || "")
        width: flick.width
        text: !root.preview ? "" : (root.kind === "rich" ? (root.preview.html || "") : (root.preview.text !== undefined ? root.preview.text : ""))
        textFormat: root.kind === "markdown" ? Text.MarkdownText : (root.kind === "rich" ? Text.RichText : Text.PlainText)
        wrapMode: root.kind === "markdown" || root.kind === "rich" ? Text.Wrap : Text.WrapAnywhere
        color: theme.fg
        linkColor: theme.accent
        font.family: root.kind === "markdown" || (root.kind === "rich" && !code) ? theme.font : "monospace"
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
        text: root.kind === "loading" ? "" : (root.kind === "info" ? "\uf15b" : "\uf06e")
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

  // Details under the picture: dimensions, duration, title and author…
  Item {
    id: captionBox
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: theme.borderWidth }
    height: root.captionText ? captionLabel.paintedHeight + theme.px(24) : 0
    visible: root.captionText !== ""

    Text {
      id: captionLabel
      anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: theme.px(20); rightMargin: theme.px(20) }
      text: root.captionText
      textFormat: Text.RichText
      wrapMode: Text.Wrap
      color: theme.muted
      font.family: theme.font
      font.pixelSize: theme.detailSize
      horizontalAlignment: root.kind === "info" ? Text.AlignHCenter : Text.AlignLeft
    }
  }

  // Scroll the text or pages with the keyboard while the list keeps focus.
  function scroll(lines) {
    var f = root.activeFlick
    if (!f.visible) return
    f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, f.contentY + lines * theme.px(18)))
  }

  onPreviewChanged: { flick.contentY = 0; pagesFlick.contentY = 0 }
}
