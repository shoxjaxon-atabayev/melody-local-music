import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "components"

// Vinyl's mini-player popover: a layer-shell surface the size of the card,
// placed next to the bar under the Vinyl icon. Like Omarchy's panels it draws
// no shadow of its own; blur, if any, comes from the theme's panel rules.
//
// Opening and closing follow Omarchy's default panel behavior (KeyboardPanel):
// no compositor animation, a 140 ms fade (none during a panel handoff), and a
// brief keyboard-focus prime. It closes on a click outside the card
// (transparent dismiss surfaces), on Escape, or from the card's close button.
PanelWindow {
  id: root

  required property Item anchorItem
  required property var service
  required property var theme
  property var bar: null
  property bool open: false
  // Set by the widget during a bar panel handoff: open/close without the fade.
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false
  property bool focusPrimed: false

  signal closeRequested()

  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPosition: bar && bar.position ? String(bar.position) : "top"
  readonly property bool horizontalBar: barPosition === "top" || barPosition === "bottom"
  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0
  readonly property real barThickness: anchorWindow
    ? (horizontalBar ? anchorWindow.height : anchorWindow.width) : 0

  // Centre of the Vinyl icon along the bar. The Omarchy bar spans its whole
  // screen edge, so bar-window coordinates equal screen coordinates on that
  // axis. Sampled by the widget just before opening.
  property point anchorPoint: Qt.point(0, 0)

  function sampleAnchor() {
    if (!anchorItem) return
    anchorPoint = anchorItem.mapToItem(null, anchorItem.width / 2, anchorItem.height / 2)
  }

  function clamp(value, lo, hi) {
    return Math.max(lo, Math.min(hi, value))
  }

  // Card placement in screen coordinates. The gap to the bar is the shell's
  // own `Style.gapsOut` (half of Hyprland's gaps_out), the same gap every
  // Omarchy popup uses; the screen-edge margin is the prototype's.
  readonly property int gap: Style.gapsOut
  readonly property int edge: theme.edgeGapRight

  readonly property real cardX: {
    if (barPosition === "left") return Math.round(barThickness + gap)
    if (barPosition === "right") return Math.round(screenW - barThickness - gap - card.width)
    return Math.round(clamp(anchorPoint.x - card.width / 2, edge, screenW - card.width - edge))
  }

  readonly property real cardY: {
    if (barPosition === "top") return Math.round(barThickness + gap)
    if (barPosition === "bottom") return Math.round(screenH - barThickness - gap - card.height)
    return Math.round(clamp(anchorPoint.y - card.height / 2, edge, screenH - card.height - edge))
  }


  screen: anchorWindow ? anchorWindow.screen : null
  // Stays mapped for the close fade, like Omarchy's KeyboardPanel.
  visible: (open || content.opacity > 0 || popoutSwitching) && anchorWindow !== null

  anchors {
    top: true
    left: true
  }
  margins {
    top: cardY
    left: cardX
  }
  exclusionMode: ExclusionMode.Ignore
  implicitWidth: Math.max(1, card.width)
  implicitHeight: Math.max(1, card.height)
  color: "transparent"

  // The namespace of Omarchy's own panels (KeyboardPanel): Omarchy's default
  // Hyprland rules give it no compositor open/close animation, so Vinyl opens
  // and closes exactly like the other bar panels. Overlay keeps the card
  // above its own dismiss surfaces (Top).
  WlrLayershell.namespace: "omarchy-keyboard-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  // Same focus handling as KeyboardPanel: a brief Exclusive prime so keys
  // (Escape) reach the card even when reopened mid-fade, then OnDemand.
  WlrLayershell.keyboardFocus: open
    ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
    : WlrKeyboardFocus.None

  function beginFocusPrime() {
    if (open && backingWindowVisible) focusPrimeTimer.restart()
  }

  onBackingWindowVisibleChanged: beginFocusPrime()
  onOpenChanged: {
    focusPrimeTimer.stop()
    focusPrimed = false
    if (open) beginFocusPrime()
  }

  Timer {
    id: focusPrimeTimer
    interval: 75
    onTriggered: if (root.open) root.focusPrimed = true
  }


  // Outside-click dismissal. Hyprland's focus grab is not used: the
  // compositor drops a grab whenever it re-evaluates focus with the pointer
  // over another surface, which closed the popover with no user input.
  // Instead, while open, every monitor gets a transparent input-only surface
  // under the card that closes it on any click. The bar strip is cut out, so
  // bar widgets (including this toggle) still receive their clicks and the
  // bar's popout coordinator closes this popover when another one opens.
  Variants {
    model: root.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: dismiss

        required property var modelData

        screen: modelData
        visible: root.visible
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        WlrLayershell.namespace: "vinyl-popover-dismiss"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        mask: Region {
          width: dismiss.width
          height: dismiss.height

          Region {
            intersection: Intersection.Subtract
            x: root.barPosition === "right" ? dismiss.width - root.barThickness : 0
            y: root.barPosition === "bottom" ? dismiss.height - root.barThickness : 0
            width: root.horizontalBar ? dismiss.width : root.barThickness
            height: root.horizontalBar ? root.barThickness : dismiss.height
          }
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: root.closeRequested()
        }
      }
    }
  }

  // Omarchy's default panel transition: a 140 ms fade on normal open/close,
  // none during a panel handoff. No other open/close animation.
  FocusScope {
    id: content
    anchors.fill: parent
    focus: true
    opacity: root.open || root.popoutSwitching ? 1 : 0
    Keys.onEscapePressed: root.closeRequested()

    Behavior on opacity {
      enabled: !root.popoutSwitching && !root.popoutSwitchClosing
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    MiniPlayer {
      id: card
      theme: root.theme
      service: root.service
      onCloseRequested: root.closeRequested()
      // The library opens centered; the popover closes first.
      onLibraryRequested: {
        root.closeRequested()
        if (root.service) root.service.openLibrary()
      }
    }
  }
}
