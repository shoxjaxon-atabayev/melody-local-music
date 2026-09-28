import QtQuick
import qs.Commons
import "../components"
import qs.Ui

// Inline notice above the track list (no player, limit reached, open
// failed), drawn as an Omarchy control surface. Errors use the theme's
// urgent color.
BorderSurface {
  id: root

  required property var theme

  property string icon: error ? "alert" : "info"
  property bool error: false
  property string title: ""
  property string detail: ""
  property string command: ""

  implicitHeight: content.implicitHeight + Style.spacing.controlPaddingY * 2 + Style.spacing.xs * 2
  radius: Style.cornerRadius
  color: Style.normalFillFor(theme.textPrimary, theme.accent)
  borderSpec: Border.controlSpec("normal", theme.textPrimary, theme.accent)

  Row {
    id: content
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.rowPaddingX
    spacing: Style.spacing.lg

    Icon {
      id: noticeIcon
      anchors.verticalCenter: parent.verticalCenter
      name: root.icon
      size: Style.font.iconLarge
      color: root.error ? Color.urgent : theme.textSecondary
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - noticeIcon.width - parent.spacing
        - (commandChip.visible ? commandChip.width + parent.spacing : 0)
      spacing: Style.spacing.xxs

      Text {
        width: parent.width
        text: root.title
        textFormat: Text.PlainText
        color: root.error ? Color.urgent : theme.textPrimary
        font.family: theme.fontFamily
        font.pixelSize: theme.fontBody
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: root.detail
        textFormat: Text.PlainText
        color: theme.textMuted
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSmall
        elide: Text.ElideRight
      }
    }

    BorderSurface {
      id: commandChip
      visible: root.command !== ""
      anchors.verticalCenter: parent.verticalCenter
      width: commandText.implicitWidth + Style.spacing.controlPaddingX * 2
      height: commandText.implicitHeight + Style.spacing.controlPaddingY * 2
      radius: Math.min(Style.cornerRadius, height / 2)
      color: Style.normalFillFor(theme.textPrimary, theme.accent)
      borderSpec: Border.controlSpec("normal", theme.textPrimary, theme.accent)

      Text {
        id: commandText
        anchors.centerIn: parent
        text: root.command
        textFormat: Text.PlainText
        color: theme.textPrimary
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSmall
      }
    }
  }
}
