import QtQuick
import qs.Commons
import qs.Ui

// Card surface: Omarchy's popup surface — the theme's popup background,
// border, and corner radius, drawn with Omarchy's own BorderSurface, as
// Omarchy's panels do. Content is laid out inside `inset*` (border + padding).
Item {
  id: root

  required property var theme

  property real radius: Style.cornerRadius
  property real padding: 0
  default property alias content: contentArea.data

  readonly property real insetTop: surface.contentTopInset
  readonly property real insetRight: surface.contentRightInset
  readonly property real insetBottom: surface.contentBottomInset
  readonly property real insetLeft: surface.contentLeftInset

  BorderSurface {
    id: surface
    anchors.fill: parent
    radius: root.radius
    padding: root.padding
    color: theme.surface
    borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  }

  Item {
    id: contentArea
    anchors.fill: parent
  }
}
