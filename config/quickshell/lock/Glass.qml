import QtQuick
import qs

// Floating glass, like the launcher's. Rises into place with appear().
Rectangle {
    id: glass

    // Red after a wrong password
    property color edgeColor: Theme.edgeColor

    color: Theme.glassColor

    function appear() {
        animation.restart();
    }

    transform: Translate {
        id: slide
    }

    ParallelAnimation {
        id: animation

        NumberAnimation {
            target: slide
            property: "y"
            from: 16
            to: 0
            duration: Theme.animationDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: glass
            property: "opacity"
            from: 0
            to: 1
            duration: Theme.animationDuration
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Theme.sheenTop
            }
            GradientStop {
                position: 0.45
                color: Theme.sheenMiddle
            }
            GradientStop {
                position: 1
                color: "transparent"
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: glass.radius
        border.width: 1
        border.color: glass.edgeColor

        Behavior on border.color {
            ColorAnimation {
                duration: Theme.animationDuration
            }
        }
    }
}
