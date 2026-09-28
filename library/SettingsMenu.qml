import QtQuick
import qs.Commons
import "../core/BarDisplay.js" as BarDisplay
import qs.Ui

// Settings, opened from the cog in the Library header and drawn like the
// "Add to playlist" menu (Omarchy's popup border and radius, on the opaque
// background of its in-panel ConfirmDialog). One setting: how the bar shows
// the current track. A choice applies at once and is saved with Vinyl's
// entry in shell.json. Fills its parent; a click outside closes it.
// Keyboard: Left/Right and Enter pick a mode, Escape closes.
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
    return "The artist and song title."
  }

  visible: opened

  onOpenedChanged: if (opened) modes.forceActiveFocus()

  // Returns true if the menu handled the key.
  function handleKey(event) {
    if (!opened) return false
    if (event.key === Qt.Key_Escape) closeRequested()
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
    width: Math.max(Style.space(340), modes.implicitWidth + Style.spacing.lg * 2)
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
        text: "Right-click Vinyl in the bar to pause or resume."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: theme.textMuted
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSmall
      }
    }
  }
}
