//@ pragma IconTheme Papirus

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Launcher daemon (`qs -c launcher -d`): the app menu plus every other menu,
// panel, popup, notification and prompt. Toggled over IPC by the ~/.local/bin
// scripts.
ShellRoot {
    id: root

    // Desktop entry id -> times launched; most used first
    property var history: ({})
    readonly property list<QtObject> menus: [appMenu, powerMenu, clipboardMenu, scratchpadMenu, keybindMenu, controlPanel, notificationCenter, datePanel]
    readonly property bool anyOpen: menus.some(menu => menu.open)
    // Pointer x on its screen when a menu opened, snapped to the bar module's
    // centre (~/.local/bin/bar-anchor); -1 until known
    property real pointerX: -1
    property var pointerScreen: null
    property bool pointerSeen: false

    // A surface appearing under a still pointer gets no position, so ask mango
    // too
    onAnyOpenChanged: {
        pointerX = -1;
        pointerSeen = false;
        if (anyOpen)
            cursor.running = true;
    }

    // x is on the given screen
    function notePointer(screen, x) {
        if (root.pointerSeen || !screen)
            return;
        root.pointerSeen = true;
        root.pointerScreen = screen;
        anchor.screenX = screen.x;
        anchor.pointer = x;
        anchor.command = [Theme.barAnchor, String(screen.x + x), String(screen.y + screen.height - Theme.barHeight), String(Theme.barHeight)];
        anchor.running = true;
    }

    // Falls back to the pointer itself
    Process {
        id: anchor

        property real screenX: 0
        property real pointer: -1

        stdout: StdioCollector {
            onStreamFinished: {
                const x = parseFloat(text);
                root.pointerX = isNaN(x) ? anchor.pointer : x - anchor.screenX;
            }
        }
    }

    // { x, y, monitor }, x in global layout coordinates
    Process {
        id: cursor
        command: ["mmsg", "get", "cursorpos"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const position = JSON.parse(text);
                    const screen = Quickshell.screens.find(screen => screen.name === position.monitor);
                    if (root.anyOpen && screen)
                        root.notePointer(screen, position.x - screen.x);
                } catch (error) {}
            }
        }
    }

    // Only one menu open at a time
    function closeOthers(menu) {
        for (const other of menus) {
            if (other !== menu)
                other.open = false;
        }
    }

    // While a menu is open, a clear layer on every screen catches clicks
    // outside it and closes it; the click doesn't reach what's underneath.
    Variants {
        model: Quickshell.screens

        PanelWindow { // qmllint disable uncreatable-type
            id: catcherWindow

            required property var modelData

            screen: modelData
            visible: root.anyOpen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "launcher-catcher"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            MouseArea {
                id: catcher

                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
                hoverEnabled: true
                onPressed: root.closeOthers(null)
                onPositionChanged: mouse => root.notePointer(catcherWindow.modelData, mouse.x)
            }
        }
    }

    // Every word must match; name matches rank above description, keywords or
    // command
    function search(query, apps, history) {
        const words = query.toLowerCase().split(/\s+/).filter(word => word);
        const matches = [];

        for (const app of apps) {
            const name = app.name.toLowerCase();
            const text = [name, app.genericName, app.keywords.join(" "), app.execString].join(" ").toLowerCase();
            if (!words.every(word => text.includes(word)))
                continue;

            let rank = 2;
            if (words.length === 0 || name.startsWith(words[0]))
                rank = 0;
            else if (words.every(word => name.includes(word)))
                rank = 1;

            matches.push({
                app: app,
                rank: rank,
                uses: history[app.id] ?? 0
            });
        }

        matches.sort((a, b) => a.rank - b.rank || b.uses - a.uses || a.app.name.localeCompare(b.app.name));
        return matches.map(match => match.app);
    }

    function launch(app) {
        const updated = Object.assign({}, history);
        updated[app.id] = (updated[app.id] ?? 0) + 1;
        history = updated;
        historyFile.setText(JSON.stringify(updated));

        if (app.runInTerminal)
            Quickshell.execDetached({
                command: Theme.terminal.concat(app.command),
                workingDirectory: app.workingDirectory
            });
        else
            app.execute();
    }

    SearchMenu {
        id: appMenu

        shadow: true
        results: root.search(query, DesktopEntries.applications.values, root.history)
        label: app => app.name
        icon: app => Quickshell.iconPath(app.icon, "application-x-executable")
        emptyText: Theme.emptyText

        onAccepted: app => root.launch(app)
        onOpenChanged: if (open)
            root.closeOthers(appMenu)
    }

    PowerMenu {
        id: powerMenu
        onOpenChanged: if (open)
            root.closeOthers(powerMenu)
    }

    ClipboardMenu {
        id: clipboardMenu
        onOpenChanged: if (open)
            root.closeOthers(clipboardMenu)
    }

    ScratchpadMenu {
        id: scratchpadMenu
        onOpenChanged: if (open)
            root.closeOthers(scratchpadMenu)
    }

    KeybindMenu {
        id: keybindMenu
        onOpenChanged: if (open)
            root.closeOthers(keybindMenu)
    }

    ControlPanel {
        id: controlPanel
        pointerX: root.pointerX
        pointerScreen: root.pointerScreen
        onOpenChanged: if (open)
            root.closeOthers(controlPanel)
    }

    NotificationCenter {
        id: notificationCenter
        pointerX: root.pointerX
        pointerScreen: root.pointerScreen
        server: notifications
        onOpenChanged: if (open)
            root.closeOthers(notificationCenter)
    }

    DatePanel {
        id: datePanel
        pointerX: root.pointerX
        pointerScreen: root.pointerScreen
        pomodoro: pomodoro
        onOpenChanged: if (open)
            root.closeOthers(datePanel)
    }

    Pomodoro {
        id: pomodoro
    }

    BluetoothAgent {}

    PolkitPrompt {}

    CapsLock {}

    BarVolume {}

    Osd {
        suppressed: controlPanel.open
    }

    Notifications {
        id: notifications
        suppressed: controlPanel.open || notificationCenter.open
    }

    IpcHandler {
        target: "launcher"

        function toggleAppMenu(): void {
            appMenu.open = !appMenu.open;
        }

        function openAppMenu(): void {
            appMenu.open = true;
        }

        function closeAppMenu(): void {
            appMenu.open = false;
        }
    }

    FileView {
        id: historyFile
        path: Quickshell.statePath("history.json")
        blockLoading: true
        printErrors: false

        onLoaded: {
            try {
                root.history = JSON.parse(text());
            } catch (error) {
                root.history = {};
            }
        }
    }
}
