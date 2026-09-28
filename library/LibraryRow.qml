import QtQuick
import qs.Commons
import "../components"
import qs.Ui

// One list row: a section header, a folder, or a track (optionally with its
// location, for search results and playlists). Omarchy list conventions:
// hover/cursor use the hover fill; selected tracks use the selection fill
// with a check; the playing track is the "current" item (selected fill and
// accent text).
Item {
  id: root

  required property var theme
  required property var row
  property bool cursor: false
  property bool playing: false
  property bool selected: false
  property bool dimmed: false
  // Hover action for tracks: "add" (add to playlist), "remove" (from this
  // playlist), or "" for none.
  property string action: ""

  signal picked(int modifiers)
  signal activated()
  signal actionRequested()

  readonly property bool isHeader: row.kind === "header"
  readonly property bool isTrack: row.kind === "track"
  // Unavailable tracks (a playlist entry that is missing, outside this
  // library, or otherwise invalid) are dimmed, labelled, and never played.
  readonly property bool missing: !!row.unavailable
  readonly property bool hot: mouse.containsMouse && !isHeader
  // What the leading slot shows: "folder", "check" (selected), "bars" (the
  // playing track), "play" (hover/cursor hint), or "number" (the file
  // name's own number, or the position in a playlist; empty when none).
  readonly property string leading: isHeader ? ""
    : row.kind === "folder" ? "folder"
    : selected ? "check"
    : playing ? "bars"
    : (hot || cursor) && !missing ? "play"
    : "number"

  height: isHeader ? Style.space(26) : Style.spacing.popupRowHeight + Style.spacing.sm

  PanelSectionHeader {
    visible: root.isHeader
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.xs
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.spacing.xs
    foreground: theme.textPrimary
    text: root.isHeader
      ? root.row.label.toUpperCase() + "  ·  " + String(root.row.count).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
      : ""
  }

  Rectangle {
    visible: !root.isHeader
    anchors.fill: parent
    radius: Math.min(Style.cornerRadius, height / 2)
    color: root.selected ? Style.selectionFillFor(theme.textPrimary, theme.accent)
      : root.playing ? Style.selectedFillFor(theme.textPrimary, theme.accent)
      : (root.hot || root.cursor) ? Style.hoverFillFor(theme.textPrimary, theme.accent)
      : "transparent"

    Behavior on color {
      ColorAnimation { duration: theme.durControl }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: !root.isHeader
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: (event) => root.row.kind === "folder" ? root.activated() : root.picked(event.modifiers)
    onDoubleClicked: (event) => {
      if (root.isTrack && !(event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) root.activated()
    }

    // Row content lives inside the MouseArea so hovering the row's own
    // action button keeps the row hovered.
    Item {
      anchors.fill: parent
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      visible: !root.isHeader
      opacity: root.dimmed || root.missing ? 0.5 : 1

      Item {
        id: lead
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(26)
        height: Style.space(16)

        Icon {
          visible: root.leading === "folder"
          anchors.verticalCenter: parent.verticalCenter
          name: "folder"
          size: Style.font.iconLarge
          color: theme.textSecondary
        }

        Icon {
          visible: root.leading === "check"
          anchors.verticalCenter: parent.verticalCenter
          name: "check"
          size: Style.font.iconLarge
          color: theme.accent
        }

        Text {
          visible: root.leading === "number"
          anchors.verticalCenter: parent.verticalCenter
          text: root.row.number === undefined ? "" : (root.row.number < 10 ? "0" : "") + root.row.number
          textFormat: Text.PlainText
          color: theme.textMuted
          font.family: theme.fontFamily
          font.pixelSize: theme.fontSmall
        }

        Icon {
          visible: root.leading === "play"
          anchors.verticalCenter: parent.verticalCenter
          name: "play"
          size: Style.font.iconLarge
          color: theme.textPrimary
        }

        PlayingBars {
          theme: root.theme
          visible: root.leading === "bars"
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Text {
        id: name
        anchors.left: lead.right
        anchors.leftMargin: Style.spacing.sm
        anchors.right: trailing.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        text: root.isTrack ? root.row.title : (root.row.name || "")
        textFormat: Text.PlainText
        color: root.playing ? theme.accent : theme.textPrimary
        font.family: theme.fontFamily
        font.pixelSize: theme.fontBody
        font.bold: root.playing
        elide: Text.ElideRight
      }

      Row {
        id: trailing
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.lg

        Text {
          visible: text !== ""
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, Style.space(220))
          text: root.row.location || ""
          textFormat: Text.PlainText
          color: theme.textMuted
          font.family: theme.fontFamily
          font.pixelSize: theme.fontSmall
          elide: Text.ElideMiddle
        }

        Text {
          visible: root.missing
          anchors.verticalCenter: parent.verticalCenter
          text: root.row.statusLabel || "Missing"
          textFormat: Text.PlainText
          color: Color.urgent
          font.family: theme.fontFamily
          font.pixelSize: theme.fontCaption
          font.bold: true
        }

        // Shown on hover only; its space is always reserved so the row
        // doesn't shift.
        IconButton {
          objectName: "rowAction"
          visible: root.isTrack && root.action !== ""
          opacity: root.hot ? 1 : 0
          enabled: root.hot
          theme: root.theme
          anchors.verticalCenter: parent.verticalCenter
          iconName: root.action === "remove" ? "playlistRemove" : "playlistAdd"
          text: root.action === "remove" ? "Remove from playlist" : "Add to playlist"
          quiet: true
          diameter: Style.space(24)
          iconSize: Style.font.iconLarge
          onClicked: root.actionRequested()
        }

        Text {
          visible: root.isTrack
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(30)
          horizontalAlignment: Text.AlignRight
          text: root.row.ext || ""
          textFormat: Text.PlainText
          color: theme.textMuted
          font.family: theme.fontFamily
          font.pixelSize: theme.fontCaption
        }

        Icon {
          visible: root.row.kind === "folder"
          anchors.verticalCenter: parent.verticalCenter
          name: "chevron"
          size: Style.font.iconLarge
          color: theme.textMuted
        }
      }
    }
  }
}
