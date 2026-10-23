pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Picks the sound for a screen recording, toggled by ~/.local/bin/record-menu.
// The choice goes to ~/.local/bin/record-toggle, and is preselected next time.
// The camera tile shows or hides the webcam widget and leaves the menu open.
Scope {
    id: root

    property bool open: false
    // `id` is the option given to record-toggle
    readonly property list<var> entries: [
        {
            id: "none",
            label: "No Sound",
            icon: Theme.recordNoSoundIcon
        },
        {
            id: "desktop",
            label: "Desktop",
            icon: Theme.recordDesktopIcon
        },
        {
            id: "mic",
            label: "Mic",
            icon: Theme.recordMicIcon
        },
        {
            id: "both",
            label: "Desktop + Mic",
            icon: Theme.recordBothIcon
        },
        {
            id: "camera",
            label: "Camera",
            icon: Theme.recordCameraIcon,
            toggle: true
        }
    ]
    property int current: 0
    // The webcam bubble (CameraWidget.qml)
    required property var camera

    function run(entry) {
        if (entry.toggle) {
            camera.open = !camera.open;
            return;
        }
        open = false;
        lastFile.setText(entry.id);
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/record-toggle", "--" + entry.id]);
    }

    // The last choice; desktop sound until there is one
    FileView {
        id: lastFile

        path: Quickshell.statePath("record-sound")
        blockLoading: true
        printErrors: false
    }

    // Also called over the launcher socket (shell.qml)
    property alias ipc: ipcHandler

    onOpenChanged: {
        if (!open)
            return;

        current = Math.max(0, entries.findIndex(entry => entry.id === (lastFile.text().trim() || "desktop")));
        tiles.forceActiveFocus();
        panel.appear();
    }

    IpcHandler {
        id: ipcHandler
        target: "record"

        function toggleRecordMenu(): void {
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
        // Follows focus: a mapped surface stays on the monitor it was made on
        screen: Compositor.focusedScreen()
        // Stays mapped while closed, just empty and click-through: mapping a
        // surface again took ~40 ms each open
        mask: Region {
            item: root.open ? panel : null
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: panel.width
        implicitHeight: panel.height

        // No shadow, like the bar. Only the bottom anchored: centred across
        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors.bottom: true
        margins.bottom: Theme.centredGap

        Glass {
            id: panel

            visible: root.open
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
                                color: row.modelData.toggle && root.camera.open ? Theme.toggleOnColor : row.selected ? Theme.selectedColor : Theme.unselectedColor
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
