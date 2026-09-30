import QtQuick
import qs.Commons

// Melody's design tokens, mapped onto Omarchy's own system values (the shell's
// Color and Style singletons), so Melody follows the user's theme, font,
// spacing scale, corner radius, and control styles. The only Melody-specific
// values are the approved layout dimensions, expressed in Omarchy's spacing
// scale. An ordinary object (not a singleton) owned by each bar widget; it
// reads no files of its own.
QtObject {
  // ---------------------------------------------------------------- layout
  function px(n) {
    return Style.space(n)
  }

  readonly property int cardWidth: Style.space(348)
  readonly property int cardPadding: Style.spacing.popupPadding
  readonly property int artworkSize: Style.space(116)
  // Omarchy's album-art tile radius (the media plugin's artwork).
  readonly property int artworkRadius: Style.spacing.labelGap
  // Approved screen-edge margin for the popover.
  readonly property int edgeGapRight: Style.space(8)

  // ---------------------------------------------------------------- type
  readonly property string fontFamily: Style.font.family
  readonly property int fontCaption: Style.font.caption
  readonly property int fontSmall: Style.font.bodySmall
  readonly property int fontBody: Style.font.body
  readonly property int fontLabel: Style.font.subtitle
  readonly property int fontTitle: Style.font.title

  // ---------------------------------------------------------------- color
  readonly property color surface: Color.popups.background
  readonly property color accent: Color.accent
  readonly property color textPrimary: Color.popups.text
  // Omarchy's secondary / tertiary / disabled text treatments.
  readonly property color textSecondary: Qt.darker(textPrimary, 1.4)
  readonly property color textMuted: Qt.darker(textPrimary, 1.6)
  readonly property color textDisabled: Qt.darker(textPrimary, 2.0)

  // ---------------------------------------------------------------- motion
  // Omarchy's control color transition and panel/slider timing.
  readonly property int durControl: 120
  readonly property int durPanel: 140
}
