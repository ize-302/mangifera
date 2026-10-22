pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import qs

// A notification card in the notification centre. A collapsed stack (`stack` >
// 1) shows two card edges peeking out below and its × dismisses the whole
// stack. In an expanded stack, `joinedAbove`/`joinedBelow` square the corners
// so they read as one card.
Item {
    id: card

    required property var notification
    required property var server
    // 1, or the size of a collapsed stack
    property int stack: 1
    property bool selected: false
    property bool joinedAbove: false
    property bool joinedBelow: false
    readonly property bool hovered: hover.hovered

    signal clicked
    signal closeClicked

    implicitHeight: face.height + (stack > 1 ? Theme.noteCardStackPeek * 2 : 0)

    HoverHandler {
        id: hover
    }

    // Only the bottoms of the cards behind show, as the cards are see-through
    Repeater {
        model: card.stack > 1 ? 2 : 0

        Item {
            required property int index

            x: Theme.noteCardStackInset * (index + 1)
            y: face.height + Theme.noteCardStackPeek * index
            width: card.width - x * 2
            height: Theme.noteCardStackPeek
            clip: true

            Rectangle {
                y: parent.height - height
                width: parent.width
                height: Theme.noteCardStackPeek * 2
                radius: Theme.cornerRadius
                color: Theme.noteCardColor
                opacity: 1 - parent.index * 0.35
            }
        }
    }

    Rectangle {
        id: face

        width: parent.width
        height: content.implicitHeight + Theme.panelPadding * 2
        topLeftRadius: card.joinedAbove ? 0 : Theme.cornerRadius
        topRightRadius: card.joinedAbove ? 0 : Theme.cornerRadius
        bottomLeftRadius: card.joinedBelow ? 0 : Theme.cornerRadius
        bottomRightRadius: card.joinedBelow ? 0 : Theme.cornerRadius
        color: hover.hovered || card.selected ? Theme.noteCardHoverColor : Theme.noteCardColor

        Behavior on color {
            ColorAnimation {
                duration: Theme.animationDuration
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: card.clicked()
        }

        Rectangle {
            visible: card.joinedAbove
            x: Theme.panelPadding
            width: parent.width - x * 2
            height: 1
            color: Theme.dividerColor
        }

        Row {
            id: content

            x: Theme.panelPadding
            y: Theme.panelPadding
            width: parent.width - x * 2
            spacing: Theme.iconSpacing

            IconImage {
                property int tried: 0
                readonly property list<string> candidates: card.notification ? card.server.icons(card.notification) : []

                implicitSize: Theme.notificationIconSize
                source: candidates[tried] ?? ""
                onStatusChanged: if (status === Image.Error && tried < candidates.length - 1)
                    tried++
            }

            Column {
                width: parent.width - Theme.notificationIconSize - parent.spacing
                spacing: Theme.rowSpacing

                // Hidden in an expanded stack, whose header names the app; the
                // age and × move to the summary line
                Item {
                    id: topLine

                    visible: !card.joinedAbove
                    width: parent.width
                    height: Math.max(app.implicitHeight, meta.implicitHeight)

                    Text {
                        id: app
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - meta.width - Theme.iconSpacing
                        text: (card.notification?.appName || "Notification").toUpperCase()
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.dimColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.sectionFontSize
                        font.weight: Theme.fontWeight
                        font.letterSpacing: 1
                    }
                }

                Item {
                    id: summaryLine

                    width: parent.width
                    height: summary.implicitHeight
                    visible: summary.text !== ""

                    Text {
                        id: summary

                        readonly property real lineHeight: lineCount > 0 ? contentHeight / lineCount : implicitHeight

                        width: parent.width - (card.joinedAbove ? meta.width + Theme.iconSpacing : 0)
                        text: card.notification?.summary ?? ""
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        color: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.controlFontSize
                        font.weight: Theme.fontWeight
                    }
                }

                Row {
                    id: meta

                    parent: card.joinedAbove ? summaryLine : topLine
                    anchors.right: parent.right
                    y: ((card.joinedAbove ? summary.lineHeight : topLine.height) - height) / 2
                    spacing: Theme.iconSpacing

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: card.notification ? card.server.age(card.notification) : ""
                        color: Theme.dimColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.controlSmallFontSize
                        font.weight: Theme.fontWeight
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: hover.hovered || card.selected ? 1 : 0
                        text: Theme.closeIcon
                        color: closeMouse.containsMouse ? Theme.textColor : Theme.keyTextColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.controlFontSize

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.animationDuration
                            }
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.closeClicked()
                        }
                    }
                }

                // Apps may send simple markup
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: card.notification?.body ?? ""
                    textFormat: Text.StyledText
                    wrapMode: Text.Wrap
                    maximumLineCount: Theme.notificationBodyLines
                    elide: Text.ElideRight
                    color: Theme.keyTextColor
                    linkColor: Theme.textColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlSmallFontSize + 1
                    font.weight: Theme.fontWeight
                }

                Flow {
                    readonly property list<var> actions: (card.notification?.actions ?? []).filter(action => action.identifier !== "default")

                    width: parent.width
                    visible: actions.length > 0
                    topPadding: Theme.rowSpacing
                    spacing: Theme.keySpacing

                    Repeater {
                        model: parent.actions

                        KeyCap {
                            id: actionCap

                            required property var modelData

                            text: modelData.text
                            fontSize: Theme.controlSmallFontSize
                            lit: actionMouse.containsMouse

                            MouseArea {
                                id: actionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: actionCap.modelData.invoke()
                            }
                        }
                    }
                }
            }
        }
    }
}
