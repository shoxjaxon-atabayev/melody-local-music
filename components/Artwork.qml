import QtQuick
import Quickshell.Widgets
import qs.Commons
import qs.Ui

// Album artwork as Omarchy's media plugin shows it: a small-radius tile with
// the normal control fill and border. The player's cover image fills the
// tile; `source` must already be a validated cover URL, a local file or an
// embedded image (Metadata.artUrl in core/Metadata.js). Without one, or if
// it fails to decode, the tile shows a music note.
Item {
  id: root

  required property var theme

  property string source: ""
  property real radius: theme.artworkRadius
  // The library draws the placeholder with Omarchy's system glyph; the
  // mini-player keeps its approved note.
  property bool systemIcon: false

  readonly property bool available: source !== "" && image.status === Image.Ready
  readonly property var borderSpec: Border.controlSpec("normal", theme.textPrimary, theme.accent)

  implicitWidth: theme.artworkSize
  implicitHeight: theme.artworkSize

  BorderSurface {
    anchors.fill: parent
    radius: root.radius
    color: Style.normalFillFor(theme.textPrimary, theme.accent)
    borderSpec: root.borderSpec

    Glyph {
      anchors.centerIn: parent
      width: root.width * 0.36
      height: width
      name: "note"
      color: theme.textPrimary
      visible: !root.available && !root.systemIcon
    }

    Icon {
      anchors.centerIn: parent
      name: "note"
      size: Math.round(root.width * 0.4)
      color: theme.textPrimary
      visible: !root.available && root.systemIcon
    }
  }

  ClippingRectangle {
    anchors.fill: parent
    radius: root.radius
    color: "transparent"
    visible: root.available

    // Local files only; decoded asynchronously and bounded to 2× the
    // displayed size so large covers don't sit in memory at full resolution.
    Image {
      id: image
      anchors.fill: parent
      source: root.source
      asynchronous: true
      cache: false
      fillMode: Image.PreserveAspectCrop
      sourceSize: Qt.size(Math.ceil(root.width * 2), Math.ceil(root.height * 2))
      smooth: true
      mipmap: true
    }
  }

  // The tile's border drawn over the cover.
  BorderSurface {
    anchors.fill: parent
    radius: root.radius
    color: "transparent"
    borderSpec: root.borderSpec
    visible: root.available
  }
}
