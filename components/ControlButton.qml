import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// Icon button following Omarchy's Button conventions: Style.cornerRadius
// shape, the shell's state fills and control borders, a 120 ms color
// transition, and Omarchy's disabled treatment. `primary` (play/pause) uses
// the selected/active state. `toggle` buttons show `checked` with an accent
// glyph and a small accent dot; the owner flips the state in `onClicked`.
T.AbstractButton {
  id: root

  required property var theme

  property string glyph: "play"
  property bool primary: false
  property bool quiet: false
  property bool toggle: false
  property real diameter: primary ? Style.space(44) : Style.space(36)
  property real glyphSize: primary ? Style.space(20) : Style.space(18)

  readonly property bool hot: hovered && enabled
  readonly property color fg: theme.textPrimary

  implicitWidth: diameter
  implicitHeight: diameter
  padding: 0
  hoverEnabled: true
  focusPolicy: Qt.TabFocus
  Accessible.name: text
  Accessible.checkable: toggle
  Accessible.checked: toggle && checked

  Keys.onReturnPressed: root.clicked()
  Keys.onEnterPressed: root.clicked()

  background: BorderSurface {
    radius: Math.min(Style.cornerRadius, height / 2)
    color: {
      if (!root.enabled) return root.primary ? Style.normalFillFor(root.fg, theme.accent) : "transparent"
      if (root.down) return Style.pressedFillFor(root.fg, theme.accent)
      if (root.visualFocus) return Style.focusFillFor(root.fg, theme.accent)
      if (root.hot) return Style.hoverFillFor(root.fg, theme.accent)
      if (root.primary) return Style.selectedFillFor(root.fg, theme.accent)
      return "transparent"
    }
    borderSpec: {
      if (root.visualFocus) return Border.controlSpec("focus", root.fg, theme.accent)
      if (root.hot) return Border.controlSpec("hover-cursor", root.fg, theme.accent)
      if (root.primary && root.enabled && Border.controlHasWidth("selected"))
        return Border.controlSpec("selected", root.fg, theme.accent)
      return Border.none()
    }

    Behavior on color {
      ColorAnimation { duration: theme.durControl }
    }
  }

  contentItem: Item {
    Glyph {
      id: icon
      anchors.centerIn: parent
      width: root.glyphSize
      height: width
      name: root.glyph
      color: {
        if (!root.enabled) return theme.textDisabled
        if (root.toggle && root.checked) return theme.accent
        if (root.quiet && !root.hot) return theme.textSecondary
        return root.fg
      }
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: icon.bottom
      anchors.topMargin: Style.spacing.xxs
      width: Style.spacing.sm
      height: width
      radius: width / 2
      color: theme.accent
      visible: root.toggle && root.checked && root.enabled
    }
  }

  HoverHandler {
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
  }
}
