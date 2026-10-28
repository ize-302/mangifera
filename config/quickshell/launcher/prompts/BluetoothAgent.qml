pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.widgets

// Bluetooth pairing prompts. Runs ~/.local/bin/bluetooth-agent (the default
// BlueZ agent) and shows its requests. Without an agent, phones and keyboards
// can't pair.
Scope {
    id: root

    // Pending, oldest first: { id, type, device, passkey, entered }
    property var requests: []
    readonly property var request: requests.length > 0 ? requests[0] : null
    readonly property string type: request?.type ?? ""
    // Shows a code to type on the device: nothing to answer
    readonly property bool display: type === "display-pin" || type === "display-passkey"
    readonly property bool typed: type === "pin" || type === "passkey"

    function received(line) {
        let message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            return;
        }
        if (message.type === "cancel") {
            requests = [];
            return;
        }
        // A display request replaces the previous one (a passkey is resent per
        // key pressed)
        const others = requests.filter(request => !(message.id === 0 && request.id === 0));
        requests = message.id === 0 ? [message].concat(others) : others.concat([message]);
    }

    function answer(yes) {
        const request = root.request;
        if (!request)
            return;
        if (request.id > 0) {
            const value = root.typed ? " " + input.text.replace(/\s/g, "") : "";
            agent.write(request.id + (yes ? " yes" : " no") + (yes ? value : "") + "\n");
        }
        input.text = "";
        requests = requests.slice(1);
    }

    function focusPrompt() {
        if (typed)
            input.forceActiveFocus();
        else
            content.forceActiveFocus();
    }

    onRequestChanged: if (request)
        Qt.callLater(root.focusPrompt)

    function title() {
        if (type === "service")
            return "Allow " + request.device + " to connect?";
        return "Pair with " + (request?.device ?? "");
    }

    function message() {
        const device = request?.device ?? "";
        if (type === "confirm")
            return "Check that " + device + " shows this code.";
        if (type === "authorize")
            return device + " wants to pair with this computer.";
        if (type === "pin")
            return "Type the PIN shown on " + device + ". If it doesn't show one, try 0000.";
        if (type === "passkey")
            return "Type the 6-digit code shown on " + device + ".";
        if (display)
            return "Type this code on " + device + ", then press Enter there.";
        if (type === "service")
            return device + " isn't trusted yet.";
        return "";
    }

    function acceptLabel() {
        if (display)
            return "Done";
        if (type === "service")
            return "Allow";
        return "Pair";
    }

    Process {
        id: agent

        command: [Quickshell.env("HOME") + "/.local/bin/bluetooth-agent"]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => root.received(line)
        }

        // The agent re-registers itself on bluez restarts; this is the agent
        // exiting. Restart, throttled
        onExited: {
            root.requests = [];
            restart.start();
        }
    }

    Timer {
        id: restart
        interval: 5000
        onTriggered: agent.running = true
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: window

        visible: root.request !== null
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: Theme.pairingWidth
        implicitHeight: panel.height

        // No edges anchored: the layer shell centres it
        WlrLayershell.namespace: "launcher-shadow"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: {
            if (!visible)
                return;
            root.focusPrompt();
            panel.appear();
        }

        Glass {
            id: panel

            floating: true
            width: parent.width
            height: content.implicitHeight + Theme.keybindPadding * 2

            Column {
                id: content

                x: Theme.keybindPadding
                y: Theme.keybindPadding
                width: parent.width - x * 2
                spacing: Theme.keybindPadding / 2

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        root.answer(true);
                    else if (event.key === Qt.Key_Escape)
                        root.answer(false);
                    else
                        return;
                    event.accepted = true;
                }

                Row {
                    spacing: Theme.iconSpacing

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.bluetoothIcon
                        color: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.searchFontSize + 4
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: content.width - Theme.searchFontSize * 2
                        text: root.title()
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.searchFontSize
                        font.weight: Font.Bold
                    }
                }

                Text {
                    width: parent.width
                    text: root.message()
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Theme.keyTextColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                    font.weight: Theme.fontWeight
                }

                // One cap per digit; typed passkey digits are lit
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: (root.request?.passkey ?? "") !== ""
                    spacing: Theme.keySpacing * 2

                    Repeater {
                        model: (root.request?.passkey ?? "").split("")

                        KeyCap {
                            required property string modelData
                            required property int index

                            text: modelData
                            fontSize: Theme.pairingCodeSize
                            minWidth: Theme.pairingCodeSize * 1.6
                            height: Theme.pairingCodeSize * 2
                            lit: root.type === "display-passkey" && index < (root.request?.entered ?? 0)
                            bold: lit
                        }
                    }
                }

                TextInput {
                    id: input

                    visible: root.typed
                    width: parent.width
                    focus: root.typed
                    color: Theme.textColor
                    selectionColor: Theme.dividerColor
                    selectedTextColor: Theme.textColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.searchFontSize
                    font.weight: Theme.fontWeight
                    font.letterSpacing: 2
                    maximumLength: 16
                    validator: RegularExpressionValidator {
                        regularExpression: root.type === "passkey" ? /[0-9]{0,6}/ : /\S{0,16}/
                    }
                    clip: true

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (input.text !== "")
                                root.answer(true);
                        }
                        else if (event.key === Qt.Key_Escape)
                            root.answer(false);
                        else
                            return;
                        event.accepted = true;
                    }

                    Text {
                        visible: input.text.length === 0
                        text: root.type === "passkey" ? "000000" : "PIN"
                        color: Theme.dimColor
                        font: input.font
                    }

                    Rectangle {
                        anchors.top: parent.bottom
                        anchors.topMargin: 3
                        width: parent.width
                        height: 1
                        color: input.activeFocus ? Theme.keyTextColor : Theme.dividerColor
                    }
                }

                Row {
                    anchors.right: parent.right
                    topPadding: Theme.rowSpacing
                    spacing: Theme.keySpacing * 2

                    KeyCap {
                        visible: !root.display
                        text: "Cancel"
                        fontSize: Theme.controlFontSize
                        height: Theme.pairingButtonHeight
                        minWidth: Theme.pairingButtonWidth
                        lit: cancelMouse.containsMouse

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.answer(false)
                        }
                    }

                    Rectangle {
                        width: Math.max(Theme.pairingButtonWidth, accept.implicitWidth + Theme.keyPadding * 2)
                        height: Theme.pairingButtonHeight
                        radius: Theme.cornerRadius
                        color: Theme.toggleOnColor
                        opacity: acceptMouse.containsMouse ? 0.85 : 1

                        Text {
                            id: accept
                            anchors.centerIn: parent
                            text: root.acceptLabel()
                            color: "white"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.controlFontSize
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: acceptMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!root.typed || input.text !== "")
                                root.answer(true)
                        }
                    }
                }
            }
        }
    }
}
