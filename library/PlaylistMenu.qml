import QtQuick
import qs.Commons
import "../components"
import qs.Ui

// "Add to playlist" menu, drawn like Omarchy's Dropdown popup (popup
// border, corner radius, popup-row-height rows, hover fill for the current
// row), on the opaque background Omarchy's in-panel ConfirmDialog uses, so
// the list underneath never shows through. Lists the playlists and "New playlist…", which
// turns into a name field. Fills its parent; a click outside closes it.
// Keyboard (via handleKey from the window): Up/Down, Enter, Escape.
Item {
  id: root

  required property var theme
  property var playlists: []
  property int trackCount: 0
  property bool opened: false
  // Right edge and top of the menu, in this item's coordinates; it opens
  // above `anchorAbove` instead when there is no room below.
  property real anchorRight: 0
  property real anchorTop: 0
  property real anchorAbove: 0
  property bool naming: false
  property string error: ""

  signal chosen(string id)
  signal createRequested(string name)
  signal closeRequested()
  signal restoreFocus()

  property int currentIndex: 0
  readonly property int itemCount: playlists.length + 1
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border,
                                                                   Color.popups.border, Style.normalBorderWidth)

  visible: opened

  onCurrentIndexChanged: if (currentIndex < playlists.length) optionList.positionViewAtIndex(currentIndex, ListView.Contain)

  onOpenedChanged: {
    if (opened) optionList.positionViewAtBeginning()
    currentIndex = 0
    naming = false
    error = ""
  }

  function startNaming() {
    naming = true
    error = ""
    nameField.text = ""
    nameField.forceActiveFocus()
  }

  function choose(index) {
    if (index < playlists.length) chosen(playlists[index].id)
    else startNaming()
  }

  // Returns true if the menu handled the key.
  function handleKey(event) {
    if (!opened) return false
    if (event.key === Qt.Key_Escape) {
      if (naming) { naming = false; error = ""; restoreFocus() }
      else closeRequested()
      return true
    }
    // Keys the name field didn't take (arrows, Tab) stay in the menu.
    if (naming) return true
    if (event.key === Qt.Key_Down) { currentIndex = Math.min(itemCount - 1, currentIndex + 1); return true }
    if (event.key === Qt.Key_Up) { currentIndex = Math.max(0, currentIndex - 1); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { choose(currentIndex); return true }
    return true
  }

  MouseArea {
    anchors.fill: parent
    onPressed: root.closeRequested()
  }

  BorderSurface {
    id: popup
    objectName: "playlistMenu"
    x: Math.max(0, root.anchorRight - width)
    y: root.anchorTop + height <= root.height ? root.anchorTop : Math.max(0, root.anchorAbove - height)
    width: Style.space(260)
    height: column.implicitHeight + Style.spacing.md * 2
    color: Color.background
    borderSpec: root.popupBorderSpec
    radius: Style.cornerRadius

    // Swallow clicks on the menu itself.
    MouseArea { anchors.fill: parent }

    Column {
      id: column
      x: Style.spacing.md
      y: Style.spacing.md
      width: popup.width - Style.spacing.md * 2
      spacing: Style.spacing.labelGap

      PanelSectionHeader {
        x: Style.spacing.md
        height: Style.space(22)
        foreground: theme.textPrimary
        text: "ADD " + root.trackCount + (root.trackCount === 1 ? " TRACK TO" : " TRACKS TO")
      }

      // Like Omarchy's Dropdown: at most 8 rows, then the list scrolls.
      ListView {
        id: optionList
        width: column.width
        height: Math.min(contentHeight, Style.spacing.popupRowHeight * 8 + Style.spacing.labelGap * 7)
        clip: true
        spacing: Style.spacing.labelGap
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        model: root.playlists

        delegate: Rectangle {
          required property var modelData
          required property int index
          objectName: "menu-" + modelData.id
          width: optionList.width
          height: Style.spacing.popupRowHeight
          radius: Math.min(Style.cornerRadius, height / 2)
          color: index === root.currentIndex || itemMouse.containsMouse
            ? Style.hoverFillFor(theme.textPrimary, theme.accent) : "transparent"

          Icon {
            id: itemIcon
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            name: "playlist"
            size: Style.font.iconLarge
            color: theme.textSecondary
          }

          Text {
            anchors.left: itemIcon.right
            anchors.leftMargin: Style.spacing.lg
            anchors.right: entryCount.left
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.name
            textFormat: Text.PlainText
            color: theme.textPrimary
            font.family: theme.fontFamily
            font.pixelSize: theme.fontBody
            elide: Text.ElideRight
          }

          Text {
            id: entryCount
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: String(modelData.count)
            textFormat: Text.PlainText
            color: theme.textMuted
            font.family: theme.fontFamily
            font.pixelSize: theme.fontCaption
          }

          MouseArea {
            id: itemMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.currentIndex = index
            onClicked: root.choose(index)
          }
        }
      }

      PanelSeparator {
        width: column.width
        foreground: theme.textPrimary
      }

      Rectangle {
        objectName: "menu-new"
        visible: !root.naming
        width: column.width
        height: Style.spacing.popupRowHeight
        radius: Math.min(Style.cornerRadius, height / 2)
        color: root.currentIndex === root.playlists.length || newMouse.containsMouse
          ? Style.hoverFillFor(theme.textPrimary, theme.accent) : "transparent"

        Icon {
          id: newIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          name: "plus"
          size: Style.font.iconLarge
          color: theme.textSecondary
        }

        Text {
          anchors.left: newIcon.right
          anchors.leftMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          text: "New playlist…"
          textFormat: Text.PlainText
          color: theme.textPrimary
          font.family: theme.fontFamily
          font.pixelSize: theme.fontBody
        }

        MouseArea {
          id: newMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.currentIndex = root.playlists.length
          onClicked: root.startNaming()
        }
      }

      TextField {
        id: nameField
        objectName: "menuNameField"
        visible: root.naming
        width: column.width
        foreground: theme.textPrimary
        placeholderText: "Playlist name"
        Keys.onReturnPressed: root.createRequested(text)
        Keys.onEnterPressed: root.createRequested(text)
      }

      Text {
        visible: root.naming && root.error !== ""
        width: column.width
        leftPadding: Style.spacing.md
        text: root.error
        textFormat: Text.PlainText
        color: Color.urgent
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSmall
        wrapMode: Text.Wrap
      }
    }
  }
}
