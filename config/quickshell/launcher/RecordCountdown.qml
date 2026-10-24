pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// 3-2-1 over the picked area before ~/.local/bin/record-toggle starts
// recording, with the area outlined. Gone before the recording starts, so it
// isn't in it. Escape sends the script SIGUSR1, which cancels.
Scope {
    id: root

    property bool running: false
    property int count: 0
    // The area in global coordinates, and the screen it's on
    property rect area
    property var screen: null
    property string caller: ""

    // `geometry` as slurp prints it: "x,y wxh"
    function start(geometry, pid) {
        const match = geometry.match(/^(-?\d+),(-?\d+) (\d+)x(\d+)$/);
        if (!match)
            return;
        area = Qt.rect(+match[1], +match[2], +match[3], +match[4]);
        const centreX = area.x + area.width / 2;
        const centreY = area.y + area.height / 2;
        screen = Quickshell.screens.find(s => centreX >= s.x && centreX < s.x + s.width && centreY >= s.y && centreY < s.y + s.height) ?? Compositor.focusedScreen();
        caller = pid;
        count = Theme.recordCountdownSeconds;
        running = true;
        tick.restart();
    }

    function cancel() {
        running = false;
        tick.stop();
        if (caller)
            Quickshell.execDetached(["kill", "-USR1", caller]);
    }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.count -= 1;
            if (root.count <= 0) {
                root.running = false;
                stop();
            }
        }
    }

    PanelWindow { // qmllint disable uncreatable-type
        screen: root.screen
        visible: root.running
        // Clicks go through, except on the number
        mask: Region {
            item: box
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.running ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        onVisibleChanged: if (visible)
            keys.forceActiveFocus()

        Item {
            id: keys

            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.cancel()

            // What will be recorded, relative to this screen
            Rectangle {
                x: root.area.x - (root.screen?.x ?? 0) - border.width
                y: root.area.y - (root.screen?.y ?? 0) - border.width
                width: root.area.width + border.width * 2
                height: root.area.height + border.width * 2
                color: "transparent"
                border.width: Theme.recordOutlineWidth
                border.color: Theme.accentColor
                radius: Theme.cornerRadius
            }

            Rectangle {
                id: box

                x: root.area.x - (root.screen?.x ?? 0) + (root.area.width - width) / 2
                y: root.area.y - (root.screen?.y ?? 0) + (root.area.height - height) / 2
                width: Theme.recordCountdownSize
                height: Theme.recordCountdownSize
                radius: Theme.panelRadius
                color: Theme.powerColor

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -Theme.rowSpacing * 2
                    text: root.count
                    color: Theme.textColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.recordCountdownFontSize
                    font.weight: Theme.selectedWeight
                    font.features: {
                        "tnum": 1
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Theme.powerTilePadding
                    text: "Esc to cancel"
                    color: Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sectionFontSize
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cancel()
                }
            }
        }
    }
}
