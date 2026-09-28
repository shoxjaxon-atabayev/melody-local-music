import QtQuick
import qs.Commons
import "../components"
import qs.Ui

// Centered empty / error state: icon, title, detail, optional command line,
// and up to two actions (Omarchy Buttons).
Item {
  id: root

  required property var theme

  property string icon: "folder"      // a Icon name
  property bool error: false
  property string title: ""
  property string detail: ""
  property string command: ""
  property string primaryAction: ""
  property string secondaryAction: ""

  signal primaryClicked()
  signal secondaryClicked()

  Column {
    anchors.centerIn: parent
    width: Math.min(parent.width, Style.space(440))
    spacing: Style.spacing.lg

    Icon {
      anchors.horizontalCenter: parent.horizontalCenter
      name: root.icon
      size: Style.space(40)
      color: root.error ? Color.urgent : theme.textSecondary
    }

    Text {
      objectName: "emptyTitle"
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: root.title
      textFormat: Text.PlainText
      color: theme.textPrimary
      font.family: theme.fontFamily
      font.pixelSize: theme.fontLabel
      font.bold: true
      wrapMode: Text.Wrap
    }

    Text {
      objectName: "emptyDetail"
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      visible: text !== ""
      text: root.detail
      textFormat: Text.PlainText
      color: theme.textMuted
      font.family: theme.fontFamily
      font.pixelSize: theme.fontBody
      wrapMode: Text.Wrap
    }

    BorderSurface {
      visible: root.command !== ""
      anchors.horizontalCenter: parent.horizontalCenter
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

    Row {
      visible: root.primaryAction !== "" || root.secondaryAction !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.spacing.controlGap

      Button {
        objectName: "emptySecondary"
        visible: root.secondaryAction !== ""
        text: root.secondaryAction
        bordered: true
        foreground: theme.textPrimary
        onClicked: root.secondaryClicked()
      }

      Button {
        objectName: "emptyPrimary"
        visible: root.primaryAction !== ""
        text: root.primaryAction
        bordered: true
        active: true
        foreground: theme.textPrimary
        onClicked: root.primaryClicked()
      }
    }
  }
}
