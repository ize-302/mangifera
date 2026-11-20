import QtQuick
import QtQuick.Shapes
import qs

// Face in scan brackets that stands in for the avatar during face unlock. Its
// eyes blink and follow the pointer, glance around while howdy looks, and it
// smiles on a match and frowns on a miss.
Item {
    id: glyph

    property bool scanning: false
    property bool matched: false
    // Pointer in this item's coordinates, while it's over the screen
    property point pointer: Qt.point(width / 2, height / 2)
    property bool tracking: false
    // Brackets grow a little, to say a click looks again
    property bool hovered: false

    // Frown for a moment, then back to neutral
    function fail() {
        failed = true;
        failTimer.restart();
    }

    property bool failed: false

    readonly property real size: width
    readonly property real stroke: Theme.faceGlyphStroke

    // Where the eyes look, -1 to 1 each way: the scan's glances, else the
    // pointer
    property real glanceX: 0
    property real glanceY: 0
    readonly property real pointerDx: pointer.x - width / 2
    readonly property real pointerDy: pointer.y - height / 2
    readonly property real pointerDistance: Math.hypot(pointerDx, pointerDy)
    // Full reach once the pointer is a few glyphs away
    readonly property real pointerPull: Math.min(1, pointerDistance / (width * 4))
    readonly property real lookX: matched ? 0 : scanning ? glanceX : tracking && pointerDistance > 0 ? pointerDx / pointerDistance * pointerPull : 0
    readonly property real lookY: matched ? 0 : scanning ? glanceY : tracking && pointerDistance > 0 ? pointerDy / pointerDistance * pointerPull : 0

    // The look, eased, so both eyes move as one
    property real eyeX: lookX
    property real eyeY: lookY

    Behavior on eyeX {
        SmoothedAnimation {
            velocity: Theme.faceEyeVelocity
        }
    }
    Behavior on eyeY {
        SmoothedAnimation {
            velocity: Theme.faceEyeVelocity
        }
    }

    // 1 smile, 0 flat, below 0 frown
    property real mood: matched ? 1 : failed ? -0.6 : 0

    Behavior on mood {
        NumberAnimation {
            duration: Theme.faceMoodDuration
            easing.type: Easing.OutBack
        }
    }

    // 1 open, near 0 shut
    property real blink: 1

    Timer {
        id: failTimer
        interval: Theme.faceFrownHold
        onTriggered: glyph.failed = false
    }

    // Every few seconds, not on a beat
    Timer {
        interval: Theme.faceBlinkInterval
        running: glyph.visible && !glyph.matched
        repeat: true
        onTriggered: {
            interval = Theme.faceBlinkInterval * (0.6 + Math.random() * 0.8);
            blinkAnimation.restart();
        }
    }

    SequentialAnimation {
        id: blinkAnimation

        NumberAnimation {
            target: glyph
            property: "blink"
            to: 0.1
            duration: Theme.faceBlinkDuration / 2
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: glyph
            property: "blink"
            to: 1
            duration: Theme.faceBlinkDuration / 2
            easing.type: Easing.OutQuad
        }
    }

    // Looking around for you: left, right, up, back
    SequentialAnimation {
        running: glyph.scanning && !glyph.matched
        loops: Animation.Infinite

        onStopped: {
            glyph.glanceX = 0;
            glyph.glanceY = 0;
        }

        NumberAnimation {
            target: glyph
            property: "glanceX"
            to: -1
            duration: Theme.faceGlanceDuration
            easing.type: Easing.InOutSine
        }
        PauseAnimation {
            duration: Theme.faceGlancePause
        }
        NumberAnimation {
            target: glyph
            property: "glanceX"
            to: 1
            duration: Theme.faceGlanceDuration * 1.5
            easing.type: Easing.InOutSine
        }
        PauseAnimation {
            duration: Theme.faceGlancePause
        }
        ParallelAnimation {
            NumberAnimation {
                target: glyph
                property: "glanceX"
                to: 0
                duration: Theme.faceGlanceDuration
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: glyph
                property: "glanceY"
                to: -0.8
                duration: Theme.faceGlanceDuration
                easing.type: Easing.InOutSine
            }
        }
        PauseAnimation {
            duration: Theme.faceGlancePause
        }
        NumberAnimation {
            target: glyph
            property: "glanceY"
            to: 0
            duration: Theme.faceGlanceDuration
            easing.type: Easing.InOutSine
        }
        PauseAnimation {
            duration: Theme.faceGlancePause * 2
        }
    }

    Item {
        id: face

        width: glyph.width
        height: glyph.height

        // Scan brackets: breathe while looking, close in on a match
        Shape {
            id: brackets

            readonly property real inset: glyph.stroke / 2
            readonly property real arm: glyph.size * 0.24
            readonly property real corner: glyph.size * 0.12
            readonly property real far: glyph.size - inset

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            scale: glyph.matched ? Theme.faceBracketsMatchScale : glyph.hovered && !glyph.scanning ? Theme.faceBracketsHoverScale : 1

            Behavior on scale {
                NumberAnimation {
                    duration: Theme.faceMoodDuration
                    easing.type: Easing.OutBack
                }
            }

            SequentialAnimation on scale {
                running: glyph.scanning && !glyph.matched
                loops: Animation.Infinite

                NumberAnimation {
                    to: Theme.faceBracketsPulseScale
                    duration: Theme.facePulseDuration / 2
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: 1
                    duration: Theme.facePulseDuration / 2
                    easing.type: Easing.InOutSine
                }
            }

            ShapePath {
                strokeColor: Theme.faceColor
                strokeWidth: glyph.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                // Top left
                PathMove {
                    x: brackets.inset
                    y: brackets.inset + brackets.arm
                }
                PathLine {
                    x: brackets.inset
                    y: brackets.inset + brackets.corner
                }
                PathArc {
                    x: brackets.inset + brackets.corner
                    y: brackets.inset
                    radiusX: brackets.corner
                    radiusY: brackets.corner
                }
                PathLine {
                    x: brackets.inset + brackets.arm
                    y: brackets.inset
                }

                // Top right
                PathMove {
                    x: brackets.far - brackets.arm
                    y: brackets.inset
                }
                PathLine {
                    x: brackets.far - brackets.corner
                    y: brackets.inset
                }
                PathArc {
                    x: brackets.far
                    y: brackets.inset + brackets.corner
                    radiusX: brackets.corner
                    radiusY: brackets.corner
                }
                PathLine {
                    x: brackets.far
                    y: brackets.inset + brackets.arm
                }

                // Bottom right
                PathMove {
                    x: brackets.far
                    y: brackets.far - brackets.arm
                }
                PathLine {
                    x: brackets.far
                    y: brackets.far - brackets.corner
                }
                PathArc {
                    x: brackets.far - brackets.corner
                    y: brackets.far
                    radiusX: brackets.corner
                    radiusY: brackets.corner
                }
                PathLine {
                    x: brackets.far - brackets.arm
                    y: brackets.far
                }

                // Bottom left
                PathMove {
                    x: brackets.inset + brackets.arm
                    y: brackets.far
                }
                PathLine {
                    x: brackets.inset + brackets.corner
                    y: brackets.far
                }
                PathArc {
                    x: brackets.inset
                    y: brackets.far - brackets.corner
                    radiusX: brackets.corner
                    radiusY: brackets.corner
                }
                PathLine {
                    x: brackets.inset
                    y: brackets.far - brackets.arm
                }
            }
        }

        Repeater {
            model: [-1, 1]

            Rectangle {
                required property int modelData

                readonly property real reach: glyph.size * Theme.faceGlanceReach
                // Squint when smiling
                readonly property real open: glyph.blink * (1 - 0.45 * Math.max(0, glyph.mood))

                width: glyph.size * 0.1
                height: Math.max(glyph.stroke / 2, width * 1.5 * open)
                radius: width / 2
                color: Theme.faceColor
                x: glyph.size / 2 + modelData * glyph.size * 0.15 - width / 2 + glyph.eyeX * reach
                y: glyph.size * 0.42 - height / 2 + glyph.eyeY * reach
            }
        }

        // Mouth: flat, a smile on a match, a small frown on a miss
        Shape {
            id: mouth

            readonly property real halfWidth: glyph.size * (0.13 + 0.04 * Math.max(0, glyph.mood))
            readonly property real middle: glyph.size * 0.66

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Theme.faceColor
                strokeWidth: glyph.stroke
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                startX: glyph.size / 2 - mouth.halfWidth
                startY: mouth.middle

                PathQuad {
                    x: glyph.size / 2 + mouth.halfWidth
                    y: mouth.middle
                    controlX: glyph.size / 2
                    controlY: mouth.middle + glyph.mood * glyph.size * 0.2
                }
            }
        }
    }
}
