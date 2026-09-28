import QtQuick
import qs.Commons
import qs.Ui

// Progress with elapsed and total time, styled like Omarchy's PanelSlider:
// the selected-state track, a foreground fill that moves with the slider's
// 140 ms timing, and (when seekable) its knob. Click or drag requests a seek;
// ←/→ step by five seconds while focused. When not seekable it only
// displays progress.
Item {
  id: root

  required property var theme

  property real position: 0
  property real length: 0
  // False when there is no track at all; the elapsed label then shows a placeholder.
  property bool hasPosition: true
  property bool seekable: true

  signal seekRequested(real seconds)

  readonly property bool active: enabled && length > 0
  readonly property bool interactive: active && seekable
  readonly property real ratio: length > 0 ? Math.max(0, Math.min(1, position / length)) : 0
  property real dragRatio: -1
  readonly property real shownRatio: dragRatio >= 0 ? dragRatio : ratio

  // PanelSlider's metrics.
  readonly property real trackHeight: Math.max(4, Math.round(Style.spacing.controlHeight * 0.11))
  readonly property real knobSize: Math.max(14, Math.round(Style.spacing.controlHeight * 0.38))

  function formatTime(seconds) {
    var n = Number(seconds)
    if (!isFinite(n) || n < 0) return "–:––"
    n = Math.floor(n)
    var h = Math.floor(n / 3600)
    var m = Math.floor((n % 3600) / 60)
    var s = n % 60
    var ss = (s < 10 ? "0" : "") + s
    if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss
    return m + ":" + ss
  }

  implicitHeight: hitArea.height + times.anchors.topMargin + times.height
  activeFocusOnTab: interactive

  Keys.onLeftPressed: if (root.interactive) root.seekRequested(root.position - 5)
  Keys.onRightPressed: if (root.interactive) root.seekRequested(root.position + 5)

  Item {
    id: hitArea
    width: parent.width
    height: Style.space(14)

    BorderSurface {
      anchors.centerIn: track
      width: track.width + Style.space(8)
      height: track.height + Style.space(8)
      radius: height / 2
      color: "transparent"
      borderSpec: Border.controlSpec("focus", theme.textPrimary, theme.accent)
      visible: root.activeFocus
    }

    Rectangle {
      id: track
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: root.trackHeight
      radius: height / 2
      color: root.active
        ? Style.selectedFillFor(theme.textPrimary, theme.accent)
        : Style.normalFillFor(theme.textPrimary, theme.accent)
    }

    Rectangle {
      anchors.left: track.left
      anchors.verticalCenter: track.verticalCenter
      height: track.height
      width: Math.max(height, track.width * root.shownRatio)
      radius: track.radius
      color: theme.textPrimary
      visible: root.active && root.shownRatio > 0

      Behavior on width {
        enabled: root.dragRatio < 0
        NumberAnimation { duration: theme.durPanel; easing.type: Easing.OutCubic }
      }
    }

    BorderSurface {
      width: root.knobSize
      height: width
      radius: width / 2
      x: Math.max(0, Math.min(track.width - width, track.width * root.shownRatio - width / 2))
      anchors.verticalCenter: track.verticalCenter
      color: theme.textPrimary
      borderSpec: Border.flat(Color.background, Math.max(1, Style.space(2)))
      visible: root.interactive
    }

    HoverHandler {
      enabled: root.interactive
      cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
      id: dragArea
      anchors.fill: parent
      enabled: root.interactive
      preventStealing: true

      function ratioAt(x) {
        return Math.max(0, Math.min(1, x / width))
      }

      onPressed: (mouse) => { root.dragRatio = ratioAt(mouse.x) }
      onPositionChanged: (mouse) => { if (pressed) root.dragRatio = ratioAt(mouse.x) }
      onReleased: {
        if (root.dragRatio >= 0) root.seekRequested(root.dragRatio * root.length)
        root.dragRatio = -1
      }
      onCanceled: root.dragRatio = -1
    }
  }

  Item {
    id: times
    anchors.top: hitArea.bottom
    anchors.topMargin: Style.spacing.xs
    width: parent.width
    height: elapsed.implicitHeight

    Text {
      id: elapsed
      anchors.left: parent.left
      text: !root.hasPosition ? "–:––"
        : root.formatTime(root.dragRatio >= 0 ? root.dragRatio * root.length : root.position)
      textFormat: Text.PlainText
      color: theme.textMuted
      font.family: theme.fontFamily
      font.pixelSize: theme.fontSmall
    }

    Text {
      anchors.right: parent.right
      text: root.length > 0 ? root.formatTime(root.length) : "–:––"
      textFormat: Text.PlainText
      color: theme.textMuted
      font.family: theme.fontFamily
      font.pixelSize: theme.fontSmall
    }
  }
}
