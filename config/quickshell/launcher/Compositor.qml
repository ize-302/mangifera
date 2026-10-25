pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// mango's monitors via `mmsg watch all-monitors`: which has focus, and their
// tags. Each event carries the whole state.
Singleton {
    id: root

    // As mmsg prints them: { name, active, tags: [{ index, is_active,
    // client_count, ... }], ... }
    property var monitors: []
    readonly property var focusedMonitor: monitors.find(monitor => monitor.active) ?? null
    readonly property string focusedMonitorName: focusedMonitor?.name ?? ""

    function focusedScreen() {
        return Quickshell.screens.find(screen => screen.name === root.focusedMonitorName) ?? null;
    }

    // Briefly true after screens come or go, so windows that stay mapped
    // unmap and map again: one left without a screen (every display off at
    // once, as when unplugging with the lid closed) never shows again
    property bool remapping: false

    Connections {
        target: Quickshell

        function onScreensChanged() {
            root.remapping = true;
            remap.restart();
        }
    }

    Timer {
        id: remap
        interval: 250
        onTriggered: root.remapping = false
    }

    Process {
        id: watcher
        running: true
        command: ["mmsg", "watch", "all-monitors"]

        // Restarted if mmsg exits (mango restarting)
        onExited: restart.restart()

        stdout: SplitParser {
            onRead: line => {
                try {
                    root.monitors = JSON.parse(line).monitors ?? [];
                } catch (error) {}
            }
        }
    }

    Timer {
        id: restart
        interval: 1000
        onTriggered: watcher.running = true
    }
}
