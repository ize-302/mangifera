pragma Singleton

import QtQuick

// Copied from the lock screen's Theme.qml: the greeter can't import Quickshell
// configs.
QtObject {
    readonly property string fontFamily: "Adwaita Sans"
    readonly property color background: "#15161e"
    // Copied here by ~/.local/bin/wallpaper, as SDDM can't read $HOME
    readonly property string wallpaper: "file:///var/lib/sddm-wallpaper/current"
    readonly property real wallpaperScale: 0.25
    readonly property real wallpaperBlur: 1.0
    readonly property int wallpaperBlurMax: 32
    readonly property real wallpaperBlurMultiplier: 2
    readonly property real wallpaperTint: 0.45
    readonly property color backgroundSheen: Qt.rgba(1, 1, 1, 0.025)

    // Glass
    readonly property color glassColor: Qt.rgba(1, 1, 1, 0.04)
    readonly property color edgeColor: Qt.rgba(1, 1, 1, 0.16)
    // Menus
    readonly property color menuColor: Qt.rgba(32 / 255, 32 / 255, 32 / 255, 0.7)
    readonly property color menuTextColor: "white"
    readonly property color menuSoftTextColor: "#cccccc"
    readonly property int menuSelectedWeight: Font.DemiBold
    readonly property color menuCurrentRowColor: Qt.rgba(1, 1, 1, 0.08)

    readonly property color textColor: "#c0caf5"
    readonly property color dimColor: "#565f89"
    readonly property color softTextColor: "#a9b1d6"
    readonly property color clockColor: "white"
    readonly property color overlayColor: Qt.rgba(1, 1, 1, 0.85)
    readonly property color overlayDimColor: Qt.rgba(1, 1, 1, 0.8)
    readonly property color selectedColor: "#0a84ff"
    readonly property color errorColor: "#f7768e"
    readonly property color hoverColor: Qt.rgba(192 / 255, 202 / 255, 245 / 255, 0.12)
    // Key caps
    readonly property color keyColor: Qt.rgba(192 / 255, 202 / 255, 245 / 255, 0.05)

    readonly property string dateFormat: "dddd d MMMM"
    readonly property string dateLocale: "en_GB"
    readonly property int dateFontSize: 20
    readonly property int dateFontWeight: 500
    readonly property string clockFormat: "hh:mm"
    readonly property int clockFontSize: 104
    readonly property int clockFontWeight: Font.Light
    readonly property real clockTop: 0.1

    readonly property int avatarSize: 88
    readonly property int avatarRadius: 14
    readonly property int usernameFontSize: 16
    readonly property int usernameFontWeight: 600
    readonly property real promptBottom: 0.16
    readonly property int promptSpacing: 12
    // Beside the name when there's more than one user
    readonly property string chooseIcon: String.fromCodePoint(0xf0140)

    // Password field
    readonly property int inputWidth: 260
    readonly property color inputColor: "white"
    readonly property color inputTextColor: "#1a1b26"
    readonly property color inputDimColor: Qt.rgba(26 / 255, 27 / 255, 38 / 255, 0.45)
    readonly property color inputHoverColor: Qt.rgba(26 / 255, 27 / 255, 38 / 255, 0.08)
    readonly property color inputEdgeColor: Qt.rgba(1, 1, 1, 0.3)
    readonly property int inputHeight: 36
    readonly property int inputRadius: 4
    readonly property int inputPadding: 12
    readonly property int inputFontSize: 14
    readonly property string placeholder: "Enter Password"
    readonly property string noPasswordPlaceholder: "Press Enter to log in"
    readonly property string maskCharacter: "•"
    readonly property int maskSpacing: 3
    readonly property int buttonSize: 26
    readonly property int buttonRadius: 2
    readonly property string submitIcon: String.fromCodePoint(0xf0054)
    readonly property string capsLockIcon: String.fromCodePoint(0xf0632)
    readonly property int iconSize: 16
    readonly property int shakeDistance: 10
    readonly property int shakeDuration: 60

    readonly property int messageFontSize: 13
    readonly property string spinnerText: "waking the penguin"
    readonly property string failedText: "Wrong password"

    readonly property int bottomMargin: 24
    readonly property int keyHeight: 30
    readonly property int keyPadding: 10
    readonly property int keySpacing: 8
    readonly property int keyFontSize: 13
    readonly property string sessionIcon: String.fromCodePoint(0xf0379)
    readonly property string sleepIcon: String.fromCodePoint(0xf04b2)
    readonly property string restartIcon: String.fromCodePoint(0xf0709)
    readonly property string shutDownIcon: String.fromCodePoint(0xf0425)
    readonly property int powerIconSize: 20

    readonly property int menuRadius: 4
    readonly property int menuPadding: 6
    readonly property int menuWidth: 220
    readonly property int rowHeight: 32
    readonly property int rowPadding: 10
    readonly property int rowRadius: 2
    readonly property int menuGap: 6
    readonly property string checkIcon: ""

    readonly property int animationDuration: 120
}
