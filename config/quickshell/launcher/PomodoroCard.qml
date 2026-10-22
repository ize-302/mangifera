pragma ComponentBehavior: Bound

import QtQuick
import qs

// Pomodoro card in the date panel: phase, session dots, controls, time left and
// a progress bar.
Rectangle {
    id: card

    // Pomodoro.qml
    property var pomodoro: null

    readonly property bool focusing: (pomodoro?.phase ?? "focus") === "focus"

    height: rows.height + Theme.panelPadding
    radius: Theme.cornerRadius
    color: Theme.noteCardColor

    Column {
        id: rows

        x: Theme.panelPadding
        y: Theme.panelPadding / 2
        width: parent.width - x * 2

        Item {
            width: parent.width
            height: Theme.noteCardButtonHeight + Theme.rowSpacing * 2

            Text {
                id: title
                anchors.verticalCenter: parent.verticalCenter
                text: card.pomodoro?.label ?? ""
                color: Theme.textColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.searchFontSize
                font.weight: Font.DemiBold
            }

            // A dot per focus session in the round, finished ones filled
            Row {
                anchors.left: title.right
                anchors.leftMargin: Theme.iconSpacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.keySpacing

                Repeater {
                    model: Theme.pomodoroRounds

                    Rectangle {
                        required property int index

                        width: Theme.pomodoroDotSize
                        height: width
                        radius: width / 2
                        color: index < (card.pomodoro?.done ?? 0) ? Theme.toggleOnColor : Theme.keyColor
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.keySpacing * 2

                Repeater {
                    model: [
                        {
                            icon: (card.pomodoro?.running ?? false) ? Theme.pauseIcon : Theme.playIcon,
                            action: "toggle",
                            lit: card.pomodoro?.running ?? false
                        },
                        {
                            icon: Theme.nextIcon,
                            action: "skip",
                            lit: false
                        },
                        {
                            icon: Theme.powerRestartIcon,
                            action: "reset",
                            lit: false
                        }
                    ]

                    Rectangle {
                        id: button

                        required property var modelData

                        width: Theme.noteCardButtonHeight
                        height: width
                        radius: Theme.cornerRadius
                        color: modelData.lit ? Theme.toggleOnColor : buttonMouse.containsMouse ? Theme.hoverColor : Theme.keyColor

                        Text {
                            anchors.centerIn: parent
                            text: button.modelData.icon
                            color: button.modelData.lit ? "white" : Theme.keyTextColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.controlFontSize
                        }

                        MouseArea {
                            id: buttonMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.pomodoro[button.modelData.action]()
                        }
                    }
                }
            }
        }

        Row {
            width: parent.width
            height: Theme.rowHeight
            spacing: Theme.iconSpacing

            Text {
                id: time

                anchors.verticalCenter: parent.verticalCenter
                text: card.pomodoro?.clock ?? ""
                color: (card.pomodoro?.running ?? false) ? Theme.textColor : Theme.dimColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.pomodoroFontSize
                font.weight: Font.DemiBold
                font.features: {
                    "tnum": 1
                }
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - time.width - parent.spacing
                interactive: false
                value: card.pomodoro ? 1 - card.pomodoro.left / card.pomodoro.length : 0
                color: card.focusing ? Theme.toggleOnColor : Theme.pomodoroBreakColor
            }
        }
    }
}
