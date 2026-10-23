pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Toolbox: small tools, floating above the bar's toolbox icon. Toggled by
// ~/.local/bin/toolbox; `--pointer` centres it over the icon. Up/Down (k/j)
// pick, Enter runs, Escape closes.
Scope {
    id: root

    property bool open: false

    // -1 until shell.qml reports the pointer
    property bool atPointer: false
    property real pointerX: -1
    property var pointerScreen: null
    property bool placeWaited: false
    readonly property bool placed: !atPointer || pointerX >= 0 || placeWaited

    // The webcam bubble (CameraWidget.qml) and the record menu
    required property var camera
    required property var recordMenu
    property bool recording: false

    readonly property list<var> entries: [
        {
            id: "camera",
            label: "Camera",
            icon: Theme.recordCameraIcon,
            toggle: true
        },
        {
            id: "record",
            label: root.recording ? "Stop Recording" : "Record Screen",
            icon: Theme.toolboxRecordIcon
        },
        {
            id: "screenshot",
            label: "Screenshot",
            icon: Theme.toolboxScreenshotIcon
        }
    ]
    property int current: 0

    function run(entry) {
        if (entry.id === "camera") {
            camera.open = !camera.open;
            return;
        }
        open = false;
        if (entry.id === "record") {
            if (recording)
                Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/record-toggle"]);
            else
                recordMenu.open = true;
        } else if (entry.id === "screenshot") {
            // Once the menu is gone, so it isn't in the shot
            shotDelay.restart();
        }
    }

    onOpenChanged: {
        if (open) {
            current = 0;
            recordingCheck.running = true;
        } else {
            atPointer = false;
            placeWaited = false;
        }
    }

    Process {
        id: recordingCheck
        command: ["pgrep", "-x", "wf-recorder"]

        onExited: code => root.recording = code === 0
    }

    Timer {
        id: shotDelay
        interval: Theme.appearDuration * 2
        onTriggered: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/screenshot"])
    }

    // Pointer not found: fall back to the right edge
    Timer {
        running: root.open && !root.placed
        interval: 500
        onTriggered: root.placeWaited = true
    }

    // Also called over the launcher socket (shell.qml)
    property alias ipc: ipcHandler

    IpcHandler {
        id: ipcHandler
        target: "toolbox"

        function toggleToolbox(): void {
            root.open = !root.open;
        }

        function toggleToolboxAtPointer(): void {
            if (!root.open)
                root.atPointer = true;
            root.open = !root.open;
        }
    }

    // Widest label, so the panel fits it
    FontMetrics {
        id: longest

        readonly property real widest: Math.max(...root.entries.map(entry => longest.advanceWidth(entry.label)))

        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.weight: Theme.selectedWeight
    }

    PanelWindow { // qmllint disable uncreatable-type
        visible: root.open && root.placed
        screen: (root.atPointer && root.pointerX >= 0 ? root.pointerScreen : null) ?? Compositor.focusedScreen()
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: panel.width
        implicitHeight: panel.height

        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        anchors {
            bottom: true
            right: true
        }
        margins.bottom: Theme.floatingGap
        margins.right: {
            if (!root.atPointer || root.pointerX < 0 || !screen)
                return Theme.floatingGap;
            const right = screen.width - root.pointerX - implicitWidth / 2;
            return Math.round(Math.max(Theme.floatingGap, Math.min(right, screen.width - implicitWidth - Theme.floatingGap)));
        }

        onVisibleChanged: {
            if (!visible)
                return;
            rows.forceActiveFocus();
            panel.appear();
        }

        Glass {
            id: panel

            floating: true
            width: Math.ceil(Theme.iconSize + Theme.iconSpacing * 2 + longest.widest + Theme.toggleWidth) + Theme.rowPadding * 2 + Theme.powerPanelPadding * 2
            height: rows.height + Theme.powerPanelPadding * 2

            Column {
                id: rows

                anchors.centerIn: parent
                width: parent.width - Theme.powerPanelPadding * 2
                spacing: Theme.rowSpacing

                Keys.onPressed: event => {
                    const count = root.entries.length;

                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
                        root.open = false;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.run(root.entries[root.current]);
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.key === Qt.Key_Tab) {
                        root.current = (root.current + 1) % count;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.key === Qt.Key_Backtab) {
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

                        width: rows.width
                        height: Theme.rowHeight + Theme.rowSpacing
                        radius: Theme.cornerRadius
                        color: selected ? Theme.currentRowColor : "transparent"

                        Text {
                            id: icon

                            anchors.left: parent.left
                            anchors.leftMargin: Theme.rowPadding
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.iconSize
                            horizontalAlignment: Text.AlignHCenter
                            text: row.modelData.icon
                            color: row.selected ? Theme.selectedColor : Theme.unselectedColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.iconSize - 4
                        }

                        Text {
                            anchors.left: icon.right
                            anchors.leftMargin: Theme.iconSpacing
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.modelData.label
                            color: row.selected ? Theme.selectedColor : Theme.unselectedColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.weight: row.selected ? Theme.selectedWeight : Theme.unselectedWeight
                        }

                        Toggle {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.rowPadding
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.modelData.toggle ?? false
                            checked: root.camera.open
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
