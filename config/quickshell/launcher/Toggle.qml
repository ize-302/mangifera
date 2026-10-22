import QtQuick
import qs

// On/off switch. The row it sits in handles the click.
Rectangle {
    id: toggle

    property bool checked: false

    width: Theme.toggleWidth
    height: Theme.toggleHeight
    radius: height / 2
    color: checked ? Theme.toggleOnColor : Theme.keyColor

    Behavior on color {
        ColorAnimation {
            duration: Theme.animationDuration
        }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: toggle.checked ? toggle.width - width - 2 : 2
        width: toggle.height - 4
        height: width
        radius: width / 2
        color: toggle.checked ? "white" : Theme.dimColor

        Behavior on x {
            NumberAnimation {
                duration: Theme.animationDuration
                easing.type: Easing.OutCubic
            }
        }
    }
}
