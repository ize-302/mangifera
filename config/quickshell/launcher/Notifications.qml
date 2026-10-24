pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// Notification server (replaces dunst). Shows cards above the bar's right end,
// at most maxPopups, and keeps them for NotificationCenter.qml. Writes
// $XDG_RUNTIME_DIR/notifications.json for the bar's bell and signals waybar
// (SIGRTMIN+8).
Scope {
    id: root

    // While the notification centre or control panel is open
    property bool suppressed: false
    // Do not disturb: no cards, except critical ones
    property bool doNotDisturb: false
    // "hour", "morning" or "" (until turned off); end time in ms, 0 for never
    property string doNotDisturbFor: ""
    property real doNotDisturbUntil: 0
    property list<Notification> popups: []

    readonly property list<Notification> notifications: server.trackedNotifications.values.slice().reverse()
    property int unread: 0
    // id -> arrival ms, and a ticking now for "5m ago"
    property var receivedAt: ({})
    property real now: Date.now()

    function setDoNotDisturb(duration) {
        const end = new Date();
        if (duration === "hour") {
            end.setTime(end.getTime() + 3600000);
        } else if (duration === "morning") {
            if (end.getHours() >= Theme.doNotDisturbMorning)
                end.setDate(end.getDate() + 1);
            end.setHours(Theme.doNotDisturbMorning, 0, 0, 0);
        }
        doNotDisturb = true;
        doNotDisturbFor = duration;
        doNotDisturbUntil = duration ? end.getTime() : 0;
    }

    // "17:20", "08:00", or "" when it doesn't end
    function doNotDisturbEnd() {
        if (!doNotDisturb || doNotDisturbUntil === 0)
            return "";
        return Qt.formatTime(new Date(doNotDisturbUntil), "HH:mm");
    }

    function markRead() {
        unread = 0;
    }

    function clear() {
        popups = [];
        for (const notification of notifications.slice())
            notification.dismiss();
    }

    // "now", "5m", "2h", "3d"
    function age(notification) {
        const seconds = (now - (receivedAt[notification.id] ?? now)) / 1000;
        if (seconds < 60)
            return "now";
        if (seconds < 3600)
            return Math.floor(seconds / 60) + "m";
        if (seconds < 86400)
            return Math.floor(seconds / 3600) + "h";
        return Math.floor(seconds / 86400) + "d";
    }

    function isCritical(notification) {
        return notification.urgency === NotificationUrgency.Critical;
    }

    function received(notification) {
        notification.tracked = true;
        now = Date.now();
        const receivedAt = Object.assign({}, root.receivedAt);
        receivedAt[notification.id] = now;
        root.receivedAt = receivedAt;
        if (!notification.transient)
            unread++;
        root.playSound(notification);

        const kept = server.trackedNotifications.values;
        for (let i = 0; i < kept.length - Theme.maxNotifications; i++)
            kept[i].expire();

        if (doNotDisturb && !root.isCritical(notification)) {
            if (notification.transient)
                notification.expire();
            return;
        }
        popups = [notification].concat(popups.filter(popup => popup !== notification)).slice(0, Theme.maxPopups);
    }

    // App's sound-file, else message.oga; none on suppress-sound or during DND
    // (unless critical)
    function playSound(notification) {
        const hints = notification.hints ?? {};
        if (hints["suppress-sound"] || (doNotDisturb && !root.isCritical(notification)))
            return;
        const file = (hints["sound-file"] ?? "").replace(/^file:\/\//, "");
        Quickshell.execDetached(["paplay", file || Theme.notificationSound]);
    }

    // Kept for the centre, unless it's transient
    function hide(notification) {
        popups = popups.filter(popup => popup !== notification);
        if (notification.transient)
            notification.expire();
    }

    function activate(notification) {
        root.openApp(notification);
        const action = notification.actions.find(action => action.identifier === "default");
        if (action)
            action.invoke();
        else
            root.hide(notification);
    }

    // Some apps (XWayland) don't take focus themselves when their action runs,
    // so focus the app's window, or start it. Matched by desktop entry, window
    // class and name against mango's app ids.
    function openApp(notification) {
        const entry = DesktopEntries.byId(notification.desktopEntry) ?? DesktopEntries.heuristicLookup(notification.appName);
        const names = [notification.desktopEntry, entry?.id, entry?.startupClass, notification.appName].filter(name => /^[\w.-]+$/.test(name ?? ""));
        if (names.length === 0)
            return;
        focusApp.entry = entry;
        // Most recent window; fails when there's none
        focusApp.command = ["sh", "-c", `id=$(mmsg get all-clients | jq -r --argjson names "$1" '[.clients[] | select(.appid | ascii_downcase | IN($names[]))] | max_by(.id) | .id // empty') && [ -n "$id" ] && mmsg dispatch focusid "client,$id"`, "sh", JSON.stringify([...new Set(names.map(name => name.toLowerCase()))])];
        focusApp.running = true;
    }

    // ms, 0 for until closed. Apps send seconds or ms depending on spec version
    function timeout(notification) {
        const timeout = notification.expireTimeout;
        if (timeout > 0)
            return timeout < 100 ? timeout * 1000 : timeout;
        return root.isCritical(notification) ? 0 : Theme.notificationTimeout;
    }

    // Best first: the sent image, its icon, the app's icon, a fallback
    function icons(notification) {
        const icons = [];
        // An icon name passed as the image (notify-send -i) is only kept if the
        // theme has it
        const image = notification.image ?? "";
        if (image.startsWith("image://icon/"))
            icons.push(Quickshell.iconPath(image.slice("image://icon/".length), true));
        else if (image)
            icons.push(image);
        const name = notification.appIcon ?? "";
        if (name.startsWith("/") || name.startsWith("file:"))
            icons.push(name);
        else if (name)
            icons.push(Quickshell.iconPath(name, true));
        const entry = DesktopEntries.byId(notification.desktopEntry) ?? DesktopEntries.heuristicLookup(notification.appName);
        if (entry?.icon)
            icons.push(Quickshell.iconPath(entry.icon, true));
        icons.push(Quickshell.iconPath("dialog-information"));
        return icons.filter(icon => icon);
    }

    onSuppressedChanged: if (suppressed)
        popups = []

    // Cards already up go too, except critical ones
    onDoNotDisturbChanged: {
        if (doNotDisturb) {
            popups = popups.filter(popup => root.isCritical(popup));
        } else {
            doNotDisturbFor = "";
            doNotDisturbUntil = 0;
        }
        root.writeStatus();
    }
    onUnreadChanged: root.writeStatus()
    Component.onCompleted: root.writeStatus()

    // { text, class }; class is "unread" or "dnd" for style.css
    function writeStatus() {
        const dot = unread > 0 ? `<span color='${Theme.accentColor}' size='small' rise='6pt'>●</span>` : "";
        status.setText(JSON.stringify({
            text: (doNotDisturb ? Theme.doNotDisturbIcon : unread > 0 ? Theme.bellUnreadIcon : Theme.bellIcon) + dot,
            class: doNotDisturb ? "dnd" : unread > 0 ? "unread" : ""
        }) + "\n");
    }

    // Also called over the launcher socket (shell.qml)
    property alias ipc: ipcHandler

    IpcHandler {
        id: ipcHandler
        target: "notifications"

        function toggleDoNotDisturb(): void {
            root.doNotDisturb = !root.doNotDisturb;
        }

        function doNotDisturbFor(duration: string): void {
            root.setDoNotDisturb(duration);
        }

        function clear(): void {
            root.clear();
        }
    }

    FileView {
        id: status

        path: Quickshell.env("XDG_RUNTIME_DIR") + "/notifications.json"
        printErrors: false
        onSaved: Quickshell.execDetached(["pkill", "-RTMIN+8", "-x", "waybar"])
    }

    Process {
        id: focusApp

        property var entry: null

        onExited: code => {
            if (code !== 0)
                entry?.execute();
        }
    }

    Timer {
        running: root.notifications.length > 0
        repeat: true
        interval: 30000
        onTriggered: root.now = Date.now()
    }

    // Checks the clock instead of a long timer, which suspend would stretch
    Timer {
        running: root.doNotDisturbUntil > 0
        repeat: true
        interval: 15000
        onTriggered: if (Date.now() >= root.doNotDisturbUntil)
            root.doNotDisturb = false
    }

    NotificationServer {
        id: server

        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        actionsSupported: true
        imageSupported: true

        onNotification: notification => root.received(notification)
    }

    PanelWindow { // qmllint disable uncreatable-type
        visible: root.popups.length > 0 && !root.suppressed
        screen: Compositor.focusedScreen()
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: Theme.notificationWidth
        implicitHeight: cards.implicitHeight
        // Clicks around the cards go through
        mask: Region {
            item: cards
        }

        WlrLayershell.namespace: "launcher-shadow"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
            bottom: true
            right: true
        }
        margins.bottom: Theme.floatingGap
        margins.right: Theme.floatingGap

        Column {
            id: cards

            width: parent.width
            spacing: Theme.notificationSpacing

            // Oldest at the top, so the newest sits by the bar
            Repeater {
                model: root.popups.slice().reverse()

                Glass {
                    id: card

                    required property Notification modelData
                    required property int index
                    readonly property bool critical: root.isCritical(modelData)
                    readonly property list<NotificationAction> actions: (modelData?.actions ?? []).filter(action => action.identifier !== "default")

                    floating: true
                    width: cards.width
                    height: content.implicitHeight + Theme.panelPadding * 2
                    edgeColor: critical ? Theme.closeColor : "transparent"

                    Component.onCompleted: appear()

                    Connections {
                        target: card.modelData

                        function onClosed() {
                            root.popups = root.popups.filter(popup => popup !== card.modelData);
                        }
                    }

                    Timer {
                        interval: root.timeout(card.modelData)
                        running: interval > 0 && !hover.hovered
                        onTriggered: root.hide(card.modelData)
                    }

                    HoverHandler {
                        id: hover
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: root.activate(card.modelData)
                    }

                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: card.modelData.dismiss()
                    }

                    Row {
                        id: content

                        x: Theme.panelPadding
                        y: Theme.panelPadding
                        width: parent.width - x * 2
                        spacing: Theme.iconSpacing

                        IconImage {
                            property int tried: 0
                            readonly property list<string> candidates: root.icons(card.modelData)

                            implicitSize: Theme.notificationIconSize
                            source: candidates[tried] ?? ""
                            onStatusChanged: if (status === Image.Error && tried < candidates.length - 1)
                                tried++
                        }

                        Column {
                            width: parent.width - Theme.notificationIconSize - parent.spacing
                            spacing: Theme.rowSpacing

                            Item {
                                width: parent.width
                                height: Math.max(app.implicitHeight, close.implicitHeight)

                                Text {
                                    id: app
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - close.width - Theme.iconSpacing
                                    text: (card.modelData.appName || "Notification").toUpperCase()
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    color: card.critical ? Theme.closeColor : Theme.dimColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.sectionFontSize
                                    font.weight: Theme.fontWeight
                                    font.letterSpacing: 1
                                }

                                Text {
                                    id: close
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: hover.hovered ? 1 : 0
                                    text: Theme.closeIcon
                                    color: closeMouse.containsMouse ? Theme.textColor : Theme.keyTextColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.controlFontSize

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: Theme.animationDuration
                                        }
                                    }

                                    MouseArea {
                                        id: closeMouse
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: card.modelData.dismiss()
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: card.modelData.summary
                                textFormat: Text.PlainText
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                color: Theme.textColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.controlFontSize
                                font.weight: Theme.fontWeight
                            }

                            // Apps may send simple markup
                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: card.modelData.body
                                textFormat: Text.StyledText
                                wrapMode: Text.Wrap
                                maximumLineCount: Theme.notificationBodyLines
                                elide: Text.ElideRight
                                color: Theme.keyTextColor
                                linkColor: Theme.textColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.controlSmallFontSize + 1
                                font.weight: Theme.fontWeight
                            }

                            Flow {
                                width: parent.width
                                visible: card.actions.length > 0
                                topPadding: Theme.rowSpacing
                                spacing: Theme.keySpacing

                                Repeater {
                                    model: card.actions

                                    KeyCap {
                                        id: actionCap

                                        required property NotificationAction modelData

                                        text: modelData.text
                                        fontSize: Theme.controlSmallFontSize
                                        lit: actionMouse.containsMouse

                                        MouseArea {
                                            id: actionMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: actionCap.modelData.invoke()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
