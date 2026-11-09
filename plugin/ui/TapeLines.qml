import QtQuick

// A tile of one horizontal line, repeated: the worn VHS picture.
Image {
  property int pitch: 3
  property color ink
  property real strength
  property int inset: 0
  anchors.fill: parent
  anchors.margins: inset
  fillMode: Image.Tile
  verticalAlignment: Image.AlignTop
  horizontalAlignment: Image.AlignLeft
  source: "data:image/svg+xml," + encodeURIComponent(
    "<svg xmlns='http://www.w3.org/2000/svg' width='" + pitch + "' height='" + pitch + "'><rect width='" + pitch
    + "' height='1' fill='" + ink + "' fill-opacity='" + strength + "'/></svg>")
}
