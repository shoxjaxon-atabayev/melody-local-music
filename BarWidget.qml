import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components"
import "core"
import "core/BarDisplay.js" as BarDisplay
import "core/Paths.js" as Paths

// Vinyl's bar indicator, built on Omarchy's WidgetButton (the base of its bar
// buttons: hover tooltip, click routing, the dimmed state). It shows:
//   - a track: the chosen display mode. Track Info ("Artist — Title", the
//     title cut to 12 characters), Spectrum, or Pulse Dots (both drawn from
//     the player's real audio). Dimmed while paused;
//   - no track and no usable music folder: a note and "Set up music library";
//   - no track otherwise: a neutral note.
// A vertical bar has no room for text or visualizations, so it always shows
// the note. A left click toggles the mini-player popover on this monitor; a
// right click pauses or resumes the player.
BarWidget {
  id: root
  moduleName: "community.shoxjaxon.vinyl"

  // Typed as QtObject so it reads null once the service is destroyed
  // (e.g. on plugin hot-reload, which unloads services before widgets).
  readonly property QtObject service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool hasTrack: !!service && service.hasTrack
  readonly property bool paused: hasTrack && !service.isPlaying
  readonly property string mode: service ? service.displayMode : BarDisplay.TRACK_INFO
  readonly property bool needsSetup: !hasTrack && !!service && service.needsLibrarySetup

  // "setup", "note", "text", "spectrum", or "dots".
  readonly property string face: {
    if (vertical) return "note"
    if (!hasTrack) return needsSetup ? "setup" : "note"
    if (mode === BarDisplay.SPECTRUM) return "spectrum"
    if (mode === BarDisplay.PULSE_DOTS) return "dots"
    return "text"
  }

  readonly property string trackText: hasTrack
    ? BarDisplay.trackLabel(service.artist,
        service.title || Paths.trackTitle(Paths.baseName(service.playingPath)) || "Unknown track")
    : ""
  readonly property string label: face === "text" ? trackText : face === "setup" ? "Set up music library" : ""
  // A layout guard only: real artist names fit; the tooltip has everything.
  readonly property real maxLabelWidth: Style.space(560)

  // Design tokens for this monitor's card. An ordinary object owned by the
  // widget, so it is created and destroyed together with the card.
  readonly property Theme theme: Theme {}

  // Popout contract used by the bar's coordinator and shell summon/hide.
  property bool popupOpen: false
  readonly property bool opened: popupOpen

  // Panel handoff, as in Omarchy's Panel/KeyboardPanel: opening in place of
  // another bar popup, or closing because one opened, skips the fade.
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false

  function open() {
    if (!popoverLoader.item) return
    popoverLoader.item.sampleAnchor()
    popoutSwitching = !!(bar && bar.activePopout && bar.activePopout !== root)
    popupOpen = true
    if (popoutSwitching) popoutSwitchTimer.restart()
  }

  function close() {
    popupOpen = false
  }

  // Called by the bar's coordinator (preferred over close()).
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  Timer {
    id: popoutSwitchTimer
    interval: 150
    onTriggered: root.popoutSwitching = false
  }

  function toggle() {
    if (popupOpen) close()
    else open()
  }

  // Open popovers are counted on the shared service so position polling
  // runs only while at least one card is visible.
  property bool counted: false

  function syncCount() {
    var want = popupOpen && !!service
    if (want === counted) return
    if (service) service.openPopovers += want ? 1 : -1
    counted = want
  }

  // Likewise, widgets drawing a visualization are counted, so audio is
  // sampled only while one is on screen.
  readonly property bool drawsAudio: face === "spectrum" || face === "dots"
  property bool audioCounted: false

  function syncAudioCount() {
    var want = drawsAudio && !!service
    if (want === audioCounted) return
    if (service) service.audioViewers += want ? 1 : -1
    audioCounted = want
  }

  onDrawsAudioChanged: syncAudioCount()

  onPopupOpenChanged: {
    if (bar) {
      if (popupOpen) bar.requestPopout(root)
      else bar.releasePopout(root)
    }
    syncCount()
  }

  onServiceChanged: {
    if (!service) popupOpen = false
    counted = false
    audioCounted = false
    syncCount()
    syncAudioCount()
  }

  Component.onDestruction: {
    if (counted && service) service.openPopovers -= 1
    if (audioCounted && service) service.audioViewers -= 1
    if (popupOpen && bar) bar.releasePopout(root)
  }

  readonly property string tooltip: {
    if (!service) return "Vinyl"
    if (!hasTrack) {
      if (!service.needsLibrarySetup) return "Vinyl — nothing playing"
      if (service.libraryRoot === "") return "Vinyl — choose a music folder in the library"
      if (service.libraryStatus === "empty") return "Vinyl — your music folder has no music to play"
      return "Vinyl — your music folder can’t be opened"
    }
    var title = service.title || "Unknown track"
    var text = service.artist ? title + " — " + service.artist : title
    var status = service.audio.status
    if (face === "spectrum" && status === "noCava") text += "\nSpectrum needs cava: omarchy pkg add cava"
    else if (face === "spectrum" && status === "failed") text += "\nSpectrum stopped: cava couldn’t read the player"
    else if (drawsAudio && status === "noStream") text += "\nNo audio data from " + (service.playerName || "the player")
    return text
  }

  // Dimmed visualizations mean "no data" (as opposed to paused, which dims
  // the whole button).
  readonly property bool audioLive: !!service && service.audio.status === "live"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    objectName: "barButton"
    anchors.fill: parent
    bar: root.bar
    useActiveColor: false
    labelVisible: false
    hasVisualContent: true
    // Omarchy's own dimmed state marks paused playback.
    dimmed: root.paused
    tooltipText: root.tooltip
    fixedWidth: root.vertical ? -1
      : root.face === "note" ? Style.bar.iconSlot
      : Math.ceil(content.implicitWidth) + Style.space(8) * 2
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
      else if (b === Qt.RightButton && root.service) root.service.togglePlaying()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(6)

      Glyph {
        objectName: "barNote"
        anchors.verticalCenter: parent.verticalCenter
        visible: root.face === "note" || root.face === "setup"
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
        name: "note"
        color: button.foreground
      }

      Text {
        objectName: "barLabel"
        anchors.verticalCenter: parent.verticalCenter
        visible: root.label !== ""
        width: Math.min(implicitWidth, root.maxLabelWidth)
        text: root.label
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        opacity: 0.85
      }

      SpectrumBars {
        objectName: "barSpectrum"
        anchors.verticalCenter: parent.verticalCenter
        visible: root.face === "spectrum"
        height: Style.bar.iconCanvas
        bands: root.service ? root.service.audio.bands : []
        color: root.theme.accent
        barWidth: Math.max(2, Style.spaceReal(2))
        gap: Math.max(1, Style.spaceReal(1.5))
        opacity: root.audioLive || root.paused ? 1 : 0.5
      }

      PulseDots {
        objectName: "barDots"
        anchors.verticalCenter: parent.verticalCenter
        visible: root.face === "dots"
        level: root.service ? root.service.audio.level : 0
        echo1: root.service ? root.service.audio.echo1 : 0
        echo2: root.service ? root.service.audio.echo2 : 0
        color: root.theme.accent
        maxSize: Math.max(6, Style.spaceReal(7))
        minSize: Math.max(3, Style.spaceReal(3))
        gap: Math.max(2, Style.spaceReal(2))
        opacity: root.audioLive || root.paused ? 1 : 0.5
      }
    }
  }

  // Created once the service exists, so the card never binds to a null theme.
  LazyLoader {
    id: popoverLoader
    active: root.service !== null

    VinylPopover {
      anchorItem: button
      bar: root.bar
      service: root.service
      theme: root.theme
      open: root.popupOpen
      popoutSwitching: root.popoutSwitching
      popoutSwitchClosing: root.popoutSwitchClosing
      onCloseRequested: root.close()
    }
  }
}
