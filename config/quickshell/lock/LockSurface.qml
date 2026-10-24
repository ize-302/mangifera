import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs

// One monitor's lock screen. Typing or a click shows the password field on the
// focused monitor; it hides after Theme.promptTimeout seconds idle.
Rectangle {
    id: root

    required property LockContext context

    readonly property bool active: Window.active

    color: Theme.background

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    // The full wallpaper, if ~/.local/bin/wallpaper hasn't made the small copy
    property bool fullWallpaper: false

    FileView {
        id: wallpaperState
        path: Theme.wallpaperState
    }

    // The small copy loads before the first frame, so the screen never shows
    // without it
    Image {
        id: wallpaper
        anchors.fill: parent
        visible: false
        source: !root.fullWallpaper ? "file://" + Theme.wallpaperSmall : wallpaperState.loaded ? "file://" + wallpaperState.text().trim() : ""
        sourceSize: Qt.size(width * Theme.wallpaperScale, height * Theme.wallpaperScale)
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: root.fullWallpaper

        onStatusChanged: {
            // Deferred: changing the source in its own status handler is a
            // binding loop
            if (status === Image.Error && !root.fullWallpaper)
                Qt.callLater(() => root.fullWallpaper = true);
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        visible: wallpaper.status === Image.Ready
        autoPaddingEnabled: false
        blurEnabled: true
        blur: Theme.wallpaperBlur
        blurMax: Theme.wallpaperBlurMax
        blurMultiplier: Theme.wallpaperBlurMultiplier
    }

    Rectangle {
        anchors.fill: parent
        visible: wallpaper.status === Image.Ready
        color: Theme.background
        opacity: Theme.wallpaperTint
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.context.showPrompt = true;
            password.forceActiveFocus();
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * Theme.clockTop)

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: clock.date.toLocaleString(Qt.locale(Theme.dateLocale), Theme.dateFormat)
            color: Theme.overlayColor
            font.pixelSize: Theme.dateFontSize
            font.weight: Theme.dateFontWeight
            font.family: Theme.fontFamily
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, Theme.clockFormat)
            color: Theme.clockColor
            font.pixelSize: Theme.clockFontSize
            font.weight: Theme.clockFontWeight
            font.family: Theme.fontFamily
        }
    }

    Column {
        id: prompt

        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: Math.round(root.height * Theme.promptBottom)
        }
        spacing: Theme.promptSpacing
        visible: root.active

        Rectangle {
            id: avatar
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.avatarSize
            height: Theme.avatarSize
            radius: Theme.avatarRadius
            color: "transparent"

            // SDDM's avatar paths, then the penguin
            readonly property list<url> sources: [
                "file:///usr/share/sddm/faces/" + Quickshell.env("USER") + ".face.icon",
                "file://" + Quickshell.env("HOME") + "/.face.icon",
                "file://" + Quickshell.env("HOME") + "/.face",
                Qt.resolvedUrl("icons/avatar.svg")
            ]
            property int sourceIndex: 0

            Image {
                id: avatarImage
                anchors.fill: parent
                source: avatar.sources[avatar.sourceIndex]
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectCrop
                mipmap: true
                visible: false

                onStatusChanged: {
                    // Deferred: changing the source in its own status handler
                    // is a binding loop, and a missing file can report its
                    // error twice
                    if (status === Image.Error) {
                        const next = avatar.sources.indexOf(source) + 1;
                        if (next > 0 && next < avatar.sources.length)
                            Qt.callLater(() => avatar.sourceIndex = Math.max(avatar.sourceIndex, next));
                    }
                }
            }

            Rectangle {
                id: avatarMask
                anchors.fill: avatarImage
                radius: avatar.radius
                visible: false
                layer.enabled: true
            }

            MultiEffect {
                anchors.fill: avatarImage
                source: avatarImage
                maskEnabled: true
                maskSource: avatarMask
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Quickshell.env("USER")
            color: Theme.clockColor
            font.pixelSize: Theme.usernameFontSize
            font.weight: Theme.usernameFontWeight
            font.family: Theme.fontFamily
        }

        // Hidden with opacity, not `visible`, so the input keeps focus and
        // catches the first key
        Item {
            id: field

            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.inputWidth
            height: Theme.inputHeight
            opacity: root.context.showPrompt ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Theme.animationDuration
                }
            }

            transform: Translate {
                id: shake
            }

            SequentialAnimation {
                id: shakeAnimation

                NumberAnimation {
                    target: shake
                    property: "x"
                    to: -Theme.shakeDistance
                    duration: Theme.shakeDuration
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: shake
                    property: "x"
                    to: Theme.shakeDistance
                    duration: Theme.shakeDuration
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: shake
                    property: "x"
                    to: -Theme.shakeDistance
                    duration: Theme.shakeDuration
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: shake
                    property: "x"
                    to: Theme.shakeDistance
                    duration: Theme.shakeDuration
                    easing.type: Easing.InOutQuad
                }
                NumberAnimation {
                    target: shake
                    property: "x"
                    to: 0
                    duration: Theme.shakeDuration
                    easing.type: Easing.OutQuad
                }
            }

            Connections {
                target: root.context
                function onShowPromptChanged() {
                    if (root.context.showPrompt)
                        glass.appear();
                }
                function onFailed() {
                    shakeAnimation.restart();
                }
                function onCurrentTextChanged() {
                    password.text = root.context.currentText;
                }
            }

            Glass {
                id: glass

                anchors.fill: parent
                radius: Theme.inputRadius
                color: Theme.inputColor
                edgeColor: root.context.messageIsError && root.context.message !== "" ? Theme.errorColor : Theme.inputEdgeColor

                Text {
                    anchors.fill: password
                    visible: password.text.length === 0
                    text: Theme.placeholder
                    color: Theme.inputDimColor
                    font.pixelSize: Theme.inputFontSize
                    font.family: Theme.fontFamily
                    verticalAlignment: Text.AlignVCenter
                }

                TextInput {
                    id: password

                    anchors {
                        left: parent.left
                        right: capsLock.visible ? capsLock.left : button.left
                        top: parent.top
                        bottom: parent.bottom
                        leftMargin: Theme.inputPadding
                        rightMargin: Theme.inputPadding / 2
                    }
                    focus: true
                    clip: true
                    readOnly: root.context.unlockInProgress
                    echoMode: TextInput.Password
                    passwordCharacter: Theme.maskCharacter
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                    color: Theme.inputTextColor
                    selectionColor: Theme.selectedColor
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: Theme.inputFontSize
                    font.family: Theme.fontFamily
                    font.letterSpacing: Theme.maskSpacing

                    Component.onCompleted: forceActiveFocus()

                    onTextChanged: root.context.currentText = text
                    onAccepted: root.context.tryUnlock()

                    Keys.onPressed: event => {
                        if (!root.context.showPrompt) {
                            // The key that brings up the field isn't typed into
                            // it
                            if (event.key !== Qt.Key_Escape)
                                root.context.showPrompt = true;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape) {
                            if (!root.context.unlockInProgress)
                                root.context.showPrompt = false;
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    id: capsLock

                    anchors.right: button.left
                    anchors.rightMargin: Theme.inputPadding / 2
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.context.capsLock
                    text: Theme.capsLockIcon
                    color: Theme.inputDimColor
                    font.pixelSize: Theme.iconSize
                    font.family: Theme.fontFamily
                }

                Rectangle {
                    id: button

                    anchors.right: parent.right
                    anchors.rightMargin: (Theme.inputHeight - height) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.buttonSize
                    height: Theme.buttonSize
                    radius: Theme.buttonRadius
                    color: root.context.unlockInProgress ? "transparent" : password.text.length > 0 ? Theme.selectedColor : buttonArea.containsMouse ? Theme.inputHoverColor : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.animationDuration
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !root.context.unlockInProgress
                        text: Theme.submitIcon
                        color: password.text.length > 0 ? "white" : Theme.inputDimColor
                        font.pixelSize: Theme.iconSize
                        font.family: Theme.fontFamily
                    }

                    Spinner {
                        anchors.centerIn: parent
                        color: Theme.inputTextColor
                        width: Theme.iconSize
                        height: Theme.iconSize
                        visible: root.context.unlockInProgress
                    }

                    MouseArea {
                        id: buttonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            password.forceActiveFocus();
                            if (root.context.showPrompt)
                                root.context.tryUnlock();
                            else
                                root.context.showPrompt = true;
                        }
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            // Keeps its height when empty so nothing jumps
            text: {
                if (root.context.unlockInProgress)
                    return Theme.spinnerText;
                if (root.context.message !== "")
                    return root.context.message;
                return root.context.showPrompt ? " " : Theme.hintText;
            }
            color: root.context.messageIsError && root.context.message !== "" && !root.context.unlockInProgress ? Theme.errorColor : Theme.overlayColor
            font.pixelSize: Theme.messageFontSize
            font.family: Theme.fontFamily
        }
    }

    Text {
        readonly property var battery: UPower.displayDevice
        readonly property int percent: Math.round(battery.percentage * 100)

        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: Theme.statusMargin
        }
        visible: battery.isLaptopBattery
        text: (UPower.onBattery ? Theme.batteryIcon(percent) : Theme.chargingIcon) + "  " + percent + "%"
        color: Theme.overlayColor
        font.pixelSize: Theme.statusFontSize
        font.family: Theme.fontFamily
    }
}
