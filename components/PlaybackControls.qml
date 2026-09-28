import QtQuick

// Shuffle / previous / play-pause / next / repeat-one. Stateless: the owner
// supplies state and capabilities and handles the signals, so the same
// component can later be driven by a real player service.
Row {
  id: root

  required property var theme

  property bool playing: false
  property bool canPlay: true
  property bool canGoPrevious: true
  property bool canGoNext: true
  property bool shuffle: false
  property bool repeatOne: false
  property bool canShuffle: true
  property bool canRepeat: true

  signal shuffleClicked()
  signal previousClicked()
  signal playPauseClicked()
  signal nextClicked()
  signal repeatClicked()

  spacing: theme.px(16)

  ControlButton {
    theme: root.theme
    anchors.verticalCenter: parent.verticalCenter
    glyph: "shuffle"
    text: root.shuffle ? "Shuffle on" : "Shuffle off"
    toggle: true
    checked: root.shuffle
    diameter: theme.px(32)
    glyphSize: theme.px(17)
    enabled: root.canShuffle
    onClicked: root.shuffleClicked()
  }

  ControlButton {
    theme: root.theme
    anchors.verticalCenter: parent.verticalCenter
    glyph: "previous"
    text: "Previous track"
    enabled: root.canGoPrevious
    onClicked: root.previousClicked()
  }

  ControlButton {
    theme: root.theme
    anchors.verticalCenter: parent.verticalCenter
    primary: true
    glyph: root.playing ? "pause" : "play"
    text: root.playing ? "Pause" : "Play"
    enabled: root.canPlay
    onClicked: root.playPauseClicked()
  }

  ControlButton {
    theme: root.theme
    anchors.verticalCenter: parent.verticalCenter
    glyph: "next"
    text: "Next track"
    enabled: root.canGoNext
    onClicked: root.nextClicked()
  }

  ControlButton {
    theme: root.theme
    anchors.verticalCenter: parent.verticalCenter
    glyph: "repeatOne"
    text: root.repeatOne ? "Repeat this track: on" : "Repeat this track: off"
    toggle: true
    checked: root.repeatOne
    diameter: theme.px(32)
    glyphSize: theme.px(18)
    enabled: root.canRepeat
    onClicked: root.repeatClicked()
  }
}
