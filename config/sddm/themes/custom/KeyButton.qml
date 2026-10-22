import QtQuick
import "."

// Key cap with a glyph and a name, lit while hovered.
Rectangle {
    id: button

    property string icon: ""
    property string label: ""

    signal clicked

    width: row.width + Theme.keyPadding * 2
    height: Theme.keyHeight
    radius: Theme.buttonRadius
    color: area.containsMouse ? Theme.hoverColor : Theme.keyColor
    border.width: 1
    border.color: Theme.edgeColor
    opacity: enabled ? 1 : 0.4

    Behavior on color {
        ColorAnimation {
            duration: Theme.animationDuration
        }
    }

    Row {
        id: row

        anchors.centerIn: parent
        spacing: Theme.keySpacing

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: button.icon
            color: Theme.softTextColor
            font.pixelSize: Theme.iconSize
            font.family: Theme.fontFamily
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: button.label
            color: Theme.softTextColor
            font.pixelSize: Theme.keyFontSize
            font.family: Theme.fontFamily
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
