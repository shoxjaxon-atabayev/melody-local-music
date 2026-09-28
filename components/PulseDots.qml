import QtQuick

// The bar's Pulse Dots: five dots sized by the real signal level (from the
// player stream's peak monitor, via AudioLevels). The middle dot follows the
// current level; the outer pairs show it about 70 and 140 ms earlier, so a
// peak ripples outward. With no signal every dot rests at its minimum size;
// nothing moves without audio.
Item {
  id: root

  property real level: 0
  property real echo1: 0
  property real echo2: 0
  property color color: "white"
  property real maxSize: 7
  property real minSize: 3
  property real gap: 2

  readonly property var values: [echo2, echo1, level, echo1, echo2]

  implicitWidth: values.length * maxSize + (values.length - 1) * gap
  implicitHeight: maxSize

  Row {
    anchors.centerIn: parent
    spacing: root.gap

    Repeater {
      model: root.values.length

      Item {
        required property int index
        readonly property real value: Math.max(0, Math.min(1, Number(root.values[index]) || 0))

        width: root.maxSize
        height: root.maxSize

        Rectangle {
          anchors.centerIn: parent
          width: root.minSize + (root.maxSize - root.minSize) * parent.value
          height: width
          radius: width / 2
          color: root.color
          opacity: 0.55 + 0.45 * parent.value
        }
      }
    }
  }
}
