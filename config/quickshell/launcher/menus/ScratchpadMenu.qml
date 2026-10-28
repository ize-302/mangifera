import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs
import qs.services
import qs.widgets

// Previews of windows in mango's scratchpad (minimized), as a strip of cards on
// the bar or a full-screen overview (ScratchpadOverview.qml), picked by
// Theme.scratchpadStyle. Previews are grabbed with `grim -T` once, when the
// window is parked: mango stops redrawing hidden windows, so the frame stays
// accurate. Opened by double tapping Super or by ~/.local/bin/scratchpad-menu.
// Enter brings the window out onto an empty tag; Delete closes it.
Scope {
    id: root

    property bool open: false
    // Theme.scratchpadStyle picks the full-screen overview over the strip
    readonly property bool overview: Theme.scratchpadStyle === "overview"
    readonly property var overviewWindow: overviewLoader.item
    // Widest a card or overview preview gets; previews are decoded at it
    readonly property int previewWidth: overview ? Math.round(menu.screen.width * Theme.overviewMaxWidth) : menu.cardWidth
    // { id, appId, title, toplevel, width, height }
    property var entries: []
    readonly property var workspaces: workspaceState(Compositor.focusedMonitor)
    // Client id -> preview URL
    property var previews: ({})
    // Client id -> grabs tried, so a failure is retried only a few times until
    // the window leaves
    property var tried: ({})
    property real lastTap: 0
    readonly property string previewDir: Quickshell.env("XDG_RUNTIME_DIR") + "/scratchpad-previews"

    function parse(parked) {
        return parked.map(client => ({
                    id: client.id,
                    appId: client.appid ?? "",
                    title: client.title ?? "",
                    toplevel: client.foreign_toplevel_id ?? "",
                    width: client.width,
                    height: client.height
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
            tried[id] = root.tried[id];
            if (id in root.previews)
                previews[id] = root.previews[id];
        }
        root.previews = previews;
        root.tried = tried;
        // A new list resets the selection; keep it in place
        const view = root.overview ? root.overviewWindow : menu.view;
        const selected = view?.currentIndex ?? 0;
        root.entries = entries;
        if (view)
            view.currentIndex = Math.max(0, Math.min(selected, entries.length - 1));

        if (grabber.running)
            return;
        const missing = entries.filter(entry => entry.toplevel && !(String(entry.id) in previews) && (tried[String(entry.id)] ?? 0) < Theme.previewAttempts);
        for (const entry of missing)
            tried[String(entry.id)] = (tried[String(entry.id)] ?? 0) + 1;
        root.capture(missing);
    }

    // At full size and light compression: grim's scaling took ~500 ms a
    // window against ~140 ms, and the Image decodes it down anyway
    function capture(entries) {
        const args = [];
        for (const entry of entries)
            args.push(String(entry.id), entry.toplevel);
        if (args.length === 0)
            return;

        grabber.command = ["sh", "-c", `
            dir=$1; shift
            mkdir -p "$dir"
            while [ $# -gt 0 ]; do
                (grim -T "$2" -l 1 "$dir/$1.png" && echo "$1") &
                shift 2
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

    function icon(entry) {
        return Quickshell.iconPath(DesktopEntries.heuristicLookup(entry.appId)?.icon ?? entry.appId, "application-x-executable");
    }

    // Delete closes. Alt+1…9 sends to that tag and stays; Alt+Shift+1…9
    // follows
    function handleKey(event, entry) {
        if (event.key === Qt.Key_Delete) {
            root.close(entry);
            return true;
        }

        const workspace = root.workspaceKey(event);
        if (!(event.modifiers & Qt.AltModifier) || workspace === 0)
            return false;

        root.open = false;
        root.bringOut(entry, workspace, event.modifiers & Qt.ShiftModifier);
        return true;
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

    Component.onCompleted: root.update(root.parse(Compositor.parked))

    // Hands open on to the style in use, and takes it back when that closes
    // itself
    onOpenChanged: {
        if (root.overview) {
            if (root.overviewWindow)
                root.overviewWindow.open = root.open;
        } else {
            menu.open = root.open;
        }
    }

    Connections {
        target: Compositor

        function onParkedChanged() {
            root.update(root.parse(Compositor.parked));
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

        onOpenChanged: root.open = open
        shadow: true
        panelPadding: Theme.cardSpacing
        card: windowCard
        searchable: false
        title: Theme.scratchpadTitle
        results: root.entries
        label: entry => entry.title
        icon: root.icon
        emptyText: Theme.scratchpadEmptyText
        keyHandler: root.handleKey

        onAccepted: entry => root.bringOut(entry, root.emptyWorkspace(), true)
    }

    Loader {
        id: overviewLoader

        active: root.overview

        sourceComponent: ScratchpadOverview {
            previewWidth: root.previewWidth
            entries: root.entries
            previews: root.previews
            icon: root.icon
            emptyText: Theme.scratchpadEmptyText
            keyHandler: root.handleKey

            onOpenChanged: root.open = open
            onAccepted: entry => root.bringOut(entry, root.emptyWorkspace(), true)
            onCloseClicked: entry => root.close(entry)
        }
    }

    Component {
        id: windowCard

        Item {
            id: cell

            required property var modelData
            required property int index
            readonly property bool selected: ListView.isCurrentItem
            readonly property bool closing: closeButton.hovered
            readonly property string iconSource: root.icon(modelData)

            width: menu.cardWidth
            height: ListView.view.height

            Rectangle {
                id: card

                anchors.fill: parent
                anchors.margins: Theme.cardSpacing
                radius: Theme.cornerRadius
                color: cell.selected ? Theme.hoverColor : Theme.keyColor
                border.width: cell.selected ? 2 : 1
                border.color: cell.closing ? Theme.scratchpadCloseColor : cell.selected ? Theme.selectedColor : "transparent"

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
                        // Decoded at the card's size, not the window's
                        sourceSize.width: root.previewWidth
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
                        color: Theme.scratchpadCloseColor
                        opacity: cell.closing ? 0.1 : 0

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

            CloseButton {
                id: closeButton
                // Inside the card's border
                anchors.top: card.top
                anchors.right: card.right
                anchors.margins: card.border.width
                outerRadius: card.radius - card.border.width
                shown: cardMouse.containsMouse || hovered
                onClicked: root.close(cell.modelData)
            }
        }
    }
}
