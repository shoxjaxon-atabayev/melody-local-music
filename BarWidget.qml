import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import "components"
import "core"

// Vinyl's bar indicator, built on Omarchy's BarIconButton. Idle: a neutral
// note. Playing: a 16 px artwork thumbnail (the note when there is no local
// artwork). Paused: the same in the button's dimmed state. A left click
// toggles the mini-player popover on this monitor.
BarWidget {
  id: root
  moduleName: "community.shoxjaxon.vinyl"

  // Typed as QtObject so it reads null once the service is destroyed
  // (e.g. on plugin hot-reload, which unloads services before widgets).
  readonly property QtObject service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool hasTrack: !!service && service.hasTrack
  readonly property bool paused: hasTrack && !service.isPlaying
  readonly property string artUrl: hasTrack ? service.artUrl : ""
  // Set by the indicator once its thumbnail has decoded.
  property bool thumbnailReady: false

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
    syncCount()
  }

  Component.onDestruction: {
    if (counted && service) service.openPopovers -= 1
    if (popupOpen && bar) bar.releasePopout(root)
  }

  readonly property string tooltip: {
    if (!hasTrack) return "Vinyl — nothing playing"
    var title = service.title || "Unknown track"
    return service.artist ? title + " — " + service.artist : title
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    useActiveColor: false
    // Omarchy's own dimmed state marks paused playback.
    dimmed: root.paused
    tooltipText: root.tooltip
    iconComponent: indicator
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
    }
  }

  Component {
    id: indicator

    Item {
      Glyph {
        anchors.fill: parent
        name: "note"
        color: button.foreground
        visible: !root.thumbnailReady
      }

      ClippingRectangle {
        anchors.fill: parent
        radius: Style.spacing.labelGap
        color: "transparent"
        visible: root.thumbnailReady

        Image {
          id: thumbnail
          anchors.fill: parent
          source: root.artUrl
          asynchronous: true
          cache: false
          fillMode: Image.PreserveAspectCrop
          sourceSize: Qt.size(48, 48)
          smooth: true
          mipmap: true
        }
      }

      Binding {
        target: root
        property: "thumbnailReady"
        value: root.artUrl !== "" && thumbnail.status === Image.Ready
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
