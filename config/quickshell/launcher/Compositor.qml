pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// mango's monitors and windows via `mmsg watch all-monitors` and `mmsg watch
// all-clients`: which monitor has focus, their tags, and the windows on them.
// Each event carries the whole state. Only the fields used here are kept, and
// only a change to them updates anything: most events are a title ticking, a
// window moving or focus changing, which nothing shows.
Singleton {
    id: root

    // { name, active, keymode, tags: [{ index, is_active, is_urgent,
    // client_count }] }
    property var monitors: []
    // { id, appid, monitor, tags: [index, ...], is_minimized,
    // is_namedscratchpad }, plus title, foreign_toplevel_id and width while
    // minimized (the scratchpad)
    property var clients: []
    // The last kept state as JSON, to tell whether an event changed it
    property string monitorsKey: ""
    property string clientsKey: ""

    function keepMonitor(monitor) {
        return {
            name: monitor.name,
            active: monitor.active,
            keymode: monitor.keymode,
            tags: (monitor.tags ?? []).map(tag => ({
                        index: tag.index,
                        is_active: tag.is_active,
                        is_urgent: tag.is_urgent,
                        client_count: tag.client_count
                    }))
        };
    }

    function keepClient(client) {
        const kept = {
            id: client.id,
            appid: client.appid,
            monitor: client.monitor,
            tags: client.tags ?? [],
            is_minimized: client.is_minimized,
            is_namedscratchpad: client.is_namedscratchpad
        };
        if (client.is_minimized) {
            kept.title = client.title;
            kept.foreign_toplevel_id = client.foreign_toplevel_id;
            kept.width = client.width;
        }
        return kept;
    }
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
                    const monitors = (JSON.parse(line).monitors ?? []).map(root.keepMonitor);
                    const key = JSON.stringify(monitors);
                    if (key !== root.monitorsKey) {
                        root.monitorsKey = key;
                        root.monitors = monitors;
                    }
                } catch (error) {}
            }
        }
    }

    Timer {
        id: restart
        interval: 1000
        onTriggered: watcher.running = true
    }

    Process {
        id: clientWatcher
        running: true
        command: ["mmsg", "watch", "all-clients"]

        onExited: clientRestart.restart()

        stdout: SplitParser {
            onRead: line => {
                try {
                    const clients = (JSON.parse(line).clients ?? []).map(root.keepClient);
                    const key = JSON.stringify(clients);
                    if (key !== root.clientsKey) {
                        root.clientsKey = key;
                        root.clients = clients;
                    }
                } catch (error) {}
            }
        }
    }

    Timer {
        id: clientRestart
        interval: 1000
        onTriggered: clientWatcher.running = true
    }
}
