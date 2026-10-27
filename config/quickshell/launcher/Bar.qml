pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// The bar along the bottom of every screen: tags on the left, system readings
// in the middle, tray, controls and the clock on the right. Panels it opens
// are centred over the module clicked.
Scope {
    id: root

    // shell.qml: its call() and openAt(), and the pomodoro and notification
    // server the bar shows
    property var shell: null
    property var pomodoro: null
    property var notifications: null

    // Recording: ms wf-recorder started at, 0 when not recording
    property real recordingSince: 0
    property real now: Date.now()

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool playing: Mpris.players.values.some(player => player.isPlaying)

    readonly property NetworkDevice wifiDevice: Networking.devices.values.find(device => device.type === DeviceType.Wifi) ?? null
    readonly property NetworkDevice wiredDevice: Networking.devices.values.find(device => device.type === DeviceType.Wired && device.connected) ?? null
    readonly property WifiNetwork wifiNetwork: Networking.wifiEnabled ? wifiDevice?.networks.values.find(network => network.connected) ?? null : null

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property list<BluetoothDevice> bluetoothConnected: adapter?.devices.values.filter(device => device.connected) ?? []

    readonly property UPowerDevice battery: UPower.displayDevice

    // First entry of a [threshold, ...] table the value reaches
    function level(table, value) {
        return table.find(entry => value >= entry[0]) ?? table[table.length - 1];
    }

    function duration(seconds) {
        return Math.floor(seconds / 3600) + "h" + Math.floor(seconds % 3600 / 60) + "m";
    }

    // From the app's desktop entry, else an icon named after it
    function appIcon(appId) {
        const entry = DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId);
        return Quickshell.iconPath(entry?.icon || appId, "application-x-executable");
    }

    function gib(bytes) {
        return Math.round(bytes / 1024 / 1024 / 1024) + "G";
    }

    // Opens a panel centred over a module, through shell.qml
    function openAt(module, screen, line) {
        const centre = module.mapToItem(null, module.width / 2, 0).x;
        root.shell?.openAt(screen, centre, line);
    }

    function setVolume(steps) {
        const audio = root.sink?.audio;
        if (!audio)
            return;
        // Up stops at 100%, but leaves anything above it alone
        const target = audio.volume + steps * Theme.volumeStep;
        if (steps > 0 && audio.volume < 1)
            audio.volume = Math.min(1, target);
        else if (steps < 0)
            audio.volume = Math.max(0, target);
    }

    BarStats {
        id: stats
        networkInterface: (root.wiredDevice ?? (root.wifiNetwork ? root.wifiDevice : null))?.name ?? ""
    }

    // Volumes are only there for tracked nodes
    PwObjectTracker {
        objects: [root.sink]
    }

    // The start time, from how long wf-recorder has been running
    Process {
        id: recordingCheck
        running: true
        command: ["sh", "-c", "pid=$(pgrep -ox wf-recorder) && ps -o etimes= -p \"$pid\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const seconds = parseInt(text);
                root.now = Date.now();
                root.recordingSince = isNaN(seconds) ? 0 : root.now - seconds * 1000;
            }
        }
    }

    Timer {
        running: root.recordingSince > 0
        repeat: true
        interval: 1000
        onTriggered: root.now = Date.now()
    }

    // Also called over the launcher socket (shell.qml)
    property alias ipc: ipcHandler

    IpcHandler {
        id: ipcHandler
        target: "bar"

        // ~/.local/bin/record-toggle, as recording starts and stops
        function recordingChanged(): void {
            recordingCheck.running = true;
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow { // qmllint disable uncreatable-type
            id: window

            required property var modelData
            // The BarModule under the pointer, for its tooltip; each sets it
            property Item hovered: null
            property bool tipDelayed: true
            // Clicked: no tooltip until the pointer moves to another module
            property bool tipDismissed: false
            readonly property var monitor: Compositor.monitors.find(monitor => monitor.name === modelData.name) ?? null

            screen: modelData
            // See Compositor.remapping
            visible: !Compositor.remapping
            color: Theme.barColor
            implicitHeight: Theme.barHeight
            exclusionMode: ExclusionMode.Auto

            WlrLayershell.namespace: "bar"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                bottom: true
                left: true
                right: true
            }

            onHoveredChanged: {
                tipDismissed = false;
                if (!hovered) {
                    tipDelayed = true;
                    tipDelay.stop();
                } else if (tipDelayed) {
                    tipDelay.restart();
                }
            }

            Timer {
                id: tipDelay
                interval: Theme.barTooltipDelay
                onTriggered: window.tipDelayed = false
            }

            Connections {
                target: window.hovered
                ignoreUnknownSignals: true

                function onPressedChanged() {
                    if (window.hovered.pressed)
                        window.tipDismissed = true;
                }
            }

            BarTooltip {
                anchor.window: window
                target: window.tipDelayed || window.tipDismissed ? null : window.hovered
            }

            // Top edge
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.edgeColor
            }

            Item {
                id: content

                anchors.fill: parent

                Row {
                    id: left

                    height: parent.height

                    Repeater {
                        model: Theme.tagCount

                        BarModule {
                            id: tag

                            required property int index
                            readonly property int number: index + 1
                            readonly property var tagState: window.monitor?.tags.find(tag => tag.index === number) ?? null
                            readonly property var windows: Compositor.clients.filter(client => client.monitor === window.modelData.name && !client.is_minimized && client.tags.includes(number)).sort((a, b) => a.id - b.id)
                            readonly property bool active: tagState?.is_active ?? false
                            readonly property bool urgent: tagState?.is_urgent ?? false
                            readonly property bool focused: active && (window.monitor?.active ?? false)
                            // Changes only with the windows, not their titles,
                            // so the icons aren't rebuilt as titles tick
                            readonly property string appIds: windows.map(client => client.appid ?? "").join("\n")

                            text: active || windows.length > 0 ? String(number) : ""
                            leftPadding: 6
                            rightPadding: windows.length > 0 ? Theme.barTagPadding : 6
                            contentWidth: tag.label.implicitWidth + (windows.length > 0 ? Theme.barTagIconGap + tagIcons.implicitWidth : 0)
                            color: urgent ? Theme.barUrgentColor : focused ? Theme.barFocusedColor : Theme.barModuleColor
                            textColor: urgent ? Theme.barUrgentTextColor : Theme.textColor

                            onClicked: button => {
                                if (button === Qt.LeftButton)
                                    Quickshell.execDetached(["mmsg", "dispatch", `viewcrossmon,${number},${window.modelData.name}`]);
                            }

                            // Each window's app icon, oldest first
                            Row {
                                id: tagIcons

                                x: tag.leftPadding + tag.label.implicitWidth + Theme.barTagIconGap
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.barTagIconSpacing

                                Repeater {
                                    model: tag.appIds ? tag.appIds.split("\n") : []

                                    IconImage {
                                        required property string modelData

                                        implicitSize: Theme.barTagIconSize
                                        source: root.appIcon(modelData)
                                    }
                                }
                            }
                        }
                    }

                    // Minimized windows, one dot each
                    BarModule {
                        readonly property var parked: Compositor.clients.filter(client => client.is_minimized && !client.is_namedscratchpad)

                        text: parked.length === 0 ? "" : parked.length > 4 ? "••••+" : "•".repeat(parked.length)
                        tooltip: parked.map(client => `${client.appid}: ${client.title}`).join("\n")
                        leftPadding: 8
                        rightPadding: 8
                        color: Theme.barModuleColor

                        onClicked: button => {
                            if (button === Qt.LeftButton)
                                root.shell?.call("scratchpad toggleScratchpadMenu");
                        }
                    }

                    // mango's key mode, unless default
                    BarModule {
                        readonly property string mode: Compositor.focusedMonitor?.keymode ?? "default"

                        text: mode === "default" ? "" : mode
                        leftPadding: 6
                        rightPadding: 6
                        color: Theme.barModeColor
                        textColor: Theme.barUrgentTextColor
                    }
                }

                Row {
                    id: centre

                    height: parent.height
                    anchors.horizontalCenter: parent.horizontalCenter

                    BarModule {
                        readonly property var level: root.level(Theme.barTemperatureLevels, stats.temperature)

                        text: stats.temperature > 0 ? level[2] + " " + stats.temperature + "ºC" : ""
                        textColor: level[1]
                    }

                    BarModule {
                        text: stats.diskTotal > 0 ? Theme.barDiskIcon + " " + stats.disk + "%" : ""
                        textColor: root.level(Theme.barDiskColors, stats.disk)[1]
                        tooltip: `Used ${root.gib(stats.diskUsed)}\nFree ${root.gib(stats.diskFree)}\nTotal ${root.gib(stats.diskTotal)}`
                    }

                    BarModule {
                        text: Theme.barCpuIcon + " " + stats.cpu + "%"
                        textColor: root.level(Theme.barLoadColors, stats.cpu)[1]

                        onClicked: button => {
                            if (button === Qt.LeftButton)
                                Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/btop-toggle"]);
                        }
                    }

                    BarModule {
                        text: Theme.barMemoryIcon + " " + stats.memory + "%"
                        textColor: root.level(Theme.barLoadColors, stats.memory)[1]
                        tooltip: `RAM ${stats.memoryUsed.toFixed(1)} / ${stats.memoryTotal.toFixed(1)} GiB\nFree ${stats.memoryFree.toFixed(1)} GiB\nSwap ${stats.swapUsed.toFixed(1)} / ${stats.swapTotal.toFixed(1)} GiB`

                        onClicked: button => {
                            if (button === Qt.LeftButton)
                                Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/btop-toggle"]);
                        }
                    }

                    BarModule {
                        readonly property bool present: root.battery?.ready && root.battery?.isLaptopBattery && root.battery?.isPresent
                        readonly property int percent: Math.round((root.battery?.percentage ?? 0) * 100)
                        readonly property bool charging: !UPower.onBattery
                        readonly property var level: Theme.barBatteryIcons.find(([below]) => percent <= below) ?? null

                        text: present ? (charging ? Theme.barChargingIcon : level?.[1] ?? Theme.barBatteryFullIcon) + " " + percent + "%" : ""
                        textColor: charging ? Theme.barChargingColor : Theme.barBatteryColors.find(([below]) => percent <= below)?.[1] ?? Theme.barBatteryFullColor
                        tooltip: {
                            if (!present)
                                return "";
                            if (!charging && root.battery.timeToEmpty > 0)
                                return root.duration(root.battery.timeToEmpty) + " left";
                            if (charging && root.battery.timeToFull > 0)
                                return root.duration(root.battery.timeToFull) + " until full";
                            // No estimate: say what it's doing instead
                            if (root.battery.state === UPowerDeviceState.FullyCharged)
                                return "Fully charged";
                            if (root.battery.state === UPowerDeviceState.PendingCharge)
                                return "Plugged in, not charging";
                            return charging ? "Charging" : "On battery";
                        }
                    }
                }

                Row {
                    id: right

                    height: parent.height
                    anchors.right: parent.right

                    // Click stops, right-click changes the sound or camera
                    BarModule {
                        id: recording

                        readonly property int seconds: Math.max(0, Math.floor((root.now - root.recordingSince) / 1000))
                        readonly property string elapsed: {
                            const pad = value => String(value).padStart(2, "0");
                            const minutes = pad(Math.floor(seconds % 3600 / 60)) + ":" + pad(seconds % 60);
                            return seconds >= 3600 ? Math.floor(seconds / 3600) + ":" + minutes : minutes;
                        }

                        // The dot pulses; the time stays put
                        text: root.recordingSince > 0 ? Theme.toolboxRecordIcon + " " + elapsed : ""
                        tooltip: "Recording the screen. Click to stop"
                        color: Theme.barRecordingBackground
                        label.visible: false
                        contentWidth: recordingRow.implicitWidth

                        onClicked: button => {
                            if (button === Qt.LeftButton)
                                Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/record-toggle"]);
                            else if (button === Qt.RightButton)
                                root.shell?.call("record toggleLiveMenu");
                        }

                        Row {
                            id: recordingRow

                            x: recording.leftPadding
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                id: dot

                                text: Theme.toolboxRecordIcon + " "
                                color: Theme.barRecordingColor
                                font.family: Theme.barFontFamily
                                font.pointSize: Theme.barFontSize
                                font.weight: Theme.fontWeight

                                SequentialAnimation on color {
                                    running: recording.visible
                                    loops: Animation.Infinite

                                    ColorAnimation {
                                        to: Qt.rgba(1, 69 / 255, 58 / 255, 0.25)
                                        duration: 1000
                                        easing.type: Easing.InOutQuad
                                    }
                                    ColorAnimation {
                                        to: Theme.barRecordingColor
                                        duration: 1000
                                        easing.type: Easing.InOutQuad
                                    }
                                }
                            }

                            Text {
                                text: recording.elapsed
                                color: Theme.textColor
                                font.family: Theme.barFontFamily
                                font.pointSize: Theme.barFontSize
                                font.weight: Theme.fontWeight
                                // Digits all one width, so it doesn't jiggle
                                font.features: {
                                    "tnum": 1
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: tray.count > 0
                        width: trayRow.implicitWidth + Theme.barModulePadding * 2
                        height: parent.height
                        color: Theme.barTrayColor

                        Row {
                            id: trayRow

                            x: Theme.barModulePadding
                            height: parent.height
                            spacing: Theme.barTraySpacing

                            Repeater {
                                id: tray

                                model: SystemTray.items.values.filter(item => item.status !== Status.Passive)

                                BarModule {
                                    id: trayItem

                                    required property SystemTrayItem modelData

                                    text: modelData.id || " "
                                    tooltip: modelData.tooltipTitle || modelData.title
                                    leftPadding: 0
                                    rightPadding: 0
                                    label.visible: false
                                    contentWidth: Theme.barTrayIconSize

                                    onClicked: button => {
                                        if (button === Qt.MiddleButton) {
                                            modelData.secondaryActivate();
                                        } else if (button === Qt.RightButton || modelData.onlyMenu) {
                                            if (modelData.hasMenu)
                                                root.shell?.openTrayMenu(modelData.menu, window.modelData, trayItem.mapToItem(null, trayItem.width / 2, 0).x);
                                        } else {
                                            modelData.activate();
                                        }
                                    }
                                    onScrolled: steps => modelData.scroll(steps * 120, false)

                                    IconImage {
                                        anchors.centerIn: parent
                                        implicitSize: Theme.barTrayIconSize
                                        source: trayItem.modelData.icon
                                    }
                                }
                            }
                        }
                    }

                    BarModule {
                        id: toolbox

                        text: Theme.barToolboxIcon
                        tooltip: "Toolbox"

                        onClicked: button => {
                            if (button === Qt.LeftButton)
                                root.openAt(toolbox, window.modelData, "toolbox toggleToolboxAtPointer");
                        }
                    }

                    // A music note while something plays. Click opens the
                    // sound panel, right-click mutes, scrolling changes it by 1%
                    BarModule {
                        id: volumeModule

                        readonly property int percent: Math.round(root.volume * 100)
                        // Spacing after each glyph tuned so they look even
                        readonly property string icon: root.playing && !root.muted ? Theme.musicIcon + " " : root.muted ? Theme.volumeMutedIcon + " " : percent >= 51 ? Theme.volumeHighIcon + "  " : Theme.volumeLowIcon + " "

                        text: root.sink ? icon + percent + "%" : ""
                        textColor: Theme.volumeColor(root.volume, root.muted)

                        onClicked: button => {
                            if (button === Qt.LeftButton)
                                root.openAt(volumeModule, window.modelData, "controlPanel toggleControlPanelAtPointer");
                            else if (button === Qt.RightButton && root.sink?.audio)
                                root.sink.audio.muted = !root.sink.audio.muted;
                        }
                        onScrolled: steps => root.setVolume(steps)
                    }

                    BarModule {
                        text: stats.backlight >= 0 ? Theme.barBacklightIcon + " " + stats.backlight + "%" : ""

                        onScrolled: steps => Quickshell.execDetached(["brightnessctl", "--min-val=1", "-q", "set", Math.abs(steps) + "%" + (steps > 0 ? "+" : "-")])
                    }

                    // Click starts or pauses, right-click resets, middle skips
                    BarModule {
                        readonly property bool paused: !(root.pomodoro?.running ?? false)

                        text: root.pomodoro && !root.pomodoro.idle ? (root.pomodoro.phase === "focus" ? Theme.pomodoroIcon : Theme.pomodoroBreakIcon) + " " + root.pomodoro.clock : ""
                        textColor: paused ? Theme.barFadedColor : root.pomodoro?.phase === "focus" ? Theme.textColor : Theme.pomodoroBreakColor
                        tooltip: root.pomodoro ? root.pomodoro.label + (paused ? " (paused)" : "") : ""

                        onClicked: button => {
                            if (button === Qt.LeftButton)
                                root.pomodoro.toggle();
                            else if (button === Qt.RightButton)
                                root.pomodoro.reset();
                            else
                                root.pomodoro.skip();
                        }
                    }

                    BarModule {
                        id: network

                        readonly property int strength: {
                            const strength = root.wifiNetwork?.signalStrength ?? 0;
                            return Math.round(strength > 1 ? strength : strength * 100);
                        }
                        readonly property string traffic: `\n${stats.networkAddress}\n↓ ${stats.rate(stats.download)}  ↑ ${stats.rate(stats.upload)}`

                        text: root.wiredDevice ? Theme.barEthernetIcon : root.wifiNetwork ? Theme.wifiStrengthIcons[Math.max(0, Math.min(3, Math.floor(strength / 25)))] : Theme.wifiOffIcon
                        textColor: root.wiredDevice || root.wifiNetwork ? Theme.textColor : Theme.barOffColor
                        tooltip: {
                            if (root.wiredDevice)
                                return "Ethernet" + traffic;
                            if (root.wifiNetwork)
                                return `${root.wifiNetwork.name}  ${strength}%` + traffic;
                            return Networking.wifiEnabled ? "Not connected" : "Wi-Fi off";
                        }

                        onClicked: button => {
                            if (button === Qt.LeftButton)
                                root.openAt(network, window.modelData, "controlPanel openSectionAtPointer Network");
                        }
                    }

                    // Right-click opens Blueman
                    BarModule {
                        id: bluetooth

                        readonly property bool on: root.adapter?.enabled ?? false

                        text: !root.adapter ? "" : !on ? Theme.bluetoothOffIcon : root.bluetoothConnected.length > 0 ? Theme.bluetoothConnectedIcon : Theme.bluetoothIcon
                        textColor: on ? Theme.textColor : Theme.barOffColor
                        tooltip: {
                            if (!root.adapter)
                                return "";
                            if (!on)
                                return "Bluetooth off";
                            const connected = root.bluetoothConnected;
                            if (connected.length === 0)
                                return `${root.adapter.name}: on, no devices connected`;
                            return `${root.adapter.name}: ${connected.length} connected\n` + connected.map(device => device.name + (device.batteryAvailable ? `  ${Math.round(device.battery * 100)}%` : "")).join("\n");
                        }

                        onClicked: button => {
                            if (button === Qt.LeftButton)
                                root.openAt(bluetooth, window.modelData, "controlPanel openSectionAtPointer Bluetooth");
                            else if (button === Qt.RightButton)
                                Quickshell.execDetached(["blueman-manager"]);
                        }
                    }

                    // An accent dot while unread. Right-click toggles do not
                    // disturb
                    BarModule {
                        id: bell

                        readonly property bool doNotDisturb: root.notifications?.doNotDisturb ?? false
                        readonly property int unread: root.notifications?.unread ?? 0

                        text: doNotDisturb ? Theme.doNotDisturbIcon : unread > 0 ? Theme.bellUnreadIcon : Theme.bellIcon
                        textColor: doNotDisturb ? Theme.barFadedColor : Theme.textColor
                        contentWidth: bell.label.implicitWidth + (unreadDot.visible ? unreadDot.implicitWidth : 0)

                        onClicked: button => {
                            if (button === Qt.LeftButton)
                                root.openAt(bell, window.modelData, "notificationCenter toggleNotificationCenterAtPointer");
                            else if (button === Qt.RightButton && root.notifications)
                                root.notifications.doNotDisturb = !root.notifications.doNotDisturb;
                        }

                        Text {
                            id: unreadDot

                            visible: !bell.doNotDisturb && bell.unread > 0
                            anchors.left: bell.label.right
                            anchors.top: bell.label.top
                            text: "●"
                            color: Theme.accentColor
                            font.family: Theme.barFontFamily
                            font.pointSize: Theme.barFontSize * 0.7
                        }
                    }

                    // Two lines, after a divider
                    BarModule {
                        id: clock

                        text: Qt.formatTime(clockTime.date, "HH:mm")
                        tooltip: Qt.formatDate(clockTime.date, "dddd, dd MMMM yyyy")
                        label.visible: false
                        contentWidth: clockLines.implicitWidth

                        onClicked: button => {
                            if (button === Qt.LeftButton)
                                root.openAt(clock, window.modelData, "datePanel toggleDatePanelAtPointer");
                        }

                        SystemClock {
                            id: clockTime
                            precision: SystemClock.Minutes
                        }

                        Rectangle {
                            width: 1
                            height: parent.height / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.barDividerColor
                        }

                        Column {
                            id: clockLines

                            x: clock.leftPadding
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: -3

                            Text {
                                text: clock.text
                                color: Theme.textColor
                                font.family: Theme.barFontFamily
                                font.pointSize: 10
                                font.weight: Font.DemiBold
                            }

                            Text {
                                text: Qt.formatDate(clockTime.date, "ddd MMM d")
                                color: Theme.textColor
                                opacity: 0.8
                                font.family: Theme.barFontFamily
                                font.pointSize: 7.5
                                font.weight: Theme.fontWeight
                            }
                        }
                    }
                }
            }
        }
    }
}
