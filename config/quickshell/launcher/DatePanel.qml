pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Date panel: pomodoro card over a month calendar, floating above the bar.
// Toggled by ~/.local/bin/date-panel; `--pointer` centres it over the clock.
// Keys: Left/Right (h/l) change month, t this month, p starts or pauses the
// timer, Escape closes.
Scope {
    id: root

    property bool open: false

    // -1 until shell.qml reports the pointer
    property bool atPointer: false
    property real pointerX: -1
    property var pointerScreen: null
    property bool placeWaited: false
    readonly property bool placed: !atPointer || pointerX >= 0 || placeWaited
    property var pomodoro: null

    onOpenChanged: {
        if (!open) {
            atPointer = false;
            placeWaited = false;
        }
    }

    // Pointer not found: fall back to the right edge
    Timer {
        running: root.open && !root.placed
        interval: 500
        onTriggered: root.placeWaited = true
    }

    IpcHandler {
        target: "datePanel"

        function toggleDatePanel(): void {
            root.open = !root.open;
        }

        function toggleDatePanelAtPointer(): void {
            if (!root.open)
                root.atPointer = true;
            root.open = !root.open;
        }

        function openDatePanel(): void {
            root.open = true;
        }

        function closeDatePanel(): void {
            root.open = false;
        }
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: window

        visible: root.open && root.placed
        screen: (root.atPointer && root.pointerX >= 0 ? root.pointerScreen : null) ?? Compositor.focusedScreen()
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: Theme.notificationWidth
        implicitHeight: panel.height

        // No shadow: no panel to cast one
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

            calendar.reset();
            content.forceActiveFocus();
            panel.appear();
        }

        Glass {
            id: panel

            floating: true
            color: "transparent"
            edgeColor: "transparent"

            width: parent.width
            height: content.height

            Column {
                id: content

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Theme.notificationSpacing

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
                        root.open = false;
                    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        calendar.step(-1);
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        calendar.step(1);
                    } else if (event.key === Qt.Key_T) {
                        calendar.reset();
                    } else if (event.key === Qt.Key_P && root.pomodoro) {
                        root.pomodoro.toggle();
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                PomodoroCard {
                    width: parent.width
                    pomodoro: root.pomodoro
                }

                Calendar {
                    id: calendar
                    width: parent.width
                }
            }
        }
    }
}
