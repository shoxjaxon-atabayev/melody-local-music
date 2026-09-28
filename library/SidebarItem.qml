import QtQuick
import qs.Commons
import "../components"

// One sidebar entry (the library, a playlist, "New playlist"). Omarchy list
// conventions: hover uses the hover fill; the open view is the selected
// item (selected fill, bold label). Playing bars mark the source that is
// playing now.
Item {
  id: root

  required property var theme

  property string iconName: "folder"
  property string label: ""
  property string detail: ""
  property bool current: false
  property bool playing: false
  property bool quiet: false

  signal clicked()

  readonly property bool hot: mouse.containsMouse

  height: Style.spacing.popupRowHeight + Style.spacing.xs

  Rectangle {
    anchors.fill: parent
    radius: Math.min(Style.cornerRadius, height / 2)
    color: root.current ? Style.selectedFillFor(theme.textPrimary, theme.accent)
      : root.hot ? Style.hoverFillFor(theme.textPrimary, theme.accent)
      : "transparent"

    Behavior on color {
      ColorAnimation { duration: theme.durControl }
    }
  }

  Icon {
    id: icon
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.xl
    anchors.verticalCenter: parent.verticalCenter
    name: root.iconName
    size: Style.font.iconLarge
    color: root.current || root.hot ? theme.textPrimary : theme.textSecondary
  }

  Text {
    anchors.left: icon.right
    anchors.leftMargin: Style.spacing.lg
    anchors.right: trailing.left
    anchors.rightMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    textFormat: Text.PlainText
    color: root.quiet && !root.hot ? theme.textSecondary : theme.textPrimary
    font.family: theme.fontFamily
    font.pixelSize: theme.fontBody
    font.bold: root.current
    elide: Text.ElideRight
  }

  Item {
    id: trailing
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.xl
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(bars.width, count.implicitWidth)
    height: Style.space(12)

    PlayingBars {
      id: bars
      theme: root.theme
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      visible: root.playing
    }

    Text {
      id: count
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.playing && text !== ""
      text: root.detail
      textFormat: Text.PlainText
      color: theme.textMuted
      font.family: theme.fontFamily
      font.pixelSize: theme.fontCaption
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
