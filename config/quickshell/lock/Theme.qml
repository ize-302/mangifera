pragma Singleton

import QtQuick
import Quickshell

// Values copied from the launcher's Theme.qml (separate Quickshell config); the
// SDDM theme copies them too.
Singleton {
    readonly property string fontFamily: "Adwaita Sans"
    readonly property color background: "#15161e"

    // Glass
    readonly property color glassColor: Qt.rgba(21 / 255, 22 / 255, 30 / 255, 0.6)
    readonly property color sheenTop: Qt.rgba(1, 1, 1, 0.05)
    readonly property color sheenMiddle: Qt.rgba(1, 1, 1, 0.01)
    readonly property color edgeColor: Qt.rgba(1, 1, 1, 0.16)

    readonly property color textColor: "#c0caf5"
    readonly property color dimColor: "#565f89"
    readonly property color softTextColor: "#a9b1d6"
    readonly property color clockColor: "white"
    readonly property color overlayColor: Qt.rgba(1, 1, 1, 0.85)
    readonly property color selectedColor: "#0a84ff"
    readonly property color errorColor: "#f7768e"
    readonly property color hoverColor: Qt.rgba(192 / 255, 202 / 255, 245 / 255, 0.12)

    // Blurred wallpaper last set by ~/.local/bin/wallpaper
    readonly property string wallpaperState: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/mangifera/wallpaper"
    // Loading smaller blurs smoother
    readonly property real wallpaperScale: 0.25
    readonly property real wallpaperBlur: 1.0
    readonly property int wallpaperBlurMax: 32
    readonly property real wallpaperBlurMultiplier: 2
    readonly property real wallpaperTint: 0.45

    readonly property string dateFormat: "dddd d MMMM"
    readonly property string dateLocale: "en_GB"
    readonly property int dateFontSize: 20
    readonly property int dateFontWeight: 500
    readonly property string clockFormat: "hh:mm"
    readonly property int clockFontSize: 104
    readonly property int clockFontWeight: Font.Light
    // Fraction of the screen height
    readonly property real clockTop: 0.1

    readonly property int avatarSize: 88
    readonly property int avatarRadius: 14
    readonly property int usernameFontSize: 16
    readonly property int usernameFontWeight: 600
    // Fraction of the screen height
    readonly property real promptBottom: 0.16
    readonly property int promptSpacing: 12

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
    readonly property string maskCharacter: "•"
    readonly property int maskSpacing: 3
    readonly property int buttonSize: 26
    readonly property int buttonRadius: 2
    readonly property string submitIcon: String.fromCodePoint(0xf0054)
    readonly property string capsLockIcon: String.fromCodePoint(0xf0632)
    readonly property int iconSize: 16
    // ms
    readonly property int capsLockPoll: 150
    readonly property int shakeDistance: 10
    readonly property int shakeDuration: 60

    readonly property int messageFontSize: 13
    readonly property string hintText: "Type to unlock"
    readonly property string spinnerText: "waking the penguin"

    // Battery, bottom right
    readonly property int statusFontSize: 14
    readonly property int statusMargin: 24
    readonly property string chargingIcon: String.fromCodePoint(0xf0084)
    function batteryIcon(percent) {
        if (percent <= 9)
            return String.fromCodePoint(0xf007b);
        if (percent <= 29)
            return String.fromCodePoint(0xf007c);
        if (percent <= 49)
            return String.fromCodePoint(0xf007e);
        if (percent <= 79)
            return String.fromCodePoint(0xf0080);
        return String.fromCodePoint(0xf0079);
    }

    readonly property int animationDuration: 120

    // Seconds idle before the field hides
    readonly property int promptTimeout: 30
}
