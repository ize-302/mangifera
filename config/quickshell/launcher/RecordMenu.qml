pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs

// Picks the sound for a screen recording, toggled by ~/.local/bin/record-menu.
// The choice goes to ~/.local/bin/record-toggle, and is preselected next time
// (the dot). The mic tiles show the mic's level, so a dead mic shows before
// recording. The camera tile turns recording with the webcam widget on or off
// (on until turned off, then remembered) and leaves the menu open. While the
// menu is open the widget shows if it's on, and its shape can be picked under
// the tile. 1-4 pick a sound, Space the camera, R its shape.
Scope {
    id: root

    property bool open: false
    // `id` is the option given to record-toggle
    readonly property list<var> sounds: [
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
            icon: Theme.recordMicIcon,
            mic: true
        },
        {
            id: "both",
            label: "Desktop + Mic",
            icon: Theme.recordBothIcon,
            mic: true
        }
    ]
    readonly property var cameraEntry: ({
            id: "camera",
            label: "Camera",
            icon: Theme.recordCameraIcon,
            toggle: true
        })
    // The camera tile comes after the sounds
    readonly property list<var> entries: [...sounds, cameraEntry]
    property int current: 0
    // The last sound picked; desktop until there is one
    property string chosen: "desktop"
    property bool withCamera: cameraFile.text().trim() !== "off"
    // The webcam bubble (CameraWidget.qml), shown while the menu is open so it
    // can be placed before recording
    required property var camera
    // Whether the menu showed the bubble, so closing it without recording
    // hides only what the menu showed
    property bool shownCamera: false
    // Set when a recording starts: record-toggle hides the bubble then
    property bool recording: false

    readonly property PwNode mic: Pipewire.defaultAudioSource
    // 0-1 across the meter's range
    readonly property real micLevel: {
        const db = 20 * Math.log10(Math.max(micPeak.peak, 1e-6));
        return Math.max(0, Math.min(1, (db + Theme.recordMeterFloor) / Theme.recordMeterFloor));
    }

    function run(entry) {
        if (entry.toggle) {
            withCamera = !withCamera;
            cameraFile.setText(withCamera ? "on" : "off");
            camera.open = withCamera;
            shownCamera = withCamera;
            return;
        }
        recording = true;
        open = false;
        chosen = entry.id;
        lastFile.setText(entry.id);
        const args = [Quickshell.env("HOME") + "/.local/bin/record-toggle", "--" + entry.id];
        if (withCamera)
            args.push("--camera");
        Quickshell.execDetached(args);
    }

    // Whether to record with the camera: "on" or "off"
    FileView {
        id: cameraFile

        path: Quickshell.statePath("record-camera")
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: lastFile

        path: Quickshell.statePath("record-sound")
        blockLoading: true
        printErrors: false
    }

    PwObjectTracker {
        objects: root.open && root.mic ? [root.mic] : []
    }

    PwNodePeakMonitor {
        id: micPeak

        node: root.mic
        enabled: root.open
    }

    RecordCountdown {
        id: countdownOverlay
    }

    // Also called over the launcher socket (shell.qml)
    property alias ipc: ipcHandler

    onOpenChanged: {
        if (!open) {
            if (shownCamera && !recording)
                camera.open = false;
            shownCamera = false;
            recording = false;
            return;
        }

        if (withCamera && !camera.open) {
            camera.open = true;
            shownCamera = true;
        }
        chosen = lastFile.text().trim() || "desktop";
        current = Math.max(0, entries.findIndex(entry => entry.id === chosen));
        tiles.forceActiveFocus();
        panel.appear();
    }

    IpcHandler {
        id: ipcHandler
        target: "record"

        function toggleRecordMenu(): void {
            root.open = !root.open;
        }

        // record-toggle, once the area is picked: "<pid> <x>,<y> <w>x<h>".
        // The pid gets SIGUSR1 if it's cancelled. One argument, as the
        // launcher socket passes one
        function countdown(call: string): void {
            const space = call.indexOf(" ");
            countdownOverlay.start(call.slice(space + 1), call.slice(0, space));
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

    component Tile: Rectangle {
        id: tile

        required property var entry
        required property int index
        readonly property bool selected: root.current === index

        width: Math.max(Theme.powerTileWidth, Math.ceil(longest.widest) + Theme.rowPadding * 2)
        height: content.height + Theme.powerTilePadding * 2
        color: tile.selected ? Theme.currentRowColor : "transparent"
        radius: Theme.cornerRadius

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: root.current = tile.index
            onClicked: root.run(tile.entry)
        }

        // The sound used last time
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Theme.powerTilePadding
            width: Theme.recordDotSize
            height: Theme.recordDotSize
            radius: width / 2
            color: Theme.toggleOnColor
            visible: tile.entry.id === root.chosen
        }

        Column {
            id: content

            anchors.centerIn: parent
            width: parent.width - Theme.rowPadding * 2
            spacing: Theme.rowSpacing + 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.entry.icon
                color: tile.entry.toggle && root.withCamera ? Theme.toggleOnColor : tile.selected ? Theme.selectedColor : Theme.unselectedColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.powerIconSize
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.entry.label
                color: tile.selected ? Theme.selectedColor : Theme.unselectedColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.powerFontSize
                font.weight: tile.selected ? Theme.selectedWeight : Theme.unselectedWeight
            }

            // Every tile has the line, so they stay the same height
            Item {
                width: parent.width
                height: Theme.recordStatusHeight

                // Mic level
                Rectangle {
                    visible: tile.entry.mic ?? false
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: Theme.recordMeterHeight
                    radius: height / 2
                    color: Theme.keyColor

                    Rectangle {
                        width: parent.width * root.micLevel
                        height: parent.height
                        radius: parent.radius
                        color: root.micLevel > 0.95 ? Theme.accentColor : Theme.toggleOnColor

                        Behavior on width {
                            NumberAnimation {
                                duration: 80
                            }
                        }
                    }
                }

                // Camera shape, while it's on
                Row {
                    visible: (tile.entry.toggle ?? false) && root.withCamera
                    anchors.centerIn: parent
                    spacing: Theme.rowSpacing * 2

                    Repeater {
                        model: [
                            {
                                shape: "circle",
                                icon: Theme.recordCircleIcon,
                                rotation: 0
                            },
                            {
                                shape: "landscape",
                                icon: Theme.recordRectangleIcon,
                                rotation: 0
                            },
                            {
                                shape: "portrait",
                                icon: Theme.recordRectangleIcon,
                                rotation: 90
                            }
                        ]

                        Text {
                            required property var modelData

                            text: modelData.icon
                            rotation: modelData.rotation
                            color: root.camera.shape === modelData.shape ? Theme.toggleOnColor : Theme.dimColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.recordShapeSize

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -Theme.rowSpacing
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.camera.setShape(parent.modelData.shape)
                            }
                        }
                    }
                }
            }
        }
    }

    component Hint: Row {
        id: hint

        required property string key
        required property string label

        spacing: Theme.keySpacing

        KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            text: hint.key
            fontSize: Theme.sectionFontSize
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: hint.label
            color: Theme.dimColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.sectionFontSize
        }
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
            width: Math.max(tiles.width, hints.width) + Theme.powerPanelPadding * 2
            height: layout.height + Theme.powerPanelPadding * 2

            Column {
                id: layout

                anchors.centerIn: parent
                spacing: Theme.powerPanelPadding

                Row {
                    id: tiles

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.rowSpacing

                    Keys.onPressed: event => {
                        const ctrl = event.modifiers & Qt.ControlModifier;
                        const count = root.entries.length;

                        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                            root.open = false;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.run(root.entries[root.current]);
                        } else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.sounds.length) {
                            root.run(root.sounds[event.key - Qt.Key_1]);
                        } else if (event.key === Qt.Key_Space || event.key === Qt.Key_C) {
                            root.run(root.cameraEntry);
                        } else if (event.key === Qt.Key_R && root.withCamera) {
                            root.camera.rotate();
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
                        model: root.sounds

                        Tile {
                            required property var modelData

                            entry: modelData
                        }
                    }

                    // Sounds pick one; the camera goes with any
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: Theme.powerIconSize * 2
                        color: Theme.dividerColor
                    }

                    Tile {
                        entry: root.cameraEntry
                        index: root.sounds.length
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.dividerColor
                }

                Row {
                    id: hints

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.rowPadding * 2

                    // Which mic the mic tiles record
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.recordMicIcon + " " + (root.mic ? (root.mic.nickname || root.mic.description || root.mic.name) : "No mic")
                        color: Theme.dimColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.sectionFontSize
                    }

                    Hint {
                        key: "1–4"
                        label: "sound"
                    }

                    Hint {
                        key: "Space"
                        label: "camera"
                    }

                    Hint {
                        visible: root.withCamera
                        key: "R"
                        label: "shape"
                    }

                    Hint {
                        key: "Esc"
                        label: "close"
                    }
                }
            }
        }
    }
}
