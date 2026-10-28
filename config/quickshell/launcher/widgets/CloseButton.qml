import QtQuick
import qs

// Close button that fades in on a hovered card: a tab flush inside its top
// right corner, square on the card's edges and rounded where it meets the
// preview, or a bigger `square` one. White while hovered, or while `lit`
// (its card is hovered).
Rectangle {
    id: button

    property bool shown: false
    // The card's corner radius, which the tab's outer corner follows
    property real outerRadius: 0
    property bool square: false
    property bool lit: false
    readonly property alias hovered: mouse.containsMouse

    signal clicked

    width: square ? Theme.overviewCloseSize : Theme.closeButtonSize
    height: width
    radius: 0
    topRightRadius: square ? 0 : outerRadius
    bottomLeftRadius: square ? 0 : Theme.cornerRadius * 2
    color: hovered || lit ? Theme.scratchpadCloseColor : Theme.glassPanelColor
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
        color: button.hovered || button.lit ? Theme.panelColor : Theme.keyTextColor
        font.family: Theme.fontFamily
        font.pixelSize: button.square ? Theme.overviewCloseFontSize : Theme.controlFontSize
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
