import QtQuick
import QtQuick.Templates as T
import qs.Commons
import qs.Ui

// Icon button with an Omarchy system glyph (Icon): the same Omarchy Button
// conventions as ControlButton (shape, state fills, control borders, 120 ms
// color transition, disabled treatment, `primary`, `quiet`, and `toggle`).
T.AbstractButton {
  id: root

  required property var theme

  property string iconName: "play"
  property bool primary: false
  property bool quiet: false
  property bool toggle: false
  property real diameter: primary ? Style.space(44) : Style.space(36)
  property real iconSize: primary ? Style.space(24) : Style.space(20)

  readonly property bool hot: hovered && enabled
  readonly property color fg: theme.textPrimary
  readonly property color iconColor: {
    if (!root.enabled) return theme.textDisabled
    if (root.toggle && root.checked) return theme.accent
    if (root.quiet && !root.hot) return theme.textSecondary
    return root.fg
  }

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
    Icon {
      id: glyph
      anchors.centerIn: parent
      name: root.iconName
      size: root.iconSize
      color: root.iconColor
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: glyph.bottom
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
