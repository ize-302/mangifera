pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Power menu, toggled by ~/.local/bin/power-menu, which also carries out the
// choice.
Scope {
    id: root

    property bool open: false
    // `id` is the argument given to power-menu
    readonly property list<var> entries: [
        {
            id: "lock",
            label: "Lock",
            icon: Theme.powerLockIcon
        },
        {
            id: "logout",
            label: "Log Out",
            icon: Theme.powerLogoutIcon
        },
        {
            id: "sleep",
            label: "Sleep",
            icon: Theme.powerSleepIcon
        },
        {
            id: "reboot",
            label: "Restart",
            icon: Theme.powerRestartIcon
        },
        {
            id: "shutdown",
            label: "Shut Down",
            icon: Theme.powerShutDownIcon
        }
    ]
    property int current: 0

    function run(entry) {
        open = false;
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/power-menu", entry.id]);
    }

    IpcHandler {
        target: "power"

        function togglePowerMenu(): void {
            root.open = !root.open;
        }
    }

    // Widest label, so every tile is as wide
    FontMetrics {
        id: longest

        readonly property real widest: Math.max(...root.entries.map(entry => longest.advanceWidth(entry.label)))

        font.family: Theme.fontFamily
        font.pixelSize: Theme.powerFontSize
        font.weight: Theme.selectedWeight
    }

    PanelWindow { // qmllint disable uncreatable-type
        visible: root.open
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: panel.width
        implicitHeight: panel.height

        // No shadow, like the bar. Only the bottom anchored: centred across
        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors.bottom: true
        margins.bottom: Theme.centredGap

        onVisibleChanged: {
            if (!visible)
                return;

            root.current = 0;
            tiles.forceActiveFocus();
            panel.appear();
        }

        Glass {
            id: panel

            floating: true
            color: Theme.powerColor
            width: tiles.width + Theme.powerPanelPadding * 2
            height: tiles.height + Theme.powerPanelPadding * 2

            Row {
                id: tiles

                anchors.centerIn: parent
                spacing: Theme.rowSpacing

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const count = root.entries.length;

                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                        root.open = false;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.run(root.entries[root.current]);
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (ctrl && event.key === Qt.Key_N)) {
                        root.current = (root.current + 1) % count;
                    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || (ctrl && event.key === Qt.Key_P)) {
                        root.current = (root.current + count - 1) % count;
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Repeater {
                    model: root.entries

                    Rectangle {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property bool selected: root.current === index

                        width: Math.max(Theme.powerTileWidth, Math.ceil(longest.widest) + Theme.rowPadding * 2)
                        height: tile.height + Theme.powerTilePadding * 2
                        color: row.selected ? Theme.currentRowColor : "transparent"
                        radius: Theme.cornerRadius

                        Column {
                            id: tile

                            anchors.centerIn: parent
                            spacing: Theme.rowSpacing + 2

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: row.modelData.icon
                                color: row.selected ? Theme.selectedColor : Theme.unselectedColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.powerIconSize
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: row.modelData.label
                                color: row.selected ? Theme.selectedColor : Theme.unselectedColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.powerFontSize
                                font.weight: row.selected ? Theme.selectedWeight : Theme.unselectedWeight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: root.current = row.index
                            onClicked: root.run(row.modelData)
                        }
                    }
                }
            }
        }
    }
}
