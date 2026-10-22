pragma ComponentBehavior: Bound

import QtQuick
import "."

// Popup list, starting on the current item. Opens above or below `anchor`;
// closes on Escape, a click outside or a pick.
Item {
    id: menu

    property list<string> items: []
    // Optional glyph per label
    property list<string> icons: []
    property int currentIndex: 0
    // Above it unless `below`
    property Item anchor: null
    property bool below: false
    property int highlighted: 0
    // Under the anchor's centre, or from its left edge
    property bool centred: true

    signal picked(int index)

    anchors.fill: parent
    visible: false

    function open() {
        // Taken now: mapToItem doesn't follow layout changes
        panel.origin = anchor ? anchor.mapToItem(menu, 0, 0) : Qt.point(0, 0);
        highlighted = Math.max(0, currentIndex);
        visible = true;
        panel.appear();
        list.forceActiveFocus();
    }

    function close() {
        visible = false;
    }

    MouseArea {
        anchors.fill: parent
        onClicked: menu.close()
    }

    Glass {
        id: panel

        property point origin

        width: Theme.menuWidth
        height: list.height + Theme.menuPadding * 2
        radius: Theme.menuRadius
        color: Theme.menuColor
        x: {
            const left = menu.centred ? origin.x + (menu.anchor?.width ?? 0) / 2 - width / 2 : origin.x;
            return Math.round(Math.max(Theme.bottomMargin, Math.min(left, menu.width - width - Theme.bottomMargin)));
        }
        y: menu.below ? origin.y + (menu.anchor?.height ?? 0) + Theme.menuGap : origin.y - height - Theme.menuGap

        // Clicks on the panel stay on it
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: list

            x: Theme.menuPadding
            y: Theme.menuPadding
            width: parent.width - Theme.menuPadding * 2
            focus: true

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Up) {
                    menu.highlighted = (menu.highlighted + menu.items.length - 1) % menu.items.length;
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                    menu.highlighted = (menu.highlighted + 1) % menu.items.length;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    menu.picked(menu.highlighted);
                    menu.close();
                } else if (event.key === Qt.Key_Escape) {
                    menu.close();
                } else {
                    return;
                }
                event.accepted = true;
            }

            Repeater {
                model: menu.items

                Rectangle {
                    id: row

                    required property int index
                    required property string modelData
                    readonly property bool lit: index === menu.highlighted

                    width: list.width
                    height: Theme.rowHeight
                    radius: Theme.rowRadius
                    color: lit ? Theme.menuCurrentRowColor : "transparent"

                    Text {
                        id: glyph
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        width: visible ? Theme.iconSize + Theme.keySpacing : 0
                        visible: text !== ""
                        text: menu.icons[row.index] ?? ""
                        color: row.lit ? Theme.menuTextColor : Theme.menuSoftTextColor
                        font.pixelSize: Theme.iconSize
                        font.family: Theme.fontFamily
                    }

                    Text {
                        anchors.left: glyph.visible ? glyph.right : parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: glyph.visible ? 0 : Theme.rowPadding
                        anchors.rightMargin: Theme.rowPadding
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData
                        elide: Text.ElideRight
                        color: row.lit ? Theme.menuTextColor : Theme.menuSoftTextColor
                        font.pixelSize: Theme.inputFontSize
                        font.family: Theme.fontFamily
                        font.weight: row.lit ? Theme.menuSelectedWeight : Font.Normal
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: menu.highlighted = row.index
                        onClicked: {
                            menu.picked(row.index);
                            menu.close();
                        }
                    }
                }
            }
        }
    }
}
