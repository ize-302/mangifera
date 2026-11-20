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
    readonly property string wallpaperSmall: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/mangifera/lock-wallpaper.jpg"
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
    // Face unlock, with howdy
    readonly property string faceText: "Looking for you"
    readonly property string faceFailedText: "Face not recognised, type your password"
    readonly property string faceWelcomeText: "Welcome back"
    readonly property color faceColor: "white"
    // Faint while you type, so it doesn't pull your eye off the field
    readonly property real faceDimOpacity: 0.25
    // ms per breath of the brackets while looking
    readonly property int facePulseDuration: 1100
    // ms the smile shows before the lock goes
    readonly property int faceMatchHold: 750
    readonly property real faceBounceScale: 1.08
    readonly property int faceBounceDuration: 300
    readonly property int faceShakeDistance: 5
    // The face that stands in for the avatar while scanning
    readonly property real faceGlyphStroke: 3.5
    readonly property real faceGlyphPadding: 10
    // How far the eyes move, as a share of the face
    readonly property real faceGlanceReach: 0.1
    // Eye travel per second, in reaches
    readonly property real faceEyeVelocity: 8
    // ms
    readonly property int faceGlanceDuration: 320
    readonly property int faceGlancePause: 160
    readonly property int faceBlinkInterval: 4000
    readonly property int faceBlinkDuration: 160
    readonly property int faceMoodDuration: 380
    readonly property int faceFrownHold: 1400
    // The avatar and face swap places
    readonly property int faceSwapDuration: 220
    readonly property real faceSwapScale: 0.85
    readonly property real faceBracketsPulseScale: 0.9
    readonly property real faceBracketsMatchScale: 0.86
    readonly property real faceBracketsHoverScale: 1.08

    // Unlock: the clock and prompt slide up and fade, in ms and px
    readonly property int exitDuration: 320
    readonly property int exitDistance: 48

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
