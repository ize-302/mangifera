pragma Singleton

import QtQuick
import Quickshell

// Same glass as the bar; mango's layer_rule for "launcher" blurs behind it.
Singleton {
    // fontconfig fills in the Nerd Font glyphs
    readonly property string fontFamily: "Adwaita Sans"
    readonly property int fontSize: 15
    readonly property int fontWeight: 500

    // Fraction of the screen width
    readonly property real panelWidth: 0.22
    readonly property int panelPadding: 14
    readonly property color panelColor: Qt.rgba(32 / 255, 32 / 255, 32 / 255, 0.9)
    readonly property color glassPanelColor: Qt.rgba(32 / 255, 32 / 255, 32 / 255, 0.7)
    readonly property color edgeColor: Qt.rgba(1, 1, 1, 0.12)
    readonly property int panelRadius: 4
    readonly property int cornerRadius: 4
    // Gap between floating panels and the bar / screen edge
    readonly property int floatingGap: 3
    // Gap between the bar and popups centred above it
    readonly property int centredGap: 10

    // Search row
    readonly property int searchFontSize: 14
    readonly property string searchIcon: ""
    readonly property string placeholder: "Search…"
    readonly property color textColor: "#ffffff"
    readonly property color dimColor: "#9a9a9a"
    readonly property color dividerColor: Qt.rgba(1, 1, 1, 0.12)
    readonly property int searchPadding: 10

    // Results
    readonly property int maxRows: 12
    readonly property int rowHeight: 32
    readonly property int rowSpacing: 4
    readonly property int rowPadding: 8
    readonly property int iconSize: 22
    readonly property int iconSpacing: 10
    readonly property color selectedColor: textColor
    readonly property int selectedWeight: Font.DemiBold
    readonly property int unselectedWeight: Font.Normal
    readonly property color unselectedColor: keyTextColor
    readonly property color currentRowColor: Qt.rgba(1, 1, 1, 0.08)
    readonly property color hoverColor: Qt.rgba(1, 1, 1, 0.12)

    // Key caps
    readonly property color keyColor: Qt.rgba(1, 1, 1, 0.06)
    readonly property color keyTextColor: "#cccccc"
    readonly property int keyFontSize: 13
    readonly property int keyHeight: 22
    readonly property int keyPadding: 7
    readonly property int keySpacing: 4

    // Group headers
    readonly property int sectionFontSize: 12
    readonly property int sectionHeight: 30

    readonly property string emptyText: "No apps found"

    // Power menu
    readonly property string powerLockIcon: String.fromCodePoint(0xf0341)
    readonly property string powerLogoutIcon: String.fromCodePoint(0xf0343)
    readonly property string powerSleepIcon: String.fromCodePoint(0xf04b2)
    readonly property string powerRestartIcon: String.fromCodePoint(0xf0709)
    readonly property string powerShutDownIcon: String.fromCodePoint(0xf0425)
    readonly property string recordNoSoundIcon: String.fromCodePoint(0xf0581)
    readonly property string recordDesktopIcon: String.fromCodePoint(0xf0f5f)
    readonly property string recordMicIcon: String.fromCodePoint(0xf036c)
    readonly property string recordBothIcon: String.fromCodePoint(0xf08b4)
    readonly property string recordCameraIcon: String.fromCodePoint(0xf05a0)
    readonly property string recordStopIcon: String.fromCodePoint(0xf04db)
    readonly property int powerIconSize: 26
    readonly property int powerTileWidth: 72
    readonly property int powerTilePadding: 8
    readonly property int powerPanelPadding: 6
    readonly property int powerFontSize: 13
    readonly property color powerColor: Qt.rgba(32 / 255, 32 / 255, 32 / 255, 0.5)

    // Record menu: the settings rows (the picked option's fill), the mic
    // level under the sounds, and the 3-2-1 before recording
    readonly property string recordCircleIcon: String.fromCodePoint(0xf0765)
    readonly property string recordRectangleIcon: String.fromCodePoint(0xf0e5e)
    readonly property color recordChosenColor: Qt.rgba(1, 1, 1, 0.16)
    readonly property int recordSegmentHeight: 28
    // Gap between a row's track and the pill on the picked option
    readonly property int recordTrackPadding: 2
    readonly property int recordButtonHeight: 40
    readonly property int recordMeterHeight: 4
    // Level bar range, in dB below full scale
    readonly property int recordMeterFloor: 60
    readonly property int recordCountdownSeconds: 3
    readonly property int recordCountdownSize: 140
    readonly property int recordCountdownFontSize: 72
    readonly property int recordOutlineWidth: 2

    // Toolbox menu. Same dot as the bar's recording module
    readonly property string toolboxRecordIcon: String.fromCodePoint(0xf044a)
    readonly property string toolboxScreenshotIcon: String.fromCodePoint(0xf0e51)
    readonly property string toolboxClipboardIcon: String.fromCodePoint(0xf0147)
    readonly property string toolboxWallpaperIcon: String.fromCodePoint(0xf0e09)

    // Webcam bubble; size is the circle's diameter
    readonly property int cameraSize: 220
    readonly property int cameraMinSize: 120
    readonly property int cameraMaxSize: 480
    // Width of the band along the edge that resizes it
    readonly property int cameraGrip: 14
    readonly property real cameraZoomStep: 0.1
    readonly property real cameraMaxZoom: 3
    readonly property int cameraCornerRadius: 16
    // Gap from the screen edge and the bar the first time
    readonly property int cameraMargin: 24

    // App menu
    readonly property real appMenuWidth: 0.28

    // Clipboard menu
    readonly property real clipboardWidth: 0.35
    readonly property string clipboardEmptyText: "Nothing found"

    // Key bindings menu
    readonly property string keybindTitle: "Shortcuts"
    readonly property int keybindPadding: 28
    readonly property int keybindFontSize: 14
    readonly property int keybindRowHeight: 28
    readonly property int keybindGroupGap: 18
    readonly property int keybindLabelGap: 24
    readonly property int keybindColumnGap: 32
    // Longer descriptions are cut short
    readonly property int keybindMaxLabel: 36
    // Fraction of the screen height before the columns scroll
    readonly property real keybindMaxHeight: 0.65
    readonly property int keybindScrollbarWidth: 6
    readonly property int keybindSearchWidth: 200
    readonly property string keybindEmptyText: "No bindings found"

    // Scratchpad menu
    readonly property string scratchpadEmptyText: "No windows in the scratchpad"
    // Fraction of the screen width
    readonly property real cardWidth: 0.15
    // Max ms between the two Super taps
    readonly property int doubleTapInterval: 400
    // mango's tag_num
    readonly property int tagCount: 9
    readonly property int closeButtonSize: 24
    readonly property color closeColor: "#f7768e"
    readonly property int stripFadeWidth: 64
    // Fraction of the screen height
    readonly property real cardHeight: 0.2
    readonly property int cardSpacing: 6
    readonly property int cardTitleHeight: 34

    // Control panel
    readonly property real controlWidth: 0.18
    readonly property int sectionGap: 12
    readonly property int controlFontSize: 14
    readonly property int controlSmallFontSize: 12
    readonly property string controlEmptyText: "Nothing to control"
    readonly property real volumeStep: 0.01
    readonly property int sliderHeight: 6
    readonly property color sliderTrackColor: keyColor
    readonly property color sliderKnobColor: "white"
    readonly property int knobSize: 12
    readonly property int knobActiveSize: 16
    // Same glyphs as the bar
    readonly property string volumeMutedIcon: "\uf026"
    readonly property string volumeLowIcon: "\uf027"
    readonly property string volumeHighIcon: "\uf028"
    readonly property string micIcon: "\uf130"
    readonly property string micMutedIcon: "\uf131"
    readonly property string bluetoothIcon: String.fromCodePoint(0xf00af)
    readonly property string bluetoothConnectedIcon: String.fromCodePoint(0xf00b1)
    readonly property string bluetoothOffIcon: String.fromCodePoint(0xf00b2)
    readonly property color controlIconColor: keyTextColor
    readonly property color controlIconOffColor: dimColor
    // Wi-Fi signal bars, like the bar's network module
    readonly property list<string> wifiStrengthIcons: [0xf08bf, 0xf08bc, 0xf08bd, 0xf08be].map(code => String.fromCodePoint(code))
    readonly property string wifiOffIcon: String.fromCodePoint(0xf0783)
    readonly property string lockIcon: String.fromCodePoint(0xf033e)
    readonly property int maxNetworks: 6
    readonly property string passwordPlaceholder: "Password"
    readonly property string networkInfo: Quickshell.env("HOME") + "/.local/bin/network-info"
    readonly property string bluetoothAudio: Quickshell.env("HOME") + "/.local/bin/bluetooth-audio"
    // On/off switch
    readonly property int toggleWidth: 30
    readonly property int toggleHeight: 18
    readonly property color toggleOnColor: "#0a84ff"
    readonly property string pageIcon: String.fromCodePoint(0xf0142)
    readonly property string backIcon: String.fromCodePoint(0xf0141)
    readonly property int pageSlide: 24
    // Same as focus_color in the mango config
    readonly property color accentColor: "#ff7518"

    // Bluetooth pairing and Wi-Fi password prompts
    readonly property int pairingWidth: 400
    readonly property int pairingCodeSize: 20
    readonly property int pairingButtonWidth: 80
    readonly property int pairingButtonHeight: 30

    // Now playing
    readonly property int mediaArtSize: 48
    readonly property int mediaButtonSize: 26
    readonly property int mediaPlaySize: 30
    readonly property string musicIcon: String.fromCodePoint(0xf075a)
    readonly property string previousIcon: String.fromCodePoint(0xf04ae)
    readonly property string nextIcon: String.fromCodePoint(0xf04ad)
    readonly property string playIcon: String.fromCodePoint(0xf040a)
    readonly property string pauseIcon: String.fromCodePoint(0xf03e4)

    // Caps lock popup. Lights are polled every capsLockPoll ms
    readonly property int capsLockSize: 60
    readonly property int capsLockIconSize: 24
    readonly property int capsLockFontSize: 9
    readonly property int capsLockTimeout: 1200
    readonly property int capsLockPoll: 150
    // Caps lock and volume popups' glass
    readonly property color popupColor: Qt.rgba(32 / 255, 32 / 255, 32 / 255, 0.5)
    readonly property color popupEdgeColor: Qt.rgba(1, 1, 1, 0.08)

    // Bar (Bar.qml)
    readonly property int barHeight: 32
    readonly property color barColor: Qt.rgba(32 / 255, 32 / 255, 32 / 255, 0.85)
    readonly property string barFontFamily: "JetBrainsMono NF"
    // Points, as waybar had it
    readonly property real barFontSize: 13
    readonly property int barModulePadding: 12
    readonly property color barModuleColor: Qt.rgba(1, 1, 1, 0.03)
    readonly property color barFocusedColor: Qt.rgba(1, 1, 1, 0.15)
    readonly property color barUrgentColor: closeColor
    readonly property color barUrgentTextColor: "#15161e"
    readonly property color barModeColor: "#ff5555"
    readonly property color barOffColor: "#808080"
    readonly property color barFadedColor: Qt.rgba(1, 1, 1, 0.4)
    readonly property color barTrayColor: Qt.rgba(192 / 255, 202 / 255, 245 / 255, 0.06)
    readonly property int barTrayIconSize: 21
    readonly property int barTraySpacing: 14
    readonly property color barRecordingColor: "#ff453a"
    readonly property color barRecordingBackground: Qt.rgba(1, 1, 1, 0.08)
    readonly property color barChargingColor: "#7dd3fc"
    readonly property color barDividerColor: Qt.rgba(1, 1, 1, 0.25)
    // Hover time before a tooltip shows
    readonly property int barTooltipDelay: 500
    readonly property color barTooltipColor: "#202020"
    readonly property int barTooltipFontSize: 13
    // Green to red as a reading rises; [threshold, colour], highest first
    readonly property var barLoadColors: [[70, "#ff0000"], [60, "#ff8000"], [50, "#ffbf00"], [25, "#ffff00"], [10, "#bfff00"], [0, "#00ff00"]]
    readonly property var barDiskColors: [[92, "#ff0000"], [85, "#ff8000"], [75, "#ffbf00"], [65, "#ffff00"], [50, "#bfff00"], [0, "#00ff00"]]
    // The thermometer empties as it cools: [from °C, colour, icon]
    readonly property var barTemperatureLevels: [[70, "#ff0000", 0xf2c7], [65, "#ff8000", 0xf2c7], [60, "#ffbf00", 0xf2c8], [55, "#ffff00", 0xf2c9], [50, "#bfff00", 0xf2ca], [0, "#00ff00", 0xf2cb]].map(([level, colour, code]) => [level, colour, String.fromCodePoint(code)])
    // Battery is the other way round: [below or at, colour]
    readonly property var barBatteryColors: [[9, "#ff0000"], [29, "#ff8000"], [49, "#ffff00"], [79, "#bfff00"]]
    readonly property color barBatteryFullColor: "#00ff00"

    readonly property string barToolboxIcon: String.fromCodePoint(0xf09ac)
    readonly property string barDiskIcon: "\uf233"
    readonly property string barCpuIcon: "\uee9c"
    readonly property string barMemoryIcon: "\uefc5"
    readonly property string barBacklightIcon: String.fromCodePoint(0xf05a8)
    readonly property string barEthernetIcon: String.fromCodePoint(0xf0200)
    readonly property string barChargingIcon: String.fromCodePoint(0xf0084)
    // [below or at, icon], then the full one
    readonly property var barBatteryIcons: [[9, 0xf007b], [29, 0xf007c], [49, 0xf007e], [79, 0xf0080]].map(([level, code]) => [level, String.fromCodePoint(code)])
    readonly property string barBatteryFullIcon: String.fromCodePoint(0xf0079)
    // App icons on the tags: size, gap after the number, between icons, and
    // after the last
    readonly property int barTagIconSize: 18
    readonly property int barTagIconGap: 6
    readonly property int barTagIconSpacing: 4
    readonly property int barTagPadding: 10

    // Tray app menus (TrayMenu.qml)
    readonly property int trayIconSize: 18
    readonly property int trayMenuMaxWidth: 360
    readonly property string trayBackText: "Back"
    readonly property string trayCheckOnIcon: String.fromCodePoint(0xf0132)
    readonly property string trayCheckOffIcon: String.fromCodePoint(0xf0131)
    readonly property string trayRadioOnIcon: String.fromCodePoint(0xf043e)
    readonly property string trayRadioOffIcon: String.fromCodePoint(0xf043d)

    // Volume popup
    readonly property int osdWidth: 40
    readonly property int osdFontSize: 10
    readonly property int osdHeight: 200
    readonly property int osdTimeout: 1500

    function volumeColor(volume, muted) {
        if (muted)
            return Qt.rgba(1, 1, 1, 0.3);
        return volume > 1.005 ? closeColor : textColor;
    }

    function sliderColor(volume, muted) {
        if (muted)
            return dimColor;
        return volume > 1.005 ? closeColor : toggleOnColor;
    }

    function volumeIcon(volume, muted) {
        return muted ? volumeMutedIcon : Math.round(volume * 100) > 50 ? volumeHighIcon : volumeLowIcon;
    }

    // Pomodoro, in minutes
    readonly property int pomodoroFocus: 25
    readonly property int pomodoroShortBreak: 5
    readonly property int pomodoroLongBreak: 15
    readonly property int pomodoroRounds: 4
    readonly property int pomodoroFontSize: 18
    readonly property int pomodoroDotSize: 6
    readonly property color pomodoroBreakColor: "#30d158"
    readonly property string pomodoroIcon: String.fromCodePoint(0xf051b)
    readonly property string pomodoroBreakIcon: String.fromCodePoint(0xf0176)

    // Calendar
    readonly property int calendarCellSize: 30
    readonly property int calendarFontSize: 12

    // Notifications
    readonly property int notificationWidth: 360
    readonly property int notificationSpacing: 6
    readonly property int notificationIconSize: 32
    readonly property int maxPopups: 3
    // Default timeout; critical ones stay until closed
    readonly property int notificationTimeout: 5000
    // Notification centre cards
    readonly property color noteCardColor: glassPanelColor
    readonly property color noteCardHoverColor: Qt.rgba(52 / 255, 52 / 255, 52 / 255, 0.75)
    readonly property int noteCardStackPeek: 6
    readonly property int noteCardStackInset: 10
    readonly property int noteCardButtonHeight: 26

    readonly property real notificationCenterMaxHeight: 0.7
    readonly property int notificationFadeHeight: 48
    readonly property string noNotificationsText: "No notifications"
    readonly property string doNotDisturbText: "Do not disturb is on"
    readonly property int maxNotifications: 50
    readonly property int notificationBodyLines: 3
    readonly property string notificationSound: "/usr/share/sounds/freedesktop/stereo/message.oga"
    readonly property string closeIcon: String.fromCodePoint(0xf0156)
    readonly property string bellIcon: String.fromCodePoint(0xf009a)
    readonly property string bellUnreadIcon: String.fromCodePoint(0xf116b)
    readonly property int notificationRowIconSize: 20
    readonly property string doNotDisturbIcon: String.fromCodePoint(0xf009b)
    // Hour "until morning" ends
    readonly property int doNotDisturbMorning: 8

    readonly property int animationDuration: 120
    // Panels fading and rising in: short, so they feel instant
    readonly property int appearDuration: 70
    // Launchers sliding up out of the bar and back down into it
    readonly property int launcherSlide: 40
    readonly property int launcherSlideDuration: 140

    // For entries with Terminal=true
    readonly property list<string> terminal: ["alacritty", "-e"]
}
