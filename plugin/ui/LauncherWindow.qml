import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// The launcher surface (docs/SPEC.md §2, §6): a transparent overlay that
// takes the keyboard, with the card centred on the screen.
PanelWindow {
  id: window

  required property var launcher
  property bool shown: false

  readonly property real z: launcher.zoom
  function px(v) { return Math.round(v * window.z) }

  readonly property color bg: Color.menu.background
  readonly property color fg: Color.menu.text
  // Same frame as the Omarchy menu: theme border colour, Style.space(2) wide
  // unless the theme sets its own width.
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  readonly property color border: borderSpec.color
  readonly property int borderWidth: Math.round(Border.top(borderSpec))
  readonly property color accent: Color.accent
  readonly property color muted: Color.muted
  readonly property color selBg: Color.menu.selectedBackground
  readonly property color selFg: Color.menu.selectedText
  readonly property string font: Style.resolvedFontFamily
  readonly property int fontSize: Math.max(9, Math.round(Style.fontBaseSize * window.z))
  // Text sizes of the Omarchy menu (Style.font tokens), scaled by zoom.
  readonly property int titleSize: px(Style.font.heading)
  readonly property int detailSize: px(Style.font.bodySmall)
  readonly property int captionSize: px(Style.font.caption)
  readonly property int iconSize: px(Style.font.iconLarge)

  readonly property int cardWidth: Math.min(px(760), width - 2 * Style.gapsOut)
  readonly property int rowHeight: px(Math.max(Style.space(50), Style.font.body + Style.spacing.rowPaddingX * 2))
  readonly property int headerHeight: px(28)
  readonly property int searchHeight: px(60)
  readonly property int footerHeight: px(36)
  readonly property int listMax: Math.min(px(430), Math.round(height * 0.6))

  visible: shown
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omalaunch"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  function focusSearch(selectAll) {
    Qt.callLater(function() {
      search.forceActiveFocus()
      if (selectAll) search.selectAll()
    })
  }

  function syncSearchText(text) {
    if (search.text !== text) search.text = text
  }

  // Flat index (headers included) of the selected item.
  function selectedFlatIndex() {
    var flat = launcher.flat
    for (var i = 0; i < flat.length; i++) if (!flat[i].header && flat[i].ordinal === launcher.selected) return i
    return -1
  }

  onShownChanged: if (shown) { pointerGate.moved = false; pointerGate.last = Qt.point(-1, -1); focusSearch(true) }

  MouseArea {
    anchors.fill: parent
    onClicked: launcher.hide()
  }

  Rectangle {
    id: card
    width: window.cardWidth
    height: window.searchHeight + listArea.height + window.footerHeight + 2 * window.borderWidth
    // With Quick Look open, card and preview are centred together.
    x: Math.round((window.width - width - (launcher.previewOpen ? window.previewSize.w + window.previewGap : 0)) / 2)
    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    // Centred at its tallest, so the search field stays put while the list
    // grows and shrinks with the results.
    y: Math.max(Style.gapsOut, Math.round((window.height - (window.searchHeight + window.listMax + window.footerHeight + 2 * window.borderWidth)) / 2))
    color: window.bg
    border.color: window.border
    border.width: window.borderWidth
    radius: Style.cornerRadius
    clip: true

    MouseArea { anchors.fill: parent; onClicked: { launcher.actionPanelOpen = false; window.focusSearch(false) } }

    // ------------------------------------------------------------ search
    Item {
      id: searchBar
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: window.borderWidth }
      height: window.searchHeight

      Text {
        id: lead
        anchors { left: parent.left; leftMargin: window.px(20); verticalCenter: parent.verticalCenter }
        text: launcher.promptMode ? "󰌌" : (launcher.stack.length ? "\uf060" : "\uf002")
        color: launcher.stack.length || launcher.promptMode ? window.accent : window.muted
        font.family: window.font
        font.pixelSize: window.iconSize
        MouseArea { anchors.fill: parent; enabled: launcher.stack.length > 0; onClicked: launcher.back() }
      }

      Text {
        id: crumb
        visible: launcher.stack.length > 0 && launcher.promptMode === ""
        anchors { left: lead.right; leftMargin: window.px(10); verticalCenter: parent.verticalCenter }
        text: launcher.breadcrumb + "  ›"
        color: window.accent
        font.family: window.font
        font.pixelSize: window.titleSize
      }

      TextInput {
        id: search
        anchors {
          left: crumb.visible ? crumb.right : lead.right
          leftMargin: window.px(12)
          right: parent.right
          rightMargin: window.px(20)
          verticalCenter: parent.verticalCenter
        }
        color: window.fg
        selectionColor: Style.selectionFill
        selectedTextColor: window.fg
        font.family: window.font
        font.pixelSize: window.titleSize
        clip: true
        focus: true

        Text {
          anchors.fill: parent
          visible: search.text.length === 0
          text: launcher.promptMode === "alias" ? "Alias for " + (launcher.promptRow ? launcher.promptRow.title : "") + " (empty removes it)"
            : launcher.promptMode === "input" ? launcher.promptLabel
            : launcher.promptMode === "hotkey" ? "Keys for " + (launcher.promptRow ? launcher.promptRow.title : "") + ", e.g. SUPER + SHIFT + B (empty removes them)"
            : (launcher.stack.length ? "Search " + launcher.stack[launcher.stack.length - 1].title + "…" : "Search apps, commands, plugins…")
          color: window.muted
          font: search.font
          elide: Text.ElideRight
        }

        onTextChanged: {
          if (launcher.promptMode) return
          if (text !== launcher.query) launcher.setQuery(text)
        }

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          window.shiftAlone = event.key === Qt.Key_Shift && !event.isAutoRepeat
          if (actionPanel.visible) { if (actionPanel.handleKey(event)) event.accepted = true; return }
          if (window.handleKey(event)) event.accepted = true
        }
        // A Shift tap on its own toggles Quick Look. Some layouts report the
        // release under another key code (Caps Lock here), so any release
        // right after a lone Shift press counts.
        Keys.onReleased: function(event) {
          if (event.isAutoRepeat) return
          if (window.shiftAlone && !actionPanel.visible && !launcher.promptMode) launcher.togglePreview()
          window.shiftAlone = false
        }
      }
    }

    Rectangle {
      anchors { left: parent.left; right: parent.right; top: searchBar.bottom; leftMargin: window.borderWidth; rightMargin: window.borderWidth }
      height: 1
      color: Qt.rgba(window.fg.r, window.fg.g, window.fg.b, 0.10)
    }

    // -------------------------------------------------------------- list
    Item {
      id: listArea
      anchors { left: parent.left; right: parent.right; top: searchBar.bottom; topMargin: 1; leftMargin: window.borderWidth; rightMargin: window.borderWidth }
      height: launcher.flat.length ? Math.min(window.listMax, (launcher.gridActive ? grid.contentHeight : list.contentHeight) + window.px(12)) : window.px(90)

      Text {
        anchors.centerIn: parent
        visible: launcher.flat.length === 0
        text: launcher.query ? "No results" : "Nothing here"
        color: window.muted
        font.family: window.font
        font.pixelSize: window.fontSize
      }

      // Grid of thumbnails (Ctrl+G, or automatic for images and emojis).
      GridView {
        id: grid
        visible: launcher.gridActive
        anchors { fill: parent; topMargin: window.px(6); bottomMargin: window.px(6); leftMargin: window.px(8); rightMargin: window.px(8) }
        clip: true
        model: launcher.gridActive ? launcher.itemsOnly : []
        cellWidth: Math.floor(width / launcher.gridColumns)
        cellHeight: Math.round(cellWidth * 0.78 + window.px(16) + window.detailSize * 1.6 + window.px(12))
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: launcher.gridActive ? launcher.selected : -1
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)

        delegate: ResultTile {
          required property var modelData
          required property int index
          width: grid.cellWidth
          height: grid.cellHeight
          theme: window
          launcher: window.launcher
          row: modelData.row
          selected: index === launcher.selected
          onClicked: { launcher.selected = index; launcher.runIndex(modelData.row, 0) }
          onHovered: if (pointerGate.moved) launcher.selected = index
        }
      }

      ListView {
        id: list
        visible: !launcher.gridActive
        anchors { fill: parent; topMargin: window.px(6); bottomMargin: window.px(6); leftMargin: window.px(8); rightMargin: window.px(8) }
        clip: true
        model: launcher.flat
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: window.selectedFlatIndex()
        highlightFollowsCurrentItem: false
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
        onModelChanged: Qt.callLater(function() { if (list.currentIndex >= 0) list.positionViewAtIndex(list.currentIndex, ListView.Contain); else list.positionViewAtBeginning() })

        delegate: ResultRow {
          required property var modelData
          width: list.width
          entry: modelData
          selected: !modelData.header && modelData.ordinal === launcher.selected ? true : false
          rowHeight: window.rowHeight
          headerHeight: window.headerHeight
          theme: window
          onClicked: { launcher.selected = modelData.ordinal; launcher.runIndex(modelData.row, 0) }
          onHovered: if (pointerGate.moved) launcher.selected = modelData.ordinal
        }
      }

      // Only follow the pointer after it actually moves, so the list does
      // not jump under a resting cursor while typing.
      QtObject {
        id: pointerGate
        property bool moved: false
        property point last: Qt.point(-1, -1)
      }
      HoverHandler {
        onPointChanged: {
          var p = point.scenePosition
          if (pointerGate.last.x < 0) { pointerGate.last = p; return }
          if (Math.abs(p.x - pointerGate.last.x) + Math.abs(p.y - pointerGate.last.y) > 3) pointerGate.moved = true
        }
      }
    }

    // ------------------------------------------------------------ footer
    Rectangle {
      id: footer
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: window.borderWidth }
      height: window.footerHeight
      color: Qt.rgba(window.fg.r, window.fg.g, window.fg.b, 0.04)

      Text {
        anchors { left: parent.left; leftMargin: window.px(16); verticalCenter: parent.verticalCenter; right: hints.left; rightMargin: window.px(12) }
        text: launcher.toastText || "omalaunch"
        color: launcher.toastText ? window.accent : window.muted
        font.family: window.font
        font.pixelSize: window.fontSize * 0.9
        elide: Text.ElideRight
      }

      Row {
        id: hints
        anchors { right: parent.right; rightMargin: window.px(16); verticalCenter: parent.verticalCenter }
        spacing: window.px(16)
        readonly property var primary: launcher.selectedRow ? launcher.actionsFor(launcher.selectedRow)[0] : null

        Text {
          visible: !!hints.primary
          text: (hints.primary ? hints.primary.title : "") + "  ↵"
          color: window.fg
          font.family: window.font
          font.pixelSize: window.fontSize * 0.9
        }
        Text {
          text: "Actions  ⌃K"
          color: window.muted
          font.family: window.font
          font.pixelSize: window.fontSize * 0.9
        }
      }
    }

    ActionPanel {
      id: actionPanel
      visible: launcher.actionPanelOpen && !!launcher.selectedRow
      theme: window
      launcher: window.launcher
      row: launcher.selectedRow
      anchors { right: parent.right; bottom: footer.top; rightMargin: window.px(10); bottomMargin: window.px(6) }
      onVisibleChanged: if (visible) reset()
    }
  }

  // ---------------------------------------------------------- quick look
  // The pane takes the shape of what it shows: an image, PDF page, slide or
  // video frame is fitted to the free area keeping its proportions (tall
  // pages use the full height, slides the full width); text and folders use
  // the full height; anything else stays compact. The card moves left so the
  // pair stays centred.
  readonly property int previewGap: px(12)
  readonly property int cardMaxHeight: window.searchHeight + window.listMax + window.footerHeight + 2 * window.borderWidth
  readonly property int previewMaxWidth: Math.max(px(320), window.width - window.cardWidth - window.previewGap - 4 * Style.gapsOut)
  readonly property int previewMaxHeight: window.height - 4 * Style.gapsOut
  readonly property int previewChromeHeight: window.searchHeight + 1 + 2 * window.borderWidth + 2 * px(16)
  readonly property int previewChromeWidth: 2 * window.borderWidth + 2 * px(16)
  readonly property var previewSize: {
    var d = launcher.previewData
    var kind = d ? d.kind : "none"
    if (kind === "image" && d.width > 0 && d.height > 0) {
      var ratio = d.width / d.height
      var w = Math.min(window.previewMaxWidth - window.previewChromeWidth, (window.previewMaxHeight - window.previewChromeHeight) * ratio)
      // Small images are not blown up past twice their size.
      w = Math.min(w, d.width * 2)
      return { w: Math.max(px(380), Math.round(w + window.previewChromeWidth)), h: Math.round(w / ratio + window.previewChromeHeight) }
    }
    if (kind === "text" || kind === "markdown" || kind === "dir")
      return { w: Math.min(px(900), window.previewMaxWidth), h: window.previewMaxHeight }
    return { w: Math.min(px(560), window.previewMaxWidth), h: window.cardMaxHeight }
  }

  PreviewPane {
    id: preview
    theme: window
    visible: launcher.previewOpen
    preview: launcher.previewData
    x: card.x + card.width + window.previewGap
    y: Math.round((window.height - height) / 2)
    width: window.previewSize.w
    height: window.previewSize.h
    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }


  // ------------------------------------------------------------- keys

  property bool shiftAlone: false

  function handleKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    var row = launcher.selectedRow
    var k = event.key

    if (k === Qt.Key_Escape) { if (shift) launcher.backToRoot(); else launcher.back(); return true }

    if (launcher.promptMode) {
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { launcher.commitPrompt(search.text); return true }
      return false
    }

    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (row) launcher.runIndex(row, ctrl && shift ? 2 : (ctrl ? 1 : 0))
      return true
    }
    if (ctrl && k === Qt.Key_K) { if (row) launcher.actionPanelOpen = true; return true }
    if (ctrl && !shift && k === Qt.Key_Y) { launcher.togglePreview(); return true }
    if (launcher.previewOpen && shift && !ctrl && (k === Qt.Key_Up || k === Qt.Key_Down)) { preview.scroll(k === Qt.Key_Up ? -4 : 4); return true }
    if (ctrl && !shift && k === Qt.Key_L) { if (row) launcher.runAction(row, { id: "omalaunch.large" }); return true }

    if (ctrl && !shift && k === Qt.Key_G) { launcher.toggleGrid(); return true }
    if (launcher.gridActive && !ctrl && !alt && !shift) {
      var cols = launcher.gridColumns
      var n = launcher.itemsOnly.length
      if (k === Qt.Key_Left) { if (launcher.selected > 0) launcher.selected -= 1; return true }
      if (k === Qt.Key_Right) { if (launcher.selected < n - 1) launcher.selected += 1; return true }
      if (k === Qt.Key_Up) { if (launcher.selected >= cols) launcher.selected -= cols; return true }
      if (k === Qt.Key_Down) { if (launcher.selected + cols < n) launcher.selected += cols; else if (launcher.selected < n - 1 && Math.floor(launcher.selected / cols) < Math.floor((n - 1) / cols)) launcher.selected = n - 1; return true }
    }
    if (k === Qt.Key_Up) {
      if (ctrl && alt) { if (row) launcher.runAction(row, { id: "omalaunch.fav-up" }); return true }
      if (ctrl) { launcher.jumpSection(-1); return true }
      if (!search.text && !launcher.stack.length && launcher.selected === 0 && launcher.historyStep(1)) return true
      if (launcher.historyIndex >= 0 && launcher.historyStep(1)) return true
      launcher.move(-1)
      return true
    }
    if (k === Qt.Key_Down) {
      if (ctrl && alt) { if (row) launcher.runAction(row, { id: "omalaunch.fav-down" }); return true }
      if (ctrl) { launcher.jumpSection(1); return true }
      if (launcher.historyIndex >= 0) { launcher.historyStep(-1); return true }
      launcher.move(1)
      return true
    }
    if (ctrl && k === Qt.Key_N) { launcher.move(1); return true }
    if (ctrl && k === Qt.Key_P) { launcher.move(-1); return true }
    if (k === Qt.Key_PageDown) { launcher.move(8); return true }
    if (k === Qt.Key_PageUp) { launcher.move(-8); return true }

    if (ctrl && !shift && k >= Qt.Key_1 && k <= Qt.Key_9) { launcher.runOrdinal(k - Qt.Key_1); return true }

    if (ctrl && shift && k === Qt.Key_F) { if (row) launcher.runAction(row, { id: "omalaunch.favorite" }); return true }
    if (ctrl && shift && k === Qt.Key_C) { if (row) launcher.runAction(row, { id: "omalaunch.copy" }); return true }
    if (ctrl && shift && k === Qt.Key_A) { if (row && launcher.isCatalogRow(row)) launcher.beginAlias(row); return true }
    if (ctrl && shift && k === Qt.Key_H) { if (row && launcher.isCatalogRow(row)) launcher.beginHotkey(row); return true }
    if (alt && shift && k === Qt.Key_D) { if (row && launcher.isCatalogRow(row)) launcher.runAction(row, { id: "omalaunch.disable" }); return true }

    if (ctrl && (k === Qt.Key_Plus || k === Qt.Key_Equal)) { launcher.setZoom(window.z + 0.1); return true }
    if (ctrl && k === Qt.Key_Minus) { launcher.setZoom(window.z - 0.1); return true }
    if (ctrl && k === Qt.Key_0) { launcher.setZoom(1); return true }

    if (k === Qt.Key_Backspace && !search.text && launcher.stack.length) { launcher.popView(); return true }

    // Emacs-style editing.
    if (ctrl && !shift) {
      if (k === Qt.Key_A) { search.cursorPosition = 0; return true }
      if (k === Qt.Key_E) { search.cursorPosition = search.text.length; return true }
      if (k === Qt.Key_B) { search.cursorPosition = Math.max(0, search.cursorPosition - 1); return true }
      if (k === Qt.Key_F) { search.cursorPosition = Math.min(search.text.length, search.cursorPosition + 1); return true }
      if (k === Qt.Key_U) { search.remove(0, search.cursorPosition); return true }
      if (k === Qt.Key_W) {
        var pos = search.cursorPosition
        var before = search.text.slice(0, pos)
        var cut = before.replace(/\S+\s*$/, "").length
        search.remove(cut, pos)
        return true
      }
    }
    return false
  }
}
