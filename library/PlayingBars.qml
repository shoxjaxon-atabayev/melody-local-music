import QtQuick
import qs.Commons
import "../components"

// Three static accent bars: "this is playing" in lists and the sidebar.
Row {
  id: root

  required property var theme

  spacing: Style.space(2)

  Repeater {
    model: [0.5, 0.9, 0.65]

    Rectangle {
      required property real modelData
      anchors.bottom: parent.bottom
      width: Style.space(3)
      height: Style.space(12) * modelData
      radius: width / 2
      color: root.theme.accent
    }
  }
}
