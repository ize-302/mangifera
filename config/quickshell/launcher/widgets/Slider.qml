import QtQuick
import qs

// Thin slider, filled up to `value` (0 to 1; more shows as full). Emits `moved`
// on drag, click or scroll; the owner sets `value`.
Item {
    id: slider

    property real value: 0
    property color color: Theme.textColor
    // Off for a read-only gauge
    property bool interactive: true
    // The knob grows
    property bool active: false

    signal moved(real value)

    implicitHeight: Theme.rowHeight

    function moveTo(x) {
        slider.moved(Math.round(Math.max(0, Math.min(x / width, 1)) * 100) / 100);
    }

    Rectangle {
        id: track

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Theme.sliderHeight
        radius: height / 2
        color: Theme.sliderTrackColor

        Rectangle {
            width: Math.max(track.height, track.width * Math.max(0, Math.min(slider.value, 1)))
            height: parent.height
            radius: parent.radius
            color: slider.color
            visible: slider.value > 0

            Behavior on width {
                enabled: !mouse.pressed
                NumberAnimation {
                    duration: Theme.animationDuration
                }
            }
        }
    }

    Rectangle {
        visible: slider.interactive
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(slider.value, 1)) * (slider.width - width)
        width: slider.active || mouse.pressed ? Theme.knobActiveSize : Theme.knobSize
        height: width
        radius: width / 2
        color: Theme.sliderKnobColor

        Behavior on width {
            NumberAnimation {
                duration: Theme.animationDuration
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: slider.interactive
        cursorShape: Qt.PointingHandCursor
        onPressed: event => slider.moveTo(event.x)
        onPositionChanged: event => {
            if (pressed)
                slider.moveTo(event.x);
        }
    }

    WheelHandler {
        enabled: slider.interactive
        onWheel: event => {
            const notches = event.angleDelta.y / 120;
            slider.moved(Math.round(Math.max(0, Math.min(slider.value + notches * Theme.volumeStep, Math.max(slider.value, 1))) * 100) / 100);
        }
    }
}
