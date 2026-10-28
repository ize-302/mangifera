pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import qs

// Month view in the date panel. Weeks from Monday, today circled; scrolling
// changes month. The owner calls reset() to return to this month.
Rectangle {
    id: calendar

    property date today: new Date()
    property int month: today.getMonth()
    property int year: today.getFullYear()

    function reset() {
        today = new Date();
        month = today.getMonth();
        year = today.getFullYear();
    }

    // Forwards (1) or back (-1)
    function step(months) {
        const date = new Date(year, month + months, 1);
        month = date.getMonth();
        year = date.getFullYear();
        fade.restart();
    }

    height: rows.height + Theme.panelPadding
    radius: Theme.cornerRadius
    color: Theme.noteCardColor

    // Today moves on at midnight while it's open
    Timer {
        running: calendar.visible
        repeat: true
        interval: 60 * 1000
        onTriggered: {
            const now = new Date();
            if (now.getDate() !== calendar.today.getDate())
                calendar.today = now;
        }
    }

    WheelHandler {
        onWheel: event => calendar.step(event.angleDelta.y > 0 ? -1 : 1)
    }

    Column {
        id: rows

        x: Theme.panelPadding
        y: Theme.panelPadding / 2
        width: parent.width - x * 2

        Item {
            width: parent.width
            height: Theme.noteCardButtonHeight + Theme.rowSpacing * 2

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.locale().standaloneMonthName(calendar.month) + " " + calendar.year
                color: Theme.textColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.searchFontSize
                font.weight: Font.DemiBold
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.keySpacing * 2

                Repeater {
                    model: [
                        {
                            icon: Theme.backIcon,
                            months: -1
                        },
                        {
                            icon: Theme.pageIcon,
                            months: 1
                        }
                    ]

                    Rectangle {
                        id: arrow

                        required property var modelData

                        width: Theme.noteCardButtonHeight
                        height: width
                        radius: Theme.cornerRadius
                        color: arrowMouse.containsMouse ? Theme.hoverColor : Theme.keyColor

                        Text {
                            anchors.centerIn: parent
                            text: arrow.modelData.icon
                            color: Theme.keyTextColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.controlFontSize
                        }

                        MouseArea {
                            id: arrowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: calendar.step(arrow.modelData.months)
                        }
                    }
                }
            }
        }

        // The templates: QtQuick.Controls' styled ones drew nothing here
        T.AbstractDayOfWeekRow {
            id: weekdays

            width: parent.width
            implicitHeight: contentItem.implicitHeight
            locale: grid.locale

            contentItem: Row {
                Repeater {
                    model: weekdays.source
                    delegate: weekdays.delegate
                }
            }

            delegate: Text {
                required property string shortName

                width: weekdays.width / 7
                height: Theme.calendarCellSize
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: shortName
                color: Theme.dimColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.controlSmallFontSize
                font.weight: Theme.fontWeight
            }
        }

        T.AbstractMonthGrid {
            id: grid

            width: parent.width
            implicitHeight: contentItem.implicitHeight
            month: calendar.month
            year: calendar.year
            // Weeks from Monday
            locale: Qt.locale("en_GB")

            contentItem: Grid {
                rows: 6
                columns: 7

                Repeater {
                    model: grid.source
                    delegate: grid.delegate
                }
            }

            delegate: Item {
                id: day

                required property var model
                readonly property bool isToday: model.day === calendar.today.getDate() && model.month === calendar.today.getMonth() && model.year === calendar.today.getFullYear()

                width: grid.width / 7
                height: Theme.calendarCellSize

                Rectangle {
                    anchors.centerIn: parent
                    visible: day.isToday
                    width: Theme.calendarCellSize - Theme.rowSpacing * 2
                    height: width
                    radius: width / 2
                    color: Theme.toggleOnColor
                }

                Text {
                    anchors.centerIn: parent
                    text: day.model.day
                    color: day.isToday ? "white" : day.model.month === calendar.month ? Theme.textColor : Theme.dimColor
                    opacity: day.isToday || day.model.month === calendar.month ? 1 : 0.6
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.calendarFontSize
                    font.weight: day.isToday ? Theme.selectedWeight : Theme.fontWeight
                }
            }

            NumberAnimation {
                id: fade
                target: grid
                property: "opacity"
                from: 0.3
                to: 1
                duration: Theme.animationDuration
            }
        }
    }
}
