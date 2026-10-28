pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// mango's monitors and windows via `mmsg watch all-monitors` and `mmsg watch
// all-clients`: which monitor has focus, their tags, and what's on them. Each
// event carries the whole state.
Singleton {
    id: root

    // As mmsg prints them: { name, active, tags: [{ index, is_active,
    // client_count, ... }], ... }
    property var monitors: []
    readonly property var focusedMonitor: monitors.find(monitor => monitor.active) ?? null
    readonly property string focusedMonitorName: focusedMonitor?.name ?? ""
    // As mmsg prints them, without titles or geometry: { id, appid, monitor,
    // tags: [index], is_minimized, is_fullscreen, ... }. Those are left out so
    // a browser tab ticking its title, or a window moving, doesn't update
    // every binding
    property var clients: []
    // Windows parked in the scratchpad (minimized), in full as mmsg prints
    // them. Named scratchpads are mango's own toggled windows, not parked ones
    property var parked: []

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

    Process {
        id: clientWatcher
        running: true
        command: ["mmsg", "watch", "all-clients"]

        onExited: clientRestart.restart()

        // Each is only replaced when it changed
        stdout: SplitParser {
            property string lastClients
            property string lastParked

            onRead: line => {
                try {
                    const all = JSON.parse(line).clients ?? [];

                    const parked = all.filter(client => client.is_minimized && !client.is_namedscratchpad);
                    const parkedKey = JSON.stringify(parked);
                    if (parkedKey !== lastParked) {
                        lastParked = parkedKey;
                        root.parked = parked;
                    }

                    const clients = all.map(client => {
                        const stripped = Object.assign({}, client);
                        for (const field of ["title", "x", "y", "width", "height", "scroller_proportion"])
                            delete stripped[field];
                        return stripped;
                    });
                    const clientsKey = JSON.stringify(clients);
                    if (clientsKey !== lastClients) {
                        lastClients = clientsKey;
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
