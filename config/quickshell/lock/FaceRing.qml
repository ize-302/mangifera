import QtQuick
import QtQuick.Shapes
import qs

// Ring around the avatar for face unlock: a sweep while howdy looks, a full
// ring once it knows you, and a faint one on hover to say a click looks again.
Item {
    id: ring

    property real radius: 0
    property bool scanning: false
    // Faint while you type, so it doesn't pull your eye off the field
    property bool dimmed: false
    property bool hinted: false
    property bool matched: false

    readonly property real stroke: Theme.faceRingWidth
    readonly property color clear: Qt.rgba(Theme.selectedColor.r, Theme.selectedColor.g, Theme.selectedColor.b, 0)

    Shape {
        id: sweep

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: ring.scanning && !ring.matched ? (ring.dimmed ? Theme.faceRingDimOpacity : 1) : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animationDuration
            }
        }

        // The band between two rounded squares, lit by a turning gradient
        ShapePath {
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            fillGradient: ConicalGradient {
                id: gradient

                centerX: ring.width / 2
                centerY: ring.height / 2

                GradientStop {
                    position: 0
                    color: Theme.selectedColor
                }
                GradientStop {
                    position: Theme.faceSweepLength
                    color: ring.clear
                }
                GradientStop {
                    position: 1
                    color: ring.clear
                }
            }

            PathRectangle {
                width: ring.width
                height: ring.height
                radius: ring.radius
            }
            PathRectangle {
                x: ring.stroke
                y: ring.stroke
                width: ring.width - 2 * ring.stroke
                height: ring.height - 2 * ring.stroke
                radius: Math.max(0, ring.radius - ring.stroke)
            }
        }

        NumberAnimation {
            target: gradient
            property: "angle"
            from: 360
            to: 0
            duration: Theme.faceSweepDuration
            loops: Animation.Infinite
            running: sweep.visible
        }
    }

    // Full ring: bright on a match, faint as the hover hint
    Rectangle {
        anchors.fill: parent
        radius: ring.radius
        color: "transparent"
        border.width: ring.stroke
        border.color: Theme.selectedColor
        opacity: ring.matched ? 1 : ring.hinted && !ring.scanning ? Theme.faceRingHintOpacity : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.animationDuration
            }
        }
    }
}
