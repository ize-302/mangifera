pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import qs
import qs.widgets

// One control panel row (an entry of ControlPanel's `rows`), with its section's
// header over the first. Clicks and keys go to the panel.
Column {
    id: entry

    required property var panel
    required property var modelData
    required property int index

    readonly property string kind: modelData.kind
    readonly property PwNode node: modelData.node ?? null
    // Bluetooth or wired device
    readonly property var device: modelData.device ?? null
    readonly property WifiNetwork network: modelData.network ?? null
    readonly property bool slider: panel.isSlider(modelData)
    readonly property bool toggle: kind === "bluetooth" || kind === "wifi" || kind === "autoconnect" || kind === "btTrust"
    readonly property bool input: kind === "joinName" || kind === "joinPassword"
    readonly property bool passive: kind === "info" || kind === "joinStatus"
    // Shows a spinner
    readonly property bool busy: {
        if (kind === "network")
            return network.state === ConnectionState.Connecting || network.state === ConnectionState.Disconnecting;
        if (kind === "bluetoothDevice")
            return device.pairing || device.state === BluetoothDeviceState.Connecting || device.state === BluetoothDeviceState.Disconnecting;
        if (kind === "bluetooth")
            return panel.adapter.state === BluetoothAdapterState.Enabling || panel.adapter.state === BluetoothAdapterState.Disabling;
        if (kind === "joinStatus")
            return panel.joinBusy;
        return false;
    }
    readonly property bool main: !modelData.list
    readonly property bool muted: node?.audio?.muted ?? false
    readonly property real level: node?.audio?.volume ?? 0
    // No highlight: the text, knob or switch brightens instead
    readonly property bool active: panel.current === index

    readonly property string glyph: {
        if (kind === "volume")
            return node.type === PwNodeType.AudioSink ? Theme.volumeIcon(level, muted) : muted ? Theme.micMutedIcon : Theme.micIcon;
        if (kind === "bluetooth")
            return !panel.bluetoothOn ? Theme.bluetoothOffIcon : panel.bluetoothDevices.some(device => device.connected) ? Theme.bluetoothConnectedIcon : Theme.bluetoothIcon;
        if (kind === "wifi")
            return panel.wifiGlyph();
        return "";
    }
    // Dim when off or muted; red past 100%
    readonly property color glyphColor: {
        if (toggle)
            return on ? Theme.controlIconColor : Theme.controlIconOffColor;
        if (muted)
            return Theme.controlIconOffColor;
        return level > 1.005 ? Theme.closeColor : Theme.controlIconColor;
    }
    readonly property bool on: {
        if (kind === "wifi")
            return Networking.wifiEnabled;
        if (kind === "bluetooth")
            return panel.bluetoothOn;
        if (kind === "autoconnect")
            return panel.details.autoconnect === true;
        if (kind === "btTrust")
            return device.trusted;
        return false;
    }
    readonly property string label: {
        if (kind === "device")
            return panel.deviceName(node);
        if (kind === "bluetooth") {
            const state = panel.adapter.state;
            if (state === BluetoothAdapterState.Enabling || state === BluetoothAdapterState.Disabling)
                return "Bluetooth";
            if (state === BluetoothAdapterState.Blocked)
                return "Off (blocked)";
            // On its page, the switch just says what it is
            if (modelData.list)
                return "Bluetooth";
            return on ? panel.summary("Bluetooth") || "No devices" : "Off";
        }
        if (kind === "bluetoothDevice")
            return device.name || device.address;
        if (kind === "wifi") {
            if (!Networking.wifiHardwareEnabled)
                return "Off (hardware switch)";
            // On its page, the switch just says what it is
            if (modelData.list)
                return "Wi-Fi";
            return on ? panel.summary("Network") || "Not connected" : "Off";
        }
        if (kind === "network")
            return network.name;
        if (kind === "wired")
            return "Ethernet";
        if (kind === "info")
            return modelData.label;
        if (kind === "connect")
            return network.connected ? "Disconnect" : "Connect";
        if (kind === "autoconnect")
            return "Connect automatically";
        if (kind === "forget")
            return "Forget this network";
        if (kind === "btConnect")
            return device.pairing ? "Cancel pairing" : device.connected ? "Disconnect" : device.paired ? "Connect" : "Pair";
        if (kind === "btTrust")
            return "Connect automatically";
        if (kind === "btForget")
            return "Forget this device";
        if (kind === "profile")
            return modelData.label;
        if (kind === "join")
            return "Join other network…";
        if (kind === "joinStatus")
            return panel.joinBusy ? panel.joinName : panel.joinError;
        return "";
    }
    readonly property string detail: {
        if (kind === "network") {
            if (entry.busy)
                return "";
            const failure = panel.failures[network.name];
            // NoSecrets: no password to try, not a wrong one
            if (failure !== undefined && !network.connected)
                return failure === ConnectionFailReason.NoSecrets ? "needs password" : failure === ConnectionFailReason.WifiAuthTimeout ? "wrong password" : "failed";
            if (network.connected)
                return "connected";
            return network.known ? "saved" : "";
        }
        if (kind === "wired")
            return device.linkSpeed ? device.linkSpeed + " Mb/s" : "";
        if (kind === "info")
            return modelData.value;
        if (kind === "profile")
            return modelData.codec;
        if (kind !== "bluetoothDevice")
            return "";
        if (entry.busy)
            return "";
        if (!device.paired)
            return "new";
        return device.connected && device.batteryAvailable ? Math.round(device.battery * 100) + "%" : "";
    }
    readonly property bool checked: {
        if (kind === "device")
            return panel.isDefault(node);
        if (kind === "bluetoothDevice" || kind === "wired")
            return device.connected;
        if (kind === "network")
            return network.connected;
        if (kind === "profile")
            return panel.audio.active === modelData.name;
        return false;
    }
    readonly property bool bright: checked || active || (main && kind !== "bluetooth" && kind !== "wifi") || on

    readonly property bool first: index === 0 || panel.rows[index - 1].section !== modelData.section

    width: parent ? parent.width : 0
    spacing: Theme.rowSpacing
    bottomPadding: Theme.rowSpacing

    // Divider between sections on the main view
    Item {
        width: parent.width
        height: Theme.sectionGap
        visible: entry.first && entry.index > 0 && panel.page === ""

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: Theme.dividerColor
        }
    }

    SectionHeader {
        width: parent.width
        visible: entry.first
        text: entry.modelData.section
        line: false
        opensPage: panel.page === "" && panel.hasPage(entry.modelData.section)
        back: panel.page !== ""
        titleSize: Theme.controlFontSize
        inset: back ? 0 : Theme.rowPadding
        // Sliders have no label, so the header names the device
        summary: !back && ["Output", "Input", "Now playing"].includes(entry.modelData.section) ? panel.summary(entry.modelData.section) : ""
        // Opened from the bar: closes instead of going back
        arrow: panel.page !== panel.entryPage
        action: {
            if (back && entry.modelData.section === "Bluetooth" && panel.bluetoothOn)
                return "Search";
            return "";
        }
        actionActive: entry.modelData.section === "Bluetooth" && (panel.adapter?.discovering ?? false)
        onClicked: back ? panel.closePage() : panel.openPage(entry.modelData.section)
        onActionClicked: panel.toggleSearch()
    }

    Item {
        width: parent.width
        height: entry.kind === "media" ? mediaView.implicitHeight + Theme.rowSpacing * 2 : Theme.rowHeight

        // Hover tint; on a page it reaches into the panel's padding
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: panel.page !== "" ? -Theme.rowPadding : 0
            anchors.rightMargin: panel.page !== "" ? -Theme.rowPadding : 0
            visible: entry.active && !entry.passive
            radius: Theme.cornerRadius
            color: Theme.currentRowColor
        }

        MouseArea {
            id: rowMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: entry.slider || entry.passive || entry.kind === "media" ? Qt.ArrowCursor : entry.input ? Qt.IBeamCursor : Qt.PointingHandCursor
            onPositionChanged: panel.current = entry.index
            onClicked: {
                if (entry.input)
                    panel.focusRow(entry.index);
                else if (!entry.slider && !entry.passive && entry.kind !== "media")
                    panel.activate(entry.modelData);
            }
        }

        Loader {
            id: mediaView

            x: Theme.rowPadding
            y: Theme.rowSpacing
            width: parent.width - x * 2
            active: entry.kind === "media"

            sourceComponent: MediaRow {
                player: entry.modelData.player
                active: entry.active
            }
        }

        Row {
            id: content

            visible: entry.kind !== "media"
            anchors.verticalCenter: parent.verticalCenter
            x: panel.page !== "" ? 0 : Theme.rowPadding
            width: parent.width - x * 2
            spacing: Theme.iconSpacing

            // Volume glyph mutes on click
            Item {
                id: icon

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.glyph !== ""
                width: Theme.iconSize
                height: Theme.iconSize

                Text {
                    anchors.centerIn: parent
                    text: entry.glyph
                    color: entry.glyphColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: entry.kind === "volume"
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.toggleMute(entry.modelData)
                    }
                }
            }

            Text {
                id: label

                anchors.verticalCenter: parent.verticalCenter
                visible: !entry.slider && !entry.input
                width: parent.width - (end.visible ? end.width + parent.spacing : 0) - (icon.visible ? icon.width + parent.spacing : 0) - (detail.visible ? detail.width + parent.spacing : 0) - (busySpinner.visible ? busySpinner.width + parent.spacing : 0) - (signal.visible ? signal.width + parent.spacing : 0) - (more.visible ? more.width + parent.spacing : 0)
                text: entry.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: {
                    if (entry.kind === "forget" || entry.kind === "btForget" || (entry.kind === "joinStatus" && entry.modelData.error))
                        return Theme.closeColor;
                    if (entry.passive)
                        return Theme.dimColor;
                    return entry.checked ? Theme.selectedColor : entry.bright ? Theme.textColor : Theme.keyTextColor;
                }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.controlFontSize
                font.weight: entry.checked ? Theme.selectedWeight : Theme.unselectedWeight

                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animationDuration
                    }
                }
            }

            // Enter/Tab/Down on the name goes to the password, Up back; Enter
            // on the password joins
            TextInput {
                id: password

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.input
                width: parent.width
                echoMode: entry.kind === "joinName" ? TextInput.Normal : TextInput.Password
                color: Theme.textColor
                selectionColor: Theme.dividerColor
                selectedTextColor: Theme.textColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.controlFontSize
                font.weight: Theme.fontWeight
                clip: true

                Component.onCompleted: if (entry.kind === "joinName")
                    forceActiveFocus()

                onTextChanged: {
                    if (entry.kind === "joinName")
                        panel.joinName = text;
                    else if (entry.kind === "joinPassword")
                        panel.joinPassword = text;
                }

                Keys.onPressed: event => {
                    const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
                    if (event.key === Qt.Key_Escape) {
                        panel.closePage();
                    } else if (entry.kind === "joinName" && (enter || event.key === Qt.Key_Tab || event.key === Qt.Key_Down)) {
                        panel.focusRow(entry.index + 1);
                    } else if (entry.kind === "joinPassword" && enter) {
                        panel.join();
                    } else if (entry.kind === "joinPassword" && (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up)) {
                        panel.focusRow(entry.index - 1);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Text {
                    visible: password.text.length === 0
                    text: entry.kind === "joinName" ? "Network name" : "Password (none if it's open)"
                    color: Theme.dimColor
                    font: password.font
                }

                Rectangle {
                    anchors.top: parent.bottom
                    anchors.topMargin: 3
                    width: parent.width
                    height: 1
                    color: password.activeFocus ? Theme.keyTextColor : Theme.dividerColor
                }
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                visible: entry.slider
                width: parent.width - percent.width - parent.spacing - (icon.visible ? icon.width + parent.spacing : 0) - (label.visible ? label.width + parent.spacing : 0)
                active: entry.active
                value: entry.level
                color: Theme.sliderColor(entry.level, entry.muted)
                onMoved: value => {
                    panel.current = entry.index;
                    panel.setVolume(entry.modelData, value);
                }
            }

            // As wide as "100%" so it doesn't jump
            KeyCap {
                id: percent

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.slider
                minWidth: Math.ceil(percentWidth.advanceWidth) + Theme.keyPadding * 2
                text: entry.muted ? "mute" : Math.round(entry.level * 100) + "%"
                fontSize: Theme.controlSmallFontSize
                lit: entry.active
            }

            Text {
                id: detail

                anchors.verticalCenter: parent.verticalCenter
                visible: text !== ""
                text: entry.detail
                color: entry.kind === "info" ? Theme.textColor : entry.checked ? Theme.selectedColor : Theme.dimColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.controlSmallFontSize
                font.weight: Theme.fontWeight
            }

            Spinner {
                id: busySpinner

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.busy
                width: Theme.controlSmallFontSize
                height: Theme.controlSmallFontSize
                color: Theme.dimColor
            }

            Row {
                id: signal

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.kind === "network"
                spacing: 3

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: signal.visible && panel.isSecured(entry.network)
                    text: Theme.lockIcon
                    color: entry.checked ? Theme.selectedColor : Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlSmallFontSize - 1
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: signal.visible ? panel.networkIcon(entry.network) : ""
                    color: entry.checked ? Theme.selectedColor : Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                }
            }

            Text {
                id: more

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.kind === "network" || entry.kind === "bluetoothDevice"
                text: Theme.pageIcon
                color: moreMouse.containsMouse || entry.active ? Theme.textColor : Theme.dimColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.sectionFontSize

                MouseArea {
                    id: moreMouse

                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: entry.kind === "network" ? panel.openDetails(entry.network) : panel.openDevice(entry.device)
                }
            }

            Toggle {
                id: end

                anchors.verticalCenter: parent.verticalCenter
                visible: entry.toggle
                checked: entry.on
            }
        }
    }

    function focusField() {
        password.forceActiveFocus();
    }

    // Widest volume, so the sliders line up
    TextMetrics {
        id: percentWidth
        text: "100%"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.controlSmallFontSize
        font.weight: Theme.fontWeight
    }
}
