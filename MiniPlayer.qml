import QtQuick
import qs.Commons
import "components"

// The Vinyl mini-player card: header (with the Music Library button),
// artwork with track info, progress, and playback controls. Driven by the
// plugin service; each control is enabled only when the selected player
// supports it, and shows the player's reported state. Styling comes from
// Omarchy's system values via `theme` (core/Theme.qml).
GlassSurface {
  id: root

  required property var service

  // Null-safe view of the service. On a plugin hot-reload the shell drops
  // the service a moment before this card is destroyed; show idle meanwhile.
  readonly property var info: service ? service : ({
    hasTrack: false, isPlaying: false, title: "", artist: "", album: "",
    artUrl: "", playerName: "", position: 0, length: 0,
    shuffle: false, repeatOne: false, canTogglePlaying: false, canGoNext: false,
    canGoPrevious: false, canSeek: false, canShuffle: false, canRepeat: false
  })

  signal closeRequested()
  signal libraryRequested()

  readonly property string statusText: !root.info.hasTrack ? ""
    : root.info.isPlaying ? "NOW PLAYING" : "PAUSED"
  readonly property string titleText: !root.info.hasTrack ? "Nothing playing"
    : (root.info.title || "Unknown track")
  readonly property string artistText: !root.info.hasTrack
    ? (root.info.needsLibrarySetup ? "Set up your music library with the library button above"
                                   : "Play something in your music player")
    : (root.info.artist || "Unknown artist")

  width: theme.cardWidth
  height: content.implicitHeight + insetTop + insetBottom
  padding: theme.cardPadding

  Column {
    id: content
    x: root.insetLeft
    y: root.insetTop
    width: root.width - root.insetLeft - root.insetRight

    // ---------------------------------------------------------------- header
    Item {
      width: parent.width
      height: theme.px(24)

      Row {
        anchors.verticalCenter: parent.verticalCenter
        spacing: theme.px(8)

        VinylMark {
          theme: root.theme
          anchors.verticalCenter: parent.verticalCenter
          size: theme.px(18)
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Vinyl"
          textFormat: Text.PlainText
          color: theme.textPrimary
          font.family: theme.fontFamily
          font.pixelSize: theme.fontLabel
          font.bold: true
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Local Music"
          textFormat: Text.PlainText
          color: theme.textMuted
          font.family: theme.fontFamily
          font.pixelSize: theme.fontBody
        }
      }

      // The Music Library, in Omarchy's system glyph; the card's other icons
      // are the approved ones.
      IconButton {
        objectName: "libraryButton"
        theme: root.theme
        anchors.right: closeButton.left
        anchors.rightMargin: Style.spacing.xxs
        anchors.verticalCenter: parent.verticalCenter
        iconName: "library"
        text: "Open Music Library"
        quiet: true
        diameter: theme.px(26)
        iconSize: Style.font.iconLarge
        onClicked: root.libraryRequested()
      }

      ControlButton {
        id: closeButton
        theme: root.theme
        anchors.right: parent.right
        anchors.rightMargin: -theme.px(4)
        anchors.verticalCenter: parent.verticalCenter
        glyph: "close"
        text: "Close"
        quiet: true
        diameter: theme.px(26)
        glyphSize: theme.px(16)
        onClicked: root.closeRequested()
      }
    }

    Item { width: 1; height: theme.px(16) }

    // ---------------------------------------------------------------- hero
    Item {
      width: parent.width
      height: theme.artworkSize

      Artwork {
        id: artwork
        theme: root.theme
        width: theme.artworkSize
        height: theme.artworkSize
        source: root.info.hasTrack ? root.info.artUrl : ""
      }

      Column {
        anchors.left: artwork.right
        anchors.leftMargin: theme.px(16)
        anchors.right: parent.right
        anchors.verticalCenter: artwork.verticalCenter
        spacing: theme.px(3)

        Text {
          width: parent.width
          visible: text !== ""
          text: root.statusText
          textFormat: Text.PlainText
          color: root.info.isPlaying ? theme.accent : theme.textSecondary
          font.family: theme.fontFamily
          font.pixelSize: theme.fontCaption
          font.bold: true
          bottomPadding: theme.px(2)
        }

        Text {
          width: parent.width
          text: root.titleText
          textFormat: Text.PlainText
          color: root.info.hasTrack ? theme.textPrimary : theme.textSecondary
          font.family: theme.fontFamily
          font.pixelSize: theme.fontTitle
          font.bold: true
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: root.artistText
          textFormat: Text.PlainText
          color: root.info.hasTrack ? theme.textSecondary : theme.textMuted
          font.family: theme.fontFamily
          font.pixelSize: root.info.hasTrack ? theme.fontLabel : theme.fontBody
          wrapMode: root.info.hasTrack ? Text.NoWrap : Text.Wrap
          maximumLineCount: root.info.hasTrack ? 1 : 2
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: text !== ""
          text: root.info.album
          textFormat: Text.PlainText
          color: theme.textMuted
          font.family: theme.fontFamily
          font.pixelSize: theme.fontBody
          elide: Text.ElideRight
        }
      }
    }

    Item { width: 1; height: theme.px(18) }

    // ---------------------------------------------------------------- progress
    ProgressBar {
      theme: root.theme
      width: parent.width
      position: root.info.position
      length: root.info.length
      hasPosition: root.info.hasTrack
      enabled: root.info.hasTrack
      seekable: root.info.canSeek
      onSeekRequested: (seconds) => { if (root.service) root.service.seek(seconds) }
    }

    Item { width: 1; height: theme.px(8) }

    // ---------------------------------------------------------------- controls
    PlaybackControls {
      theme: root.theme
      anchors.horizontalCenter: parent.horizontalCenter
      playing: root.info.isPlaying
      shuffle: root.info.shuffle
      repeatOne: root.info.repeatOne
      // Enabled only when the selected player supports the action.
      canPlay: root.info.canTogglePlaying
      canGoPrevious: root.info.canGoPrevious
      canGoNext: root.info.canGoNext
      canShuffle: root.info.canShuffle
      canRepeat: root.info.canRepeat
      onPlayPauseClicked: if (root.service) root.service.togglePlaying()
      onPreviousClicked: if (root.service) root.service.previous()
      onNextClicked: if (root.service) root.service.next()
      onShuffleClicked: if (root.service) root.service.setShuffle(!root.info.shuffle)
      onRepeatClicked: if (root.service) root.service.setRepeatOne(!root.info.repeatOne)
    }

    Item { width: 1; height: theme.px(14) }

    // ---------------------------------------------------------------- footer
    // The selected player's name. Hidden while idle; opacity (not
    // visibility) keeps the card's height identical across states.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      // Explicit, because a Row only measures itself when its window
      // renders; the card must have its final height before first showing.
      height: footerLabel.implicitHeight
      spacing: theme.px(6)
      opacity: root.info.hasTrack && root.info.playerName !== "" ? 1 : 0

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: theme.px(5)
        height: width
        radius: width / 2
        color: theme.textDisabled
      }

      Text {
        id: footerLabel
        anchors.verticalCenter: parent.verticalCenter
        text: root.info.playerName
        textFormat: Text.PlainText
        color: theme.textMuted
        font.family: theme.fontFamily
        font.pixelSize: theme.fontCaption
      }
    }
  }
}
