import QtQuick
import qs

// Close button that fades in on a hovered card: a tab flush inside its top
// right corner, square on the card's edges and rounded where it meets the
// preview, or `outside`, a badge centred on the card's corner. White while
// hovered.
Rectangle {
    id: button

    property bool shown: false
    // The card's corner radius, which the tab's outer corner follows
    property real outerRadius: 0
    property bool outside: false
    readonly property alias hovered: mouse.containsMouse

    signal clicked

    width: Theme.closeButtonSize
    height: Theme.closeButtonSize
    radius: 0
    topLeftRadius: outside ? Theme.cornerRadius : 0
    topRightRadius: outside ? Theme.cornerRadius : outerRadius
    bottomLeftRadius: Theme.cornerRadius * (outside ? 1 : 2)
    bottomRightRadius: outside ? Theme.cornerRadius : 0
    color: hovered ? Theme.scratchpadCloseColor : Theme.glassPanelColor
    // Sets the badge off from the preview it overlaps
    border.width: outside ? 1 : 0
    border.color: hovered ? Theme.scratchpadCloseColor : Theme.edgeColor
    opacity: shown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.animationDuration
        }
    }
    Behavior on color {
        ColorAnimation {
            duration: Theme.animationDuration
        }
    }

    Text {
        anchors.centerIn: parent
        text: Theme.closeIcon
        color: button.hovered ? Theme.panelColor : Theme.keyTextColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.controlFontSize
        scale: mouse.pressed ? 0.85 : 1

        Behavior on color {
            ColorAnimation {
                duration: Theme.animationDuration
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Theme.animationDuration
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
