pragma ComponentBehavior: Bound

import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Notification centre: kept notifications grouped by app, newest app first, as
// floating cards above the bar. Toggled by ~/.local/bin/notification-center;
// `--pointer` centres it over the bell.
// Keys: Up/Down (j/k) move, Enter runs the default action, Delete dismisses, c
// clears all, d toggles do not disturb (h for an hour, m until morning), Escape
// closes.
Scope {
    id: root

    property bool open: false
    property int current: 0

    // -1 until shell.qml reports the pointer
    property bool atPointer: false
    property real pointerX: -1
    property var pointerScreen: null
    property bool placeWaited: false
    readonly property bool placed: !atPointer || pointerX >= 0 || placeWaited
    property var server: null
    readonly property var notifications: server ? Array.from(server.notifications) : []

    // app -> true; stacks start collapsed
    property var expanded: ({})

    // An app with several notifications is a stack: collapsed, its newest card
    // ({ kind: "card", stack }); expanded, a header ({ kind: "header" }) over a
    // card for each.
    readonly property var rows: {
        const groups = new Map();
        for (const notification of notifications) {
            const app = notification.appName || "Other";
            groups.set(app, (groups.get(app) ?? []).concat([notification]));
        }
        const rows = [];
        for (const [app, list] of groups) {
            if (list.length > 1 && expanded[app]) {
                rows.push({
                    kind: "header",
                    group: app,
                    count: list.length
                });
                for (const [index, notification] of list.entries())
                    rows.push({
                        kind: "card",
                        group: app,
                        notification: notification,
                        stack: 1,
                        joined: true,
                        last: index === list.length - 1
                    });
            } else {
                rows.push({
                    kind: "card",
                    group: app,
                    notification: list[0],
                    stack: list.length
                });
            }
        }
        return rows;
    }

    function setExpanded(app, on) {
        const expanded = Object.assign({}, root.expanded);
        if (on)
            expanded[app] = true;
        else
            delete expanded[app];
        root.expanded = expanded;
    }

    function dismissGroup(app) {
        for (const notification of notifications.filter(notification => (notification.appName || "Other") === app))
            notification.dismiss();
        root.setExpanded(app, false);
    }

    function activate(row) {
        if (row.kind === "header") {
            root.setExpanded(row.group, false);
        } else if (row.stack > 1) {
            root.setExpanded(row.group, true);
        } else {
            server.activate(row.notification);
            root.open = false;
        }
    }

    // A stack goes whole
    function dismiss(row) {
        if (row.kind === "header" || row.stack > 1)
            root.dismissGroup(row.group);
        else
            row.notification.dismiss();
    }

    function countLabel() {
        const unread = Math.min(server?.unread ?? 0, notifications.length);
        if (unread > 0)
            return unread + " new";
        const count = notifications.length;
        return count === 0 ? "" : count === 1 ? "1 notification" : count + " notifications";
    }

    function toggleDoNotDisturb() {
        server.doNotDisturb = !server.doNotDisturb;
    }

    function reveal() {
        const item = repeater.itemAt(current);
        if (!item)
            return;
        if (item.y < flick.contentY)
            flick.contentY = item.y;
        else if (item.y + item.height > flick.contentY + flick.height)
            flick.contentY = item.y + item.height - flick.height;
    }

    onCurrentChanged: Qt.callLater(root.reveal)
    onRowsChanged: current = Math.max(0, Math.min(current, rows.length - 1))

    onOpenChanged: {
        if (open && server)
            server.markRead();
        if (!open) {
            atPointer = false;
            placeWaited = false;
            expanded = {};
        }
    }

    // Pointer not found: fall back to the right edge
    Timer {
        running: root.open && !root.placed
        interval: 500
        onTriggered: root.placeWaited = true
    }

    IpcHandler {
        target: "notificationCenter"

        function toggleNotificationCenter(): void {
            root.open = !root.open;
        }

        function toggleNotificationCenterAtPointer(): void {
            if (!root.open)
                root.atPointer = true;
            root.open = !root.open;
        }

        function openNotificationCenter(): void {
            root.open = true;
        }

        function closeNotificationCenter(): void {
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

            root.current = 0;
            flick.contentY = 0;
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
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const count = root.rows.length;
                    const row = root.rows[Math.min(root.current, count - 1)];

                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
                        root.open = false;
                    } else if (event.key === Qt.Key_D && root.server) {
                        root.toggleDoNotDisturb();
                    } else if (event.key === Qt.Key_H && root.server) {
                        root.server.setDoNotDisturb("hour");
                    } else if (event.key === Qt.Key_M && root.server) {
                        root.server.setDoNotDisturb("morning");
                    } else if (count === 0) {
                        return;
                    } else if (event.key === Qt.Key_C) {
                        root.server.clear();
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activate(row);
                    } else if (event.key === Qt.Key_Delete || event.key === Qt.Key_X) {
                        root.dismiss(row);
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || event.key === Qt.Key_J || (ctrl && event.key === Qt.Key_N)) {
                        root.current = (root.current + 1) % count;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || event.key === Qt.Key_K || (ctrl && event.key === Qt.Key_P)) {
                        root.current = (root.current + count - 1) % count;
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                // Title card: count, do not disturb and Clear All
                Rectangle {
                    width: parent.width
                    height: titleRows.height + Theme.panelPadding
                    radius: Theme.cornerRadius
                    color: Theme.noteCardColor

                    Column {
                        id: titleRows

                        x: Theme.panelPadding
                        y: Theme.panelPadding / 2
                        width: parent.width - x * 2

                        Item {
                            width: parent.width
                            height: Theme.noteCardButtonHeight + Theme.rowSpacing * 2

                            Text {
                                id: title
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Notifications"
                                color: Theme.textColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.searchFontSize
                                font.weight: Font.DemiBold
                            }

                            Text {
                                anchors.left: title.right
                                anchors.leftMargin: Theme.iconSpacing
                                anchors.baseline: title.baseline
                                text: root.countLabel()
                                color: (root.server?.unread ?? 0) > 0 ? Theme.accentColor : Theme.dimColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.controlSmallFontSize
                                font.weight: Theme.fontWeight
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.keySpacing * 2

                                Rectangle {
                                    readonly property bool on: root.server?.doNotDisturb ?? false

                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.noteCardButtonHeight
                                    height: width
                                    radius: Theme.cornerRadius
                                    color: on ? Theme.toggleOnColor : doNotDisturbMouse.containsMouse ? Theme.hoverColor : Theme.keyColor

                                    Text {
                                        anchors.centerIn: parent
                                        text: Theme.doNotDisturbIcon
                                        color: parent.on ? "white" : Theme.keyTextColor
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.controlFontSize
                                    }

                                    MouseArea {
                                        id: doNotDisturbMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleDoNotDisturb()
                                    }
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: root.rows.length > 0
                                    width: clearLabel.implicitWidth + Theme.keyPadding * 2
                                    height: Theme.noteCardButtonHeight
                                    radius: Theme.cornerRadius
                                    color: clearMouse.containsMouse ? Theme.hoverColor : Theme.keyColor

                                    Text {
                                        id: clearLabel
                                        anchors.centerIn: parent
                                        text: "Clear All"
                                        color: Theme.textColor
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.controlSmallFontSize
                                        font.weight: Font.DemiBold
                                    }

                                    MouseArea {
                                        id: clearMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.server.clear()
                                    }
                                }
                            }
                        }

                        // Do not disturb duration, while on
                        Item {
                            visible: root.server?.doNotDisturb ?? false
                            width: parent.width
                            height: Theme.rowHeight

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (root.server?.doNotDisturbEnd() ?? "") ? "Ends " + root.server.doNotDisturbEnd() : "Do not disturb"
                                color: Theme.dimColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.controlSmallFontSize
                                font.weight: Theme.fontWeight
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.keySpacing

                                Repeater {
                                    model: [
                                        {
                                            duration: "hour",
                                            text: "1 hour"
                                        },
                                        {
                                            duration: "morning",
                                            text: "Until morning"
                                        },
                                        {
                                            duration: "",
                                            text: "Until off"
                                        }
                                    ]

                                    KeyCap {
                                        id: durationCap

                                        required property var modelData

                                        text: modelData.text
                                        fontSize: Theme.controlSmallFontSize
                                        lit: (root.server?.doNotDisturbFor ?? "") === modelData.duration || durationMouse.containsMouse
                                        bold: (root.server?.doNotDisturbFor ?? "") === modelData.duration
                                        weight: Theme.unselectedWeight
                                        litTextColor: bold ? Theme.selectedColor : Theme.textColor

                                        MouseArea {
                                            id: durationMouse
                                            anchors.fill: parent
                                            anchors.margins: -2
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.server.setDoNotDisturb(durationCap.modelData.duration)
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.rows.length === 0
                            height: Theme.rowHeight
                            verticalAlignment: Text.AlignVCenter
                            text: (root.server?.doNotDisturb ?? false) ? Theme.doNotDisturbText : Theme.noNotificationsText
                            color: Theme.dimColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.controlFontSize
                            font.weight: Theme.fontWeight
                        }
                    }
                }

                // Bottom fade, used as the Flickable's mask
                Item {
                    id: fade

                    visible: false
                    layer.enabled: true
                    width: flick.width
                    height: flick.height

                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: "white"
                            }
                            GradientStop {
                                position: Math.max(0, 1 - Theme.notificationFadeHeight / Math.max(1, fade.height))
                                color: "white"
                            }
                            GradientStop {
                                position: 1
                                color: "transparent"
                            }
                        }
                    }
                }

                Flickable {
                    id: flick

                    readonly property bool moreBelow: contentY + height < contentHeight - 1

                    visible: root.rows.length > 0
                    width: parent.width
                    height: Math.min(list.height, window.screen.height * Theme.notificationCenterMaxHeight)
                    contentHeight: list.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    layer.enabled: moreBelow
                    layer.effect: OpacityMask {
                        maskSource: fade
                    }

                    Column {
                        id: list

                        width: flick.width

                        Repeater {
                            id: repeater

                            model: root.rows

                            Item {
                                id: entry

                                required property var modelData
                                required property int index
                                readonly property bool header: modelData.kind === "header"
                                // No gap inside an expanded stack
                                readonly property int gap: index > 0 && !modelData.joined ? Theme.notificationSpacing : 0

                                width: list.width
                                height: gap + (header ? groupHeader.height : notificationCard.implicitHeight)

                                // Expanded stack's header
                                Rectangle {
                                    id: groupHeader

                                    visible: entry.header
                                    y: entry.gap
                                    width: parent.width
                                    height: Theme.noteCardButtonHeight + Theme.rowSpacing * 2 + Theme.panelPadding / 2
                                    topLeftRadius: Theme.cornerRadius
                                    topRightRadius: Theme.cornerRadius
                                    color: Theme.noteCardColor

                                    Text {
                                        x: Theme.panelPadding
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: entry.modelData.group ?? ""
                                        color: root.current === entry.index ? Theme.selectedColor : Theme.unselectedColor
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.controlFontSize
                                        font.weight: Font.DemiBold
                                    }

                                    Row {
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.panelPadding
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Theme.keySpacing * 2

                                        Rectangle {
                                            width: lessLabel.implicitWidth + Theme.keyPadding * 2
                                            height: Theme.noteCardButtonHeight
                                            radius: Theme.cornerRadius
                                            color: lessMouse.containsMouse ? Theme.hoverColor : Theme.keyColor

                                            Text {
                                                id: lessLabel
                                                anchors.centerIn: parent
                                                text: "Show less"
                                                color: Theme.textColor
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.controlSmallFontSize
                                                font.weight: Font.DemiBold
                                            }

                                            MouseArea {
                                                id: lessMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.setExpanded(entry.modelData.group, false)
                                            }
                                        }

                                        Rectangle {
                                            width: Theme.noteCardButtonHeight
                                            height: width
                                            radius: Theme.cornerRadius
                                            color: groupCloseMouse.containsMouse ? Theme.hoverColor : Theme.keyColor

                                            Text {
                                                anchors.centerIn: parent
                                                text: Theme.closeIcon
                                                color: Theme.keyTextColor
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.controlSmallFontSize
                                            }

                                            MouseArea {
                                                id: groupCloseMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.dismissGroup(entry.modelData.group)
                                            }
                                        }
                                    }
                                }

                                NotificationCard {
                                    id: notificationCard

                                    visible: !entry.header
                                    y: entry.gap
                                    width: parent.width
                                    joinedAbove: entry.modelData.joined ?? false
                                    joinedBelow: (entry.modelData.joined ?? false) && !entry.modelData.last
                                    notification: entry.modelData.notification ?? null
                                    server: root.server
                                    stack: entry.modelData.stack ?? 1
                                    selected: root.current === entry.index
                                    onClicked: root.activate(entry.modelData)
                                    onCloseClicked: root.dismiss(entry.modelData)
                                    onHoveredChanged: if (hovered)
                                        root.current = entry.index
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
