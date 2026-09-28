import QtQuick

// The bar's Spectrum: one rounded bar per frequency band, low to high, each
// as tall as its real band level (from cava, via AudioLevels.bands). With no
// data (paused, silent, or no stream) every bar rests at its minimum
// height; nothing moves without audio.
Item {
  id: root

  property var bands: []
  property color color: "white"
  property real barWidth: 2
  property real gap: 1.5
  property real minHeight: 2

  implicitWidth: bands.length * barWidth + Math.max(0, bands.length - 1) * gap
  implicitHeight: 16

  Row {
    anchors.centerIn: parent
    height: parent.height
    spacing: root.gap

    Repeater {
      model: root.bands.length

      Rectangle {
        required property int index
        readonly property real value: Number(root.bands[index]) || 0

        anchors.verticalCenter: parent.verticalCenter
        width: root.barWidth
        height: Math.max(root.minHeight, Math.min(1, value) * root.height)
        radius: width / 2
        color: root.color
      }
    }
  }
}
