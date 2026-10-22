import QtQuick
import QtQuick.Effects
import "."

// Login screen, laid out like the lock screen. Power menu bottom right, session
// picker bottom left (only with several), user menu on the name (only with
// several). Shown on every screen.
Rectangle {
    id: root

    // userModel and sessionModel roles (sddm's UserModel.h, SessionModel.h)
    readonly property int nameRole: Qt.UserRole + 1
    readonly property int realNameRole: Qt.UserRole + 2
    readonly property int iconRole: Qt.UserRole + 4
    readonly property int needsPasswordRole: Qt.UserRole + 5
    readonly property int sessionNameRole: Qt.UserRole + 4

    property var users: []
    property list<string> sessions: []
    property int userIndex: 0
    property int sessionIndex: 0
    readonly property var user: users[userIndex] ?? {
        name: "",
        realName: "",
        icon: "",
        needsPassword: true
    }
    property bool busy: false
    property string message: ""
    property bool messageIsError: false

    color: Theme.background

    Component.onCompleted: {
        const found = [];
        for (let i = 0; i < userModel.rowCount(); i++) {
            const index = userModel.index(i, 0);
            found.push({
                name: userModel.data(index, nameRole),
                realName: userModel.data(index, realNameRole),
                icon: userModel.data(index, iconRole),
                needsPassword: userModel.data(index, needsPasswordRole)
            });
        }
        users = found;
        userIndex = Math.max(0, userModel.lastIndex);

        const names = [];
        for (let i = 0; i < sessionModel.rowCount(); i++)
            names.push(sessionModel.data(sessionModel.index(i, 0), sessionNameRole));
        sessions = names;
        sessionIndex = Math.max(0, sessionModel.lastIndex);

        password.forceActiveFocus();
    }

    function login() {
        if (busy || !user.name)
            return;
        busy = true;
        message = "";
        sddm.login(user.name, password.text, sessionIndex);
    }

    Connections {
        target: sddm

        function onLoginFailed() {
            root.busy = false;
            password.text = "";
            root.message = Theme.failedText;
            root.messageIsError = true;
            shakeAnimation.restart();
        }
        function onInformationMessage(text) {
            root.message = text;
            root.messageIsError = true;
        }
    }

    Image {
        id: wallpaper
        anchors.fill: parent
        visible: false
        source: Theme.wallpaper
        sourceSize: Qt.size(width * Theme.wallpaperScale, height * Theme.wallpaperScale)
        fillMode: Image.PreserveAspectCrop
        smooth: true
        asynchronous: true
        // The file is replaced under the same name
        cache: false
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

    // No wallpaper: the sheen over the whole screen
    Rectangle {
        anchors.fill: parent
        visible: wallpaper.status !== Image.Ready
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Theme.backgroundSheen
            }
            GradientStop {
                position: 0.6
                color: "transparent"
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: password.forceActiveFocus()
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(root.height * Theme.clockTop)

        Text {
            id: date
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.overlayColor
            font.pixelSize: Theme.dateFontSize
            font.weight: Theme.dateFontWeight
            font.family: Theme.fontFamily
        }

        Text {
            id: time
            anchors.horizontalCenter: parent.horizontalCenter
            color: Theme.clockColor
            font.pixelSize: Theme.clockFontSize
            font.weight: Theme.clockFontWeight
            font.family: Theme.fontFamily
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                const now = new Date();
                date.text = now.toLocaleString(Qt.locale(Theme.dateLocale), Theme.dateFormat);
                time.text = Qt.formatDateTime(now, Theme.clockFormat);
            }
        }
    }

    Column {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: Math.round(root.height * Theme.promptBottom)
        }
        spacing: Theme.promptSpacing

        Rectangle {
            id: avatar

            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.avatarSize
            height: Theme.avatarSize
            radius: Theme.avatarRadius
            color: "transparent"

            // SDDM's default face
            readonly property bool hasFace: root.user.icon !== "" && !String(root.user.icon).endsWith("/faces/.face.icon")

            Image {
                id: avatarImage
                anchors.fill: parent
                property bool failed: false
                source: avatar.hasFace && !failed ? root.user.icon : "icons/avatar.svg"
                onStatusChanged: {
                    if (status === Image.Error)
                        failed = true;
                }
                sourceSize: Qt.size(width, height)
                fillMode: Image.PreserveAspectCrop
                mipmap: true
                visible: false
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

        Item {
            id: name

            anchors.horizontalCenter: parent.horizontalCenter
            width: nameRow.width
            height: nameRow.height

            Row {
                id: nameRow

                spacing: 4

                Text {
                    text: root.user.realName || root.user.name
                    color: Theme.clockColor
                    font.pixelSize: Theme.usernameFontSize
                    font.weight: Theme.usernameFontWeight
                    font.family: Theme.fontFamily
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.users.length > 1
                    text: Theme.chooseIcon
                    color: Theme.overlayColor
                    font.pixelSize: Theme.iconSize
                    font.family: Theme.fontFamily
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                enabled: root.users.length > 1
                cursorShape: Qt.PointingHandCursor
                onClicked: userMenu.open()
            }
        }

        Item {
            id: field

            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.inputWidth
            height: Theme.inputHeight

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

            Glass {
                anchors.fill: parent
                radius: Theme.inputRadius
                color: Theme.inputColor
                edgeColor: root.messageIsError && root.message !== "" ? Theme.errorColor : Theme.inputEdgeColor

                Text {
                    anchors.fill: password
                    visible: password.text.length === 0
                    text: root.user.needsPassword ? Theme.placeholder : Theme.noPasswordPlaceholder
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
                    readOnly: root.busy
                    echoMode: TextInput.Password
                    passwordCharacter: Theme.maskCharacter
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                    color: Theme.inputTextColor
                    selectionColor: Theme.selectedColor
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: Theme.inputFontSize
                    font.family: Theme.fontFamily
                    font.letterSpacing: Theme.maskSpacing

                    onTextChanged: {
                        if (text !== "")
                            root.message = "";
                    }
                    onAccepted: root.login()

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            text = "";
                            event.accepted = true;
                        }
                    }
                }

                Text {
                    id: capsLock

                    anchors.right: button.left
                    anchors.rightMargin: Theme.inputPadding / 2
                    anchors.verticalCenter: parent.verticalCenter
                    visible: keyboard.capsLock
                    text: Theme.capsLockIcon
                    color: Theme.inputDimColor
                    font.pixelSize: Theme.iconSize
                    font.family: Theme.fontFamily
                }

                Rectangle {
                    id: button

                    readonly property bool ready: password.text.length > 0 || !root.user.needsPassword

                    anchors.right: parent.right
                    anchors.rightMargin: (Theme.inputHeight - height) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.buttonSize
                    height: Theme.buttonSize
                    radius: Theme.buttonRadius
                    color: root.busy ? "transparent" : ready ? Theme.selectedColor : buttonArea.containsMouse ? Theme.inputHoverColor : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.animationDuration
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !root.busy
                        text: Theme.submitIcon
                        color: button.ready ? "white" : Theme.inputDimColor
                        font.pixelSize: Theme.iconSize
                        font.family: Theme.fontFamily
                    }

                    Spinner {
                        anchors.centerIn: parent
                        color: Theme.inputTextColor
                        width: Theme.iconSize
                        height: Theme.iconSize
                        visible: root.busy
                    }

                    MouseArea {
                        id: buttonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            password.forceActiveFocus();
                            root.login();
                        }
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            // Keeps its height when empty so nothing jumps
            text: root.busy ? Theme.spinnerText : root.message || " "
            color: root.messageIsError && root.message !== "" && !root.busy ? Theme.errorColor : Theme.overlayColor
            font.pixelSize: Theme.messageFontSize
            font.family: Theme.fontFamily
        }
    }

    KeyButton {
        id: sessionButton

        anchors {
            left: parent.left
            bottom: parent.bottom
            margins: Theme.bottomMargin
        }
        visible: root.sessions.length > 1
        icon: Theme.sessionIcon
        label: root.sessions[root.sessionIndex] ?? ""
        onClicked: sessionMenu.open()
    }

    // What SDDM allows; session-ending ones last
    readonly property var powerActions: [
        {
            allowed: sddm.canSuspend,
            icon: Theme.sleepIcon,
            label: "Sleep",
            run: () => sddm.suspend()
        },
        {
            allowed: sddm.canReboot,
            icon: Theme.restartIcon,
            label: "Restart",
            run: () => sddm.reboot()
        },
        {
            allowed: sddm.canPowerOff,
            icon: Theme.shutDownIcon,
            label: "Shut Down",
            run: () => sddm.powerOff()
        }
    ].filter(action => action.allowed)

    Item {
        id: powerButton

        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: Theme.bottomMargin
        }
        width: Theme.keyHeight
        height: Theme.keyHeight
        visible: root.powerActions.length > 0

        Text {
            anchors.centerIn: parent
            text: Theme.shutDownIcon
            color: powerArea.containsMouse || powerMenu.visible ? Theme.clockColor : Theme.overlayDimColor
            font.pixelSize: Theme.powerIconSize
            font.family: Theme.fontFamily

            Behavior on color {
                ColorAnimation {
                    duration: Theme.animationDuration
                }
            }
        }

        MouseArea {
            id: powerArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: powerMenu.open()
        }
    }

    Menu {
        id: userMenu

        anchor: name
        below: true
        items: root.users.map(user => user.realName || user.name)
        currentIndex: root.userIndex
        onPicked: index => {
            avatarImage.failed = false;
            root.userIndex = index;
            root.message = "";
            password.text = "";
        }
        onVisibleChanged: {
            if (!visible)
                password.forceActiveFocus();
        }
    }

    Menu {
        id: powerMenu

        anchor: powerButton
        centred: false
        items: root.powerActions.map(action => action.label)
        icons: root.powerActions.map(action => action.icon)
        currentIndex: -1
        onPicked: index => root.powerActions[index].run()
        onVisibleChanged: {
            if (!visible)
                password.forceActiveFocus();
        }
    }

    Menu {
        id: sessionMenu

        anchor: sessionButton
        centred: false
        items: root.sessions
        currentIndex: root.sessionIndex
        onPicked: index => root.sessionIndex = index
        onVisibleChanged: {
            if (!visible)
                password.forceActiveFocus();
        }
    }
}
