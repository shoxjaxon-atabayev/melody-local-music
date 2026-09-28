import QtQuick
import QtQuick.Shapes

// Small vector icon set drawn on a 24×24 grid with QtQuick.Shapes, so the
// icons stay crisp at fractional scales and don't depend on an icon font.
Item {
  id: root

  // play | pause | previous | next | shuffle | repeatOne | close | note
  property string name: "play"
  property color color: "white"

  implicitWidth: 24
  implicitHeight: 24

  readonly property var fills: ({
    play: "M 8.3 6.6 L 8.3 17.4 Q 8.3 19.2 9.83 18.26 L 18.47 12.94 Q 20 12 18.47 11.06 L 9.83 5.74 Q 8.3 4.8 8.3 6.6 Z",
    pause: "M 7.8 5 L 9 5 Q 10.3 5 10.3 6.3 L 10.3 17.7 Q 10.3 19 9 19 L 7.8 19 Q 6.5 19 6.5 17.7 L 6.5 6.3 Q 6.5 5 7.8 5 Z "
      + "M 15 5 L 16.2 5 Q 17.5 5 17.5 6.3 L 17.5 17.7 Q 17.5 19 16.2 19 L 15 19 Q 13.7 19 13.7 17.7 L 13.7 6.3 Q 13.7 5 15 5 Z",
    next: "M 3.5 7.7 L 3.5 16.3 Q 3.5 17.5 4.5 16.84 L 10.8 12.66 Q 11.8 12 10.8 11.34 L 4.5 7.16 Q 3.5 6.5 3.5 7.7 Z "
      + "M 11.7 7.7 L 11.7 16.3 Q 11.7 17.5 12.7 16.84 L 19 12.66 Q 20 12 19 11.34 L 12.7 7.16 Q 11.7 6.5 11.7 7.7 Z",
    note: "M 4.8 17.3 A 2.8 2.3 0 1 0 10.4 17.3 A 2.8 2.3 0 1 0 4.8 17.3 Z "
      + "M 13.4 15.1 A 2.8 2.3 0 1 0 19 15.1 A 2.8 2.3 0 1 0 13.4 15.1 Z "
      + "M 9.4 6.6 L 19.8 4.3 L 19.8 6.9 L 9.4 9.2 Z"
  })

  readonly property var strokes: ({
    close: "M 7 7 L 17 17 M 17 7 L 7 17",
    note: "M 10.2 7.8 L 10.2 17.3 M 18.9 5.4 L 18.9 15.1",
    shuffle: "M 3.5 7.5 L 6.5 7.5 C 10.8 7.5 12.7 16.5 17 16.5 L 20 16.5 "
      + "M 3.5 16.5 L 6.5 16.5 C 10.8 16.5 12.7 7.5 17 7.5 L 20 7.5 "
      + "M 17.5 5 L 20 7.5 L 17.5 10 M 17.5 14 L 20 16.5 L 17.5 19",
    repeatOne: "M 4.5 12 L 4.5 9.5 Q 4.5 6.5 7.5 6.5 L 19 6.5 M 16.5 4 L 19 6.5 L 16.5 9 "
      + "M 19.5 12 L 19.5 14.5 Q 19.5 17.5 16.5 17.5 L 5 17.5 M 7.5 15 L 5 17.5 L 7.5 20 "
      + "M 10.7 10.4 L 12.4 9.3 L 12.4 14.7"
  })

  readonly property var strokeWidths: ({ close: 2, note: 1.6, shuffle: 1.7, repeatOne: 1.7 })

  // "previous" is "next" mirrored.
  readonly property string shapeName: name === "previous" ? "next" : name

  Shape {
    width: 24
    height: 24
    anchors.centerIn: parent
    scale: Math.min(root.width, root.height) / 24
    preferredRendererType: Shape.CurveRenderer
    transform: Scale {
      origin.x: 12
      origin.y: 12
      xScale: root.name === "previous" ? -1 : 1
    }

    ShapePath {
      strokeWidth: -1
      strokeColor: "transparent"
      fillColor: root.fills[root.shapeName] ? root.color : "transparent"
      fillRule: ShapePath.WindingFill
      PathSvg { path: root.fills[root.shapeName] || "M 0 0" }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokes[root.shapeName] ? root.color : "transparent"
      strokeWidth: root.strokeWidths[root.shapeName] || -1
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: root.strokes[root.shapeName] || "M 0 0" }
    }
  }
}
