import QtQuick
import qs.Commons
import "../components"
import qs.Ui

// Bottom strip: the player's current track (from its metadata) and where it
// sits in Vinyl's session queue. Informational; playback controls stay in the
// mini-player.
Item {
  id: root

  required property var theme
  property bool hasTrack: true
  property string title: ""
  property string subtitle: ""
  property string cover: ""
  property string position: ""
  property string player: ""
  property string idleDetail: "Choose a track and press Enter to play it"

  implicitHeight: Style.space(52)

  PanelSeparator {
    anchors.top: parent.top
    foreground: theme.textPrimary
  }

  Artwork {
    id: art
    systemIcon: true
    theme: root.theme
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: Style.spacing.xxs
    width: Style.space(36)
    height: width
    source: root.hasTrack ? root.cover : ""
  }

  Column {
    anchors.left: art.right
    anchors.leftMargin: Style.spacing.xl
    anchors.right: meta.left
    anchors.rightMargin: Style.spacing.xl
    anchors.verticalCenter: art.verticalCenter
    spacing: Style.spacing.xxs

    Text {
      width: parent.width
      text: root.hasTrack ? root.title : "Nothing playing"
      textFormat: Text.PlainText
      color: root.hasTrack ? theme.textPrimary : theme.textSecondary
      font.family: theme.fontFamily
      font.pixelSize: theme.fontBody
      font.bold: true
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: root.hasTrack ? root.subtitle : root.idleDetail
      textFormat: Text.PlainText
      color: theme.textMuted
      font.family: theme.fontFamily
      font.pixelSize: theme.fontSmall
      elide: Text.ElideRight
    }
  }

  Row {
    id: meta
    anchors.right: parent.right
    anchors.verticalCenter: art.verticalCenter
    spacing: Style.spacing.lg
    visible: root.hasTrack

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: text !== ""
      text: root.position
      textFormat: Text.PlainText
      color: theme.textMuted
      font.family: theme.fontFamily
      font.pixelSize: theme.fontSmall
    }

    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(5)
        height: width
        radius: width / 2
        color: theme.textDisabled
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.player
        textFormat: Text.PlainText
        color: theme.textMuted
        font.family: theme.fontFamily
        font.pixelSize: theme.fontCaption
      }
    }
  }
}
