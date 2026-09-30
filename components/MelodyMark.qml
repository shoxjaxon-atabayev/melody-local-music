import QtQuick
import qs.Commons

// Melody's app mark: an accent tile with three static level bars, using the
// theme's accent and background and Omarchy's small-tile radius.
Rectangle {
  id: root

  required property var theme

  property real size: Style.space(18)

  width: size
  height: size
  radius: Style.spacing.labelGap
  color: theme.accent

  Row {
    anchors.centerIn: parent
    spacing: Math.max(1, Math.round(root.size * 0.1))

    Repeater {
      model: [0.34, 0.58, 0.42]

      Rectangle {
        required property real modelData
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(1.5, root.size * 0.11)
        height: root.size * modelData
        radius: width / 2
        color: Color.background
      }
    }
  }
}
