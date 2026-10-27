import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs

// Strip of preview cards for windows in mango's scratchpad (minimized).
// Previews are grabbed with `grim -T` once, when the window is parked: mango
// stops redrawing hidden windows, so the frame stays accurate. Opened by double
// tapping Super or by ~/.local/bin/scratchpad-menu. Enter brings the window out
// onto an empty tag; Delete closes it.
Scope {
    id: root

    property alias open: menu.open
    // { id, appId, title, toplevel, width }
    property var entries: []
    readonly property var workspaces: workspaceState(Compositor.focusedMonitor)
    // Client id -> preview URL
    property var previews: ({})
    // Ids already tried, so failures aren't retried until the window leaves
    property var tried: ({})
    property real lastTap: 0
    readonly property string previewDir: Quickshell.env("XDG_RUNTIME_DIR") + "/scratchpad-previews"

    // Named scratchpads are mango's own toggled windows, not parked ones
    function parse(state) {
        return (state.clients ?? []).filter(client => client.is_minimized && !client.is_namedscratchpad).map(client => ({
                    id: client.id,
                    appId: client.appid ?? "",
                    title: client.title ?? "",
                    toplevel: client.foreign_toplevel_id ?? "",
                    width: client.width
                }));
    }

    function workspaceState(monitor) {
        const result = { used: [], focusedEmpty: false, focused: 0 };
        for (const tag of monitor?.tags ?? []) {
            if (tag.client_count > 0)
                result.used.push(tag.index);
            if (tag.is_active && result.focused === 0) {
                result.focused = tag.index;
                result.focusedEmpty = tag.client_count === 0;
            }
        }
        return result;
    }

    // The shown tag if empty, else the lowest free one (the last when all are
    // used)
    function emptyWorkspace() {
        if (root.workspaces.focusedEmpty)
            return root.workspaces.focused;

        let number = 1;
        while (number < Theme.tagCount && root.workspaces.used.includes(number))
            number++;
        return number;
    }

    // Drop previews of windows that left, then grab the missing ones
    function update(entries) {
        const ids = entries.map(entry => String(entry.id));
        const previews = {};
        const tried = {};
        for (const id of Object.keys(root.tried)) {
            if (!ids.includes(id)) {
                Quickshell.execDetached(["rm", "-f", root.previewDir + "/" + id + ".png"]);
                continue;
            }
            tried[id] = true;
            if (id in root.previews)
                previews[id] = root.previews[id];
        }
        root.previews = previews;
        root.tried = tried;
        // A new list resets the selection; keep it in place
        const selected = menu.view.currentIndex;
        root.entries = entries;
        menu.view.currentIndex = Math.max(0, Math.min(selected, entries.length - 1));

        if (grabber.running)
            return;
        const missing = entries.filter(entry => entry.toplevel && !(String(entry.id) in tried));
        for (const entry of missing)
            tried[String(entry.id)] = true;
        root.capture(missing);
    }

    // About twice a card's width, sharp on HiDPI
    function capture(entries) {
        const args = [];
        for (const entry of entries)
            args.push(String(entry.id), entry.toplevel, String(Math.min(1, menu.cardWidth * 2 / entry.width).toFixed(3)));
        if (args.length === 0)
            return;

        grabber.command = ["sh", "-c", `
            dir=$1; shift
            mkdir -p "$dir"
            while [ $# -gt 0 ]; do
                (grim -T "$2" -s "$3" "$dir/$1.png" && echo "$1") &
                shift 3
            done
            wait`, "sh", root.previewDir].concat(args);
        grabber.running = true;
    }

    // Its card goes when mango's client event comes in
    function close(entry) {
        Quickshell.execDetached(["mmsg", "dispatch", "killclient", `client,${entry.id}`]);
    }

    // focusid un-minimizes it; `tag` follows, `tagsilent` stays here
    function bringOut(entry, workspace, follow) {
        const back = follow ? "" : `; mmsg dispatch view,${root.workspaces.focused},0`;
        Quickshell.execDetached(["sh", "-c", `mmsg dispatch focusid client,$1 && mmsg dispatch ${follow ? "tag" : "tagsilent"},$2,0 client,$1${back}`, "sh", String(entry.id), String(workspace)]);
    }

    function tap() {
        const now = Date.now();
        if (now - root.lastTap <= Theme.doubleTapInterval) {
            root.lastTap = 0;
            root.open = !root.open;
        } else {
            root.lastTap = now;
        }
    }

    // Read from the keycode (xkb 10…19), as Shift turns 1 into "!" etc.
    function workspaceKey(event) {
        const code = event.nativeScanCode;
        return code >= 10 && code <= 18 ? code - 9 : 0;
    }

    // Windows from Compositor.qml; only a change to the parked ones updates
    // the strip
    property string entriesKey: ""

    function refresh() {
        const entries = root.parse({
            clients: Compositor.clients
        });
        const key = JSON.stringify(entries);
        if (key === root.entriesKey)
            return;
        root.entriesKey = key;
        root.update(entries);
    }

    Component.onCompleted: refresh()

    Connections {
        target: Compositor

        function onClientsChanged() {
            root.refresh();
        }
    }

    // Also called over the launcher socket (shell.qml)
    property alias ipc: ipcHandler

    IpcHandler {
        id: ipcHandler
        target: "scratchpad"

        function toggleScratchpadMenu(): void {
            root.open = !root.open;
        }

        function openScratchpadMenu(): void {
            root.open = true;
        }

        function closeScratchpadMenu(): void {
            root.open = false;
        }

        function tap(): void {
            root.tap();
        }
    }

    // Prints each id whose preview is ready
    Process {
        id: grabber

        onExited: root.update(root.entries)

        stdout: SplitParser {
            onRead: id => {
                // New URL so the Image doesn't show a stale grab
                const previews = Object.assign({}, root.previews);
                previews[id] = "file://" + root.previewDir + "/" + id + ".png?" + Date.now();
                root.previews = previews;
            }
        }
    }

    SearchMenu {
        id: menu

        shadow: true
        panelPadding: Theme.cardSpacing
        card: windowCard
        searchable: false
        results: root.entries
        label: entry => entry.title
        icon: entry => Quickshell.iconPath(DesktopEntries.heuristicLookup(entry.appId)?.icon ?? entry.appId, "application-x-executable")
        emptyText: Theme.scratchpadEmptyText

        onAccepted: entry => root.bringOut(entry, root.emptyWorkspace(), true)

        // Delete closes. Alt+1…9 sends to that tag and stays; Alt+Shift+1…9
        // follows
        keyHandler: (event, entry) => {
            if (event.key === Qt.Key_Delete) {
                root.close(entry);
                return true;
            }

            const workspace = root.workspaceKey(event);
            if (!(event.modifiers & Qt.AltModifier) || workspace === 0)
                return false;

            menu.open = false;
            root.bringOut(entry, workspace, event.modifiers & Qt.ShiftModifier);
            return true;
        }
    }

    Component {
        id: windowCard

        Item {
            id: cell

            required property var modelData
            required property int index
            readonly property bool selected: ListView.isCurrentItem
            readonly property bool closing: closeMouse.containsMouse
            readonly property string iconSource: Quickshell.iconPath(DesktopEntries.heuristicLookup(modelData.appId)?.icon ?? modelData.appId, "application-x-executable")

            width: menu.cardWidth
            height: ListView.view.height

            Rectangle {
                id: card

                anchors.fill: parent
                anchors.margins: Theme.cardSpacing
                radius: Theme.cornerRadius
                color: cell.selected ? Theme.hoverColor : Theme.keyColor
                border.width: cell.selected ? 2 : 1
                border.color: cell.closing ? Theme.closeColor : cell.selected ? Theme.selectedColor : "transparent"

                Behavior on border.color {
                    ColorAnimation {
                        duration: Theme.animationDuration
                    }
                }

                ClippingRectangle {
                    id: thumbnail

                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: title.top
                    anchors.topMargin: card.border.width
                    anchors.leftMargin: card.border.width
                    anchors.rightMargin: card.border.width
                    color: "transparent"
                    topLeftRadius: card.radius - card.border.width
                    topRightRadius: card.radius - card.border.width
                    bottomLeftRadius: 0
                    bottomRightRadius: 0

                    // Crops, keeping the window's top
                    Image {
                        id: preview
                        anchors.fill: parent
                        source: root.previews[cell.modelData.id] ?? ""
                        fillMode: Image.PreserveAspectCrop
                        verticalAlignment: Image.AlignTop
                        asynchronous: true
                        cache: false
                        smooth: true
                        mipmap: true
                        opacity: cell.selected ? 1 : 0.75
                    }

                    // Until the preview is ready, or when it can't be grabbed
                    IconImage {
                        anchors.centerIn: parent
                        visible: preview.status !== Image.Ready
                        implicitSize: Theme.iconSize * 2
                        source: cell.iconSource
                        opacity: 0.5
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.closeColor
                        opacity: cell.closing ? 0.18 : 0

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.animationDuration
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: title.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: card.border.width
                    anchors.rightMargin: card.border.width
                    height: 1
                    color: Theme.edgeColor
                }

                Row {
                    id: title

                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Theme.rowPadding
                    anchors.rightMargin: Theme.rowPadding
                    height: Theme.cardTitleHeight
                    spacing: Theme.iconSpacing

                    IconImage {
                        id: icon
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: Theme.iconSize * 0.8
                        source: cell.iconSource
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - icon.width - parent.spacing
                        text: cell.modelData.title
                        textFormat: Text.PlainText
                        color: cell.selected ? Theme.textColor : Theme.keyTextColor
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.keyFontSize
                        font.weight: Theme.fontWeight
                    }
                }
            }

            MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: cell.ListView.view.currentIndex = cell.index
                onClicked: menu.accept(cell.modelData)
            }

            // Close button on a hovered card
            Rectangle {
                id: closeButton

                readonly property bool shown: cardMouse.containsMouse || closeMouse.containsMouse

                // Out as far as the strip's clip allows
                anchors.top: card.top
                anchors.right: card.right
                anchors.margins: -Theme.cardSpacing
                width: Theme.closeButtonSize
                height: Theme.closeButtonSize
                radius: width / 2
                color: cell.closing ? Theme.closeColor : Theme.panelColor
                border.width: 1
                border.color: cell.closing ? Theme.closeColor : Theme.edgeColor
                opacity: shown ? 1 : 0
                visible: opacity > 0
                scale: !shown ? 0.6 : closeMouse.pressed ? 0.85 : 1

                Behavior on opacity {
                    NumberAnimation {
                        duration: Theme.animationDuration
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animationDuration * 1.5
                        easing.type: Easing.OutBack
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animationDuration
                    }
                }

                // Two crossed bars, crisper than a glyph
                Item {
                    anchors.centerIn: parent
                    width: parent.width * 0.42
                    height: width
                    rotation: cell.closing ? 90 : 0

                    Behavior on rotation {
                        NumberAnimation {
                            duration: Theme.animationDuration * 2
                            easing.type: Easing.OutCubic
                        }
                    }

                    Repeater {
                        model: [45, -45]

                        Rectangle {
                            required property int modelData

                            anchors.centerIn: parent
                            width: parent.width * Math.SQRT2
                            height: 2
                            radius: 1
                            rotation: modelData
                            antialiasing: true
                            color: cell.closing ? Theme.panelColor : Theme.textColor
                        }
                    }
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close(cell.modelData)
                }
            }
        }
    }
}
