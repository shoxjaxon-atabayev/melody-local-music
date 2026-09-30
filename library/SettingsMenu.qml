import QtQuick
import qs.Commons
import "../core/BarDisplay.js" as BarDisplay
import qs.Ui

// Settings, opened from the cog in the Library header and drawn like the
// "Add to playlist" menu (Omarchy's popup border and radius, on the opaque
// background of its in-panel ConfirmDialog). How the bar shows the current
// track: the display mode and, for Track Info, what its text shows. A
// choice applies at once and is saved with Melody's entry in shell.json.
// Fills its parent; a click outside closes it.
// Keyboard: Left/Right and Enter pick a choice, Up/Down or Tab move between
// the rows, Escape closes.
Item {
  id: root

  required property var theme
  required property var service
  property bool opened: false
  // Right edge and top of the menu, in this item's coordinates.
  property real anchorRight: 0
  property real anchorTop: 0

  signal closeRequested()

  readonly property string mode: service ? service.displayMode : BarDisplay.TRACK_INFO
  readonly property string label: service ? service.trackLabel : BarDisplay.LABEL_ARTIST_TITLE
  readonly property bool labelShown: mode === BarDisplay.TRACK_INFO
  // The chosen text, for the song that's playing (or a sample one).
  readonly property string labelExample: service && service.hasTrack
    ? BarDisplay.trackLabel(service.artist, service.displayTitle || "Unknown track", label)
    : BarDisplay.trackLabel("Artist Name", "Song Title", label)
  readonly property string cavaState: service ? service.audio.cavaState : "unknown"
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border,
                                                                   Color.popups.border, Style.normalBorderWidth)

  readonly property string modeDetail: {
    if (mode === BarDisplay.SPECTRUM) {
      if (cavaState === "missing")
        return "Spectrum needs cava, which isn’t installed. Install it with “omarchy pkg add cava”, then choose Spectrum again."
      if (cavaState === "checking") return "Checking for cava…"
      return "Frequency bars from your music player’s audio, measured by cava."
    }
    if (mode === BarDisplay.PULSE_DOTS) return "Dots that follow how loud your music player’s audio is."
    return "The song that’s playing, after a pause or play sign."
  }

  visible: opened

  onOpenedChanged: if (opened) modes.forceActiveFocus()

  // Returns true if the menu handled the key.
  function handleKey(event) {
    if (!opened) return false
    if (event.key === Qt.Key_Escape) closeRequested()
    else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { if (labelShown) labels.forceActiveFocus() }
    else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) modes.forceActiveFocus()
    return true
  }

  MouseArea {
    anchors.fill: parent
    onPressed: root.closeRequested()
  }

  BorderSurface {
    id: popup
    objectName: "settingsMenu"
    x: Math.max(0, root.anchorRight - width)
    y: root.anchorTop
    width: Math.max(Style.space(340), Math.max(modes.implicitWidth, labels.implicitWidth) + Style.spacing.lg * 2)
    height: column.implicitHeight + Style.spacing.lg * 2
    color: Color.background
    borderSpec: root.popupBorderSpec
    radius: Style.cornerRadius

    // Swallow clicks on the menu itself.
    MouseArea { anchors.fill: parent }

    Column {
      id: column
      x: Style.spacing.lg
      y: Style.spacing.lg
      width: popup.width - Style.spacing.lg * 2
      spacing: Style.spacing.md

      PanelSectionHeader {
        height: Style.space(22)
        foreground: theme.textPrimary
        text: "BAR DISPLAY"
      }

      ButtonGroup {
        id: modes
        objectName: "displayModes"
        options: [
          { value: BarDisplay.TRACK_INFO, label: "Track Info" },
          { value: BarDisplay.SPECTRUM, label: "Spectrum" },
          { value: BarDisplay.PULSE_DOTS, label: "Pulse Dots" }
        ]
        value: root.mode
        foreground: theme.textPrimary
        accent: theme.accent
        fontFamily: theme.fontFamily
        fontSize: theme.fontBody
        onChanged: (value) => { if (root.service) root.service.setDisplayMode(value) }
      }

      Text {
        objectName: "modeDetail"
        width: column.width
        text: root.modeDetail
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: theme.textSecondary
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSmall
      }

      // What Track Info's text shows.
      PanelSectionHeader {
        visible: root.labelShown
        height: Style.space(22)
        foreground: theme.textPrimary
        text: "TRACK INFO SHOWS"
      }

      ButtonGroup {
        id: labels
        objectName: "trackLabels"
        visible: root.labelShown
        options: [
          { value: BarDisplay.LABEL_ARTIST_TITLE, label: "Artist — Title" },
          { value: BarDisplay.LABEL_TITLE, label: "Title" },
          { value: BarDisplay.LABEL_ARTIST, label: "Artist" }
        ]
        value: root.label
        foreground: theme.textPrimary
        accent: theme.accent
        fontFamily: theme.fontFamily
        fontSize: theme.fontBody
        onChanged: (value) => { if (root.service) root.service.setTrackLabel(value) }
      }

      Text {
        objectName: "labelExample"
        width: column.width
        visible: root.labelShown
        text: "In the bar: " + root.labelExample
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: theme.textSecondary
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSmall
      }

      Text {
        width: column.width
        visible: BarDisplay.isVisual(root.mode)
        text: "Only your music player’s own audio is read, and only while it plays. Nothing is recorded or saved."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: theme.textMuted
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSmall
      }

      Text {
        width: column.width
        text: "Right-click Melody in the bar to pause or resume."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: theme.textMuted
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSmall
      }
    }
  }
}
