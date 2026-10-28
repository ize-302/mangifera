pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs
import qs.widgets

// The session's polkit agent: asks for the admin password in a centred panel.
// Without an agent such requests are refused, so this only works while the
// shell runs.
Scope {
    id: root

    readonly property AuthFlow flow: agent.flow
    // After a password, until polkit asks again or finishes
    readonly property bool busy: flow !== null && !flow.isResponseRequired
    readonly property string error: {
        if (!flow)
            return "";
        if (flow.supplementaryIsError && flow.supplementaryMessage)
            return flow.supplementaryMessage;
        return flow.failed ? "That password didn't work." : "";
    }

    function submit() {
        if (flow && flow.isResponseRequired)
            flow.submit(input.text);
    }

    function cancel() {
        flow?.cancelAuthenticationRequest();
    }

    function nextIdentity() {
        const identities = flow?.identities ?? [];
        if (identities.length < 2)
            return;
        const at = identities.indexOf(flow.selectedIdentity);
        flow.selectedIdentity = identities[(at + 1) % identities.length];
    }

    PolkitAgent {
        id: agent
    }

    // A new prompt (or a retry after a wrong password) starts empty
    Connections {
        target: root.flow

        function onIsResponseRequiredChanged() {
            if (root.flow.isResponseRequired) {
                input.text = "";
                input.forceActiveFocus();
            }
        }
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: window

        visible: agent.isActive && root.flow !== null
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: Theme.pairingWidth
        implicitHeight: glass.height

        // No edges anchored: the layer shell centres it
        WlrLayershell.namespace: "launcher-shadow"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        onVisibleChanged: {
            input.text = "";
            if (!visible)
                return;
            input.forceActiveFocus();
            glass.appear();
        }

        Glass {
            id: glass

            floating: true
            width: parent.width
            height: content.implicitHeight + Theme.keybindPadding * 2

            Column {
                id: content

                x: Theme.keybindPadding
                y: Theme.keybindPadding
                width: parent.width - x * 2
                spacing: Theme.keybindPadding / 2

                Row {
                    spacing: Theme.iconSpacing

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.lockIcon
                        color: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.searchFontSize + 4
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: content.width - Theme.searchFontSize * 2
                        text: "Authentication required"
                        elide: Text.ElideRight
                        color: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.searchFontSize
                        font.weight: Font.Bold
                    }
                }

                Text {
                    width: parent.width
                    text: root.flow?.message ?? ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Theme.keyTextColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                    font.weight: Theme.fontWeight
                }

                // Click cycles identities when there's a choice
                Text {
                    readonly property var identities: root.flow?.identities ?? []

                    visible: identities.length > 0
                    width: parent.width
                    text: "As " + (root.flow?.selectedIdentity?.displayName ?? "") + (identities.length > 1 ? "  ›" : "")
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                    font.weight: Theme.fontWeight

                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.identities.length > 1 && !root.busy
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.nextIdentity()
                    }
                }

                TextInput {
                    id: input

                    width: parent.width
                    echoMode: root.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                    readOnly: root.busy
                    color: Theme.textColor
                    selectionColor: Theme.dividerColor
                    selectedTextColor: Theme.textColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.searchFontSize
                    font.weight: Theme.fontWeight
                    clip: true

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                            root.submit();
                        else if (event.key === Qt.Key_Escape)
                            root.cancel();
                        else
                            return;
                        event.accepted = true;
                    }

                    // polkit's prompt, else ours
                    Text {
                        visible: input.text.length === 0
                        text: (root.flow?.inputPrompt ?? "").replace(/:\s*$/, "") || Theme.passwordPlaceholder
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

                Text {
                    visible: text !== ""
                    width: parent.width
                    text: root.error || (root.flow?.supplementaryMessage ?? "")
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: root.error ? Theme.closeColor : Theme.keyTextColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                    font.weight: Theme.fontWeight
                }

                Row {
                    anchors.right: parent.right
                    topPadding: Theme.rowSpacing
                    spacing: Theme.keySpacing * 2

                    KeyCap {
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
                            onClicked: root.cancel()
                        }
                    }

                    Rectangle {
                        width: Math.max(Theme.pairingButtonWidth, authenticate.implicitWidth + Theme.keyPadding * 2)
                        height: Theme.pairingButtonHeight
                        radius: Theme.cornerRadius
                        color: Theme.toggleOnColor
                        opacity: root.busy ? 0.5 : authenticateMouse.containsMouse ? 0.85 : 1

                        Text {
                            id: authenticate
                            anchors.centerIn: parent
                            text: "Authenticate"
                            opacity: root.busy ? 0 : 1
                            color: "white"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.controlFontSize
                            font.weight: Font.DemiBold
                        }

                        Spinner {
                            anchors.centerIn: parent
                            visible: root.busy
                            width: Theme.controlFontSize
                            height: Theme.controlFontSize
                            color: "white"
                        }

                        MouseArea {
                            id: authenticateMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.submit()
                        }
                    }
                }
            }
        }
    }
}
