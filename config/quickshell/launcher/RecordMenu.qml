pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs

// Sets up a screen recording, toggled by ~/.local/bin/record-menu: a row each
// for the sound, the camera (with its shape while it's on), which camera
// (while it's on and there's more than one) and the frame rate, then Record, which runs ~/.local/bin/record-toggle with them. Every
// setting is remembered for next time. The mic sounds show the mic's level,
// so a dead mic shows before recording. While the camera is on its bubble
// (CameraWidget.qml) shows, so it can be placed first. Up/Down move between
// rows, Left/Right change one (on the camera row, its shape); 1-4 pick a
// sound, Space the camera, R its shape, F the frame rate, Enter records.
// Opened while recording (live), it changes the running recording's sound
// and camera on the spot; the frame rate is fixed then, and Record is Stop.
Scope {
    id: root

    property bool open: false
    // Opened while recording
    property bool live: false
    // `value` is the option given to record-toggle
    readonly property list<var> sounds: [
        {
            value: "none",
            label: "No Sound",
            icon: Theme.recordNoSoundIcon
        },
        {
            value: "desktop",
            label: "Desktop",
            icon: Theme.recordDesktopIcon
        },
        {
            value: "mic",
            label: "Mic",
            icon: Theme.recordMicIcon,
            mic: true
        },
        {
            value: "both",
            label: "Desktop + Mic",
            icon: Theme.recordBothIcon,
            mic: true
        }
    ]
    readonly property list<var> shapes: [
        {
            value: "circle",
            label: "Circle",
            icon: Theme.recordCircleIcon
        },
        {
            value: "landscape",
            label: "Landscape",
            icon: Theme.recordRectangleIcon
        },
        {
            value: "portrait",
            label: "Portrait",
            icon: Theme.recordRectangleIcon,
            rotation: 90
        }
    ]
    // Frame rates given to record-toggle's --fps; 0 is uncapped (up to the
    // refresh rate, which sites such as X refuse over 60)
    readonly property list<var> frameRates: [30, 60, 120, 0].map(rate => ({
                value: rate,
                label: rate > 0 ? String(rate) : "Max"
            }))
    readonly property list<var> settings: [
        {
            id: "sound",
            label: "Sound",
            options: sounds
        },
        {
            id: "camera",
            label: "Camera",
            options: shapes
        },
        {
            id: "device",
            label: "Device",
            // "Integrated Camera: Integrated C" reads as "Integrated Camera"
            options: camera.devices.map(device => ({
                        value: device.description,
                        label: device.description.split(":")[0]
                    }))
        },
        {
            id: "fps",
            label: "FPS",
            options: frameRates
        }
    ]
    // The focused row; settings.length is the Record button
    property int current: 0
    // desktop until one is picked
    property string chosen: "desktop"
    property bool withCamera: cameraFile.text().trim() !== "off"
    // 60 until one is picked
    property int fps: {
        const saved = parseInt(fpsFile.text().trim());
        return frameRates.some(rate => rate.value === saved) ? saved : 60;
    }
    // What Record will do, shown on it
    readonly property string summary: {
        const parts = [sounds.find(sound => sound.value === chosen)?.label ?? "", fps > 0 ? fps + " fps" : "Max fps"];
        if (withCamera)
            parts.push("Camera");
        return parts.join("  ·  ");
    }
    // The webcam bubble (CameraWidget.qml), shown while the menu is open so it
    // can be placed before recording
    required property var camera
    // Whether the menu showed the bubble, so closing it without recording
    // hides only what the menu showed
    property bool shownCamera: false
    // Set when a recording starts: record-toggle hides the bubble then
    property bool recording: false

    readonly property PwNode mic: Pipewire.defaultAudioSource
    // 0-1 across the meter's range
    readonly property real micLevel: {
        const db = 20 * Math.log10(Math.max(micPeak.peak, 1e-6));
        return Math.max(0, Math.min(1, (db + Theme.recordMeterFloor) / Theme.recordMeterFloor));
    }

    // The camera row picks the shape
    function valueOf(id: string): var {
        switch (id) {
        case "sound":
            return chosen;
        case "camera":
            return camera.shape;
        case "device":
            return camera.currentDevice;
        case "fps":
            return fps;
        }
    }

    function choose(id: string, value: var): void {
        switch (id) {
        case "sound":
            chosen = value;
            lastFile.setText(value);
            if (live)
                Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/record-toggle", "--live-sound=" + value]);
            break;
        case "camera":
            camera.setShape(value);
            break;
        case "device":
            camera.setDevice(value);
            break;
        case "fps":
            fps = value;
            fpsFile.setText(String(value));
            break;
        }
    }

    function setting(id: string): var {
        return settings.find(setting => setting.id === id);
    }

    // The camera choice only shows with the camera on and a choice to make.
    // The Record button (undefined) always shows
    function shown(setting: var): bool {
        return setting?.id !== "device" || (withCamera && setting.options.length > 1);
    }

    // wf-recorder's frame rate is set when it starts
    function editable(setting: var): bool {
        return !live || setting?.id !== "fps";
    }

    // Focuses the next (1) or previous (-1) row showing that can change,
    // wrapping
    function move(delta: int): void {
        const count = settings.length + 1;
        let next = current;
        do
            next = (next + delta + count) % count;
        while (!shown(settings[next]) || !editable(settings[next]))
        current = next;
    }

    function setCamera(on: bool): void {
        withCamera = on;
        cameraFile.setText(on ? "on" : "off");
        camera.open = on;
        shownCamera = on;
        // Off the camera choice as it hides
        if (!shown(settings[current]))
            current = settings.indexOf(setting("camera"));
    }

    // Moves a setting to its next (1) or previous (-1) option, wrapping. The
    // camera's shape turns it on first
    function step(setting: var, delta: int): void {
        if (!editable(setting))
            return;
        if (setting.id === "camera" && !withCamera) {
            setCamera(true);
            return;
        }
        const options = setting.options;
        const index = options.findIndex(option => option.value === valueOf(setting.id));
        choose(setting.id, options[(index + delta + options.length) % options.length].value);
    }

    // Or stops the running one, when live
    function record(): void {
        if (live) {
            open = false;
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/record-toggle"]);
            return;
        }
        recording = true;
        open = false;
        const args = [Quickshell.env("HOME") + "/.local/bin/record-toggle", "--" + chosen, "--fps=" + fps];
        if (withCamera)
            args.push("--camera");
        Quickshell.execDetached(args);
    }

    // Whether to record with the camera: "on" or "off"
    FileView {
        id: cameraFile

        path: Quickshell.statePath("record-camera")
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: fpsFile

        path: Quickshell.statePath("record-fps")
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: lastFile

        path: Quickshell.statePath("record-sound")
        blockLoading: true
        printErrors: false
    }

    PwObjectTracker {
        objects: root.open && root.mic ? [root.mic] : []
    }

    PwNodePeakMonitor {
        id: micPeak

        node: root.mic
        enabled: root.open
    }

    RecordCountdown {
        id: countdownOverlay
    }

    // Also called over the launcher socket (shell.qml)
    property alias ipc: ipcHandler

    onOpenChanged: {
        if (!open) {
            if (shownCamera && !recording)
                camera.open = false;
            shownCamera = false;
            recording = false;
            // Set again by toggleLiveMenu; others open it to start one
            live = false;
            return;
        }

        if (live) {
            // What's being recorded; the bubble stays as left on closing
            withCamera = camera.open;
        } else if (withCamera && !camera.open) {
            camera.open = true;
            shownCamera = true;
        }
        chosen = lastFile.text().trim() || "desktop";
        // On Record (or Stop), so Enter records with last time's settings
        current = settings.length;
        layout.forceActiveFocus();
        panel.appear();
    }

    IpcHandler {
        id: ipcHandler
        target: "record"

        function toggleRecordMenu(): void {
            root.open = !root.open;
        }

        // ~/.local/bin/record-menu, while recording
        function toggleLiveMenu(): void {
            if (!root.open)
                root.live = true;
            root.open = !root.open;
        }

        // record-toggle, once the area is picked: "<pid> <x>,<y> <w>x<h>".
        // The pid gets SIGUSR1 if it's cancelled. One argument, as the
        // launcher socket passes one
        function countdown(call: string): void {
            const space = call.indexOf(" ");
            countdownOverlay.start(call.slice(space + 1), call.slice(0, space));
        }
    }

    // Widest row label, so the controls line up
    FontMetrics {
        id: labels

        readonly property real widest: Math.max(...root.settings.map(setting => labels.advanceWidth(setting.label)))

        font.family: Theme.fontFamily
        font.pixelSize: Theme.powerFontSize
        font.weight: Theme.selectedWeight
    }

    // A setting's options in one track, the picked one on a pill that slides
    // between them
    component SegmentedControl: Rectangle {
        id: control

        required property var setting
        // Icons only, for the shapes
        property bool iconsOnly: false
        readonly property int chosenIndex: setting.options.findIndex(option => option.value === root.valueOf(setting.id))
        // Read again as the segments are made
        readonly property Item chosenItem: segments.count > chosenIndex ? segments.itemAt(chosenIndex) : null

        width: segmentRow.width + Theme.recordTrackPadding * 2
        height: Theme.recordSegmentHeight + Theme.recordTrackPadding * 2
        radius: Theme.cornerRadius + Theme.recordTrackPadding
        color: Theme.keyColor

        Rectangle {
            visible: control.chosenItem !== null
            x: Theme.recordTrackPadding + (control.chosenItem?.x ?? 0)
            y: Theme.recordTrackPadding
            width: control.chosenItem?.width ?? 0
            height: Theme.recordSegmentHeight
            radius: Theme.cornerRadius
            color: Theme.recordChosenColor

            Behavior on x {
                NumberAnimation {
                    duration: Theme.animationDuration
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on width {
                NumberAnimation {
                    duration: Theme.animationDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        Row {
            id: segmentRow

            x: Theme.recordTrackPadding
            y: Theme.recordTrackPadding

            Repeater {
                id: segments

                model: control.setting.options

                Item {
                    id: segment

                    required property var modelData
                    required property int index
                    readonly property bool chosen: control.chosenIndex === index
                    readonly property color textColor: chosen || hover.containsMouse ? Theme.selectedColor : Theme.unselectedColor

                    width: segmentContent.width + Theme.rowPadding * (control.iconsOnly ? 1.5 : 2)
                    height: Theme.recordSegmentHeight

                    MouseArea {
                        id: hover

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.choose(control.setting.id, segment.modelData.value)
                    }

                    Row {
                        id: segmentContent

                        anchors.centerIn: parent
                        spacing: Theme.rowSpacing + 2

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: segment.modelData.icon !== undefined
                            text: segment.modelData.icon ?? ""
                            rotation: segment.modelData.rotation ?? 0
                            color: segment.textColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.powerFontSize + 3
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !control.iconsOnly
                            text: segment.modelData.label
                            color: segment.textColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.powerFontSize
                            font.weight: segment.chosen ? Theme.selectedWeight : Theme.unselectedWeight
                        }
                    }

                    // The mic's level, on the sounds that record it
                    Rectangle {
                        visible: segment.modelData.mic ?? false
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: segmentContent.width
                        height: Theme.recordMeterHeight
                        radius: height / 2
                        color: Theme.dividerColor

                        Rectangle {
                            width: parent.width * root.micLevel
                            height: parent.height
                            radius: parent.radius
                            color: root.micLevel > 0.95 ? Theme.accentColor : Theme.toggleOnColor

                            Behavior on width {
                                NumberAnimation {
                                    duration: 80
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // A label, then its control
    component SettingRow: Rectangle {
        id: row

        required property int index
        readonly property var setting: root.settings[index]
        readonly property bool focused: root.current === index
        default property alias control: controls.data
        readonly property real naturalWidth: Math.ceil(labels.widest) + Theme.rowPadding * 4 + controls.width

        enabled: root.editable(setting)
        opacity: enabled ? 1 : 0.35
        width: layout.width
        height: Theme.recordSegmentHeight + Theme.recordTrackPadding * 2 + Theme.powerTilePadding
        radius: Theme.cornerRadius
        color: row.focused ? Theme.currentRowColor : "transparent"

        // Behind the controls, so they still take clicks
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: root.current = row.index
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.rowPadding
            text: row.setting.label
            color: row.focused ? Theme.selectedColor : Theme.dimColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.powerFontSize
            font.weight: Theme.selectedWeight
        }

        Row {
            id: controls

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Theme.rowPadding
            spacing: Theme.rowPadding * 1.5
        }
    }

    component Hint: Row {
        id: hint

        required property string key
        required property string label

        spacing: Theme.keySpacing

        KeyCap {
            anchors.verticalCenter: parent.verticalCenter
            text: hint.key
            fontSize: Theme.sectionFontSize
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: hint.label
            color: Theme.dimColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.sectionFontSize
        }
    }

    PanelWindow { // qmllint disable uncreatable-type
        // Follows focus: a mapped surface stays on the monitor it was made on
        screen: Compositor.focusedScreen()
        // Stays mapped while closed, just empty and click-through: mapping a
        // surface again took ~40 ms each open
        visible: !Compositor.remapping
        mask: Region {
            item: root.open ? panel : null
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: panel.width
        implicitHeight: panel.height

        // No shadow, like the bar. Only the bottom anchored: centred across
        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors.bottom: true
        margins.bottom: Theme.centredGap

        Glass {
            id: panel

            visible: root.open
            floating: true
            color: Theme.powerColor
            width: layout.width + Theme.powerPanelPadding * 2
            height: layout.height + Theme.powerPanelPadding * 2

            Column {
                id: layout

                anchors.centerIn: parent
                // The camera rows as wide as with the camera on, so turning it
                // on doesn't resize the panel
                width: Math.max(soundRow.naturalWidth, cameraRow.naturalWidth + (root.withCamera ? 0 : shapeControl.width + Theme.rowPadding * 1.5), deviceRow.naturalWidth, fpsRow.naturalWidth, hints.width)
                spacing: Theme.rowSpacing

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const setting = root.settings[root.current];

                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backspace) {
                        root.open = false;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.record();
                    } else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.sounds.length) {
                        root.choose("sound", root.sounds[event.key - Qt.Key_1].value);
                    } else if (event.key === Qt.Key_Space || event.key === Qt.Key_C) {
                        root.setCamera(!root.withCamera);
                    } else if (event.key === Qt.Key_R) {
                        if (root.withCamera)
                            root.step(root.setting("camera"), 1);
                    } else if (event.key === Qt.Key_F) {
                        root.step(root.setting("fps"), 1);
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        if (setting)
                            root.step(setting, 1);
                    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        if (setting)
                            root.step(setting, -1);
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.key === Qt.Key_Tab || (ctrl && event.key === Qt.Key_N)) {
                        root.move(1);
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.key === Qt.Key_Backtab || (ctrl && event.key === Qt.Key_P)) {
                        root.move(-1);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                SettingRow {
                    id: soundRow

                    index: 0

                    SegmentedControl {
                        setting: soundRow.setting
                    }
                }

                SettingRow {
                    id: cameraRow

                    index: 1

                    // Left of the switch, so the switch stays put at the edge
                    SegmentedControl {
                        id: shapeControl

                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.withCamera
                        setting: cameraRow.setting
                        iconsOnly: true
                    }

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.toggleWidth
                        height: Theme.recordSegmentHeight

                        Toggle {
                            anchors.centerIn: parent
                            checked: root.withCamera
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Theme.rowSpacing
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setCamera(!root.withCamera)
                        }
                    }
                }

                SettingRow {
                    id: deviceRow

                    index: 2
                    visible: root.shown(setting)

                    SegmentedControl {
                        setting: deviceRow.setting
                    }
                }

                SettingRow {
                    id: fpsRow

                    index: 3

                    SegmentedControl {
                        setting: fpsRow.setting
                    }
                }

                Item {
                    width: parent.width
                    height: Theme.rowSpacing
                }

                Rectangle {
                    id: recordButton

                    readonly property bool focused: root.current === root.settings.length
                    readonly property color tint: Theme.closeColor

                    width: parent.width
                    height: Theme.recordButtonHeight
                    radius: Theme.cornerRadius
                    color: Qt.rgba(tint.r, tint.g, tint.b, focused ? 0.32 : recordHover.containsMouse ? 0.24 : 0.16)
                    border.width: focused ? 1 : 0
                    border.color: Qt.rgba(tint.r, tint.g, tint.b, 0.6)

                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.animationDuration
                        }
                    }

                    MouseArea {
                        id: recordHover

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: root.current = root.settings.length
                        onClicked: root.record()
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.rowPadding

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.live ? Theme.recordStopIcon : Theme.toolboxRecordIcon
                            color: recordButton.tint
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.powerFontSize + 3
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.live ? "Stop" : "Record"
                            color: Theme.selectedColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.powerFontSize + 1
                            font.weight: Theme.selectedWeight
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.summary
                            color: Theme.keyTextColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.sectionFontSize
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: Theme.rowSpacing
                }

                Row {
                    id: hints

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.rowPadding * 2

                    // Which mic the mic sounds record
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.recordMicIcon + " " + (root.mic ? (root.mic.nickname || root.mic.description || root.mic.name) : "No mic")
                        color: Theme.dimColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.sectionFontSize
                    }

                    Hint {
                        key: "↑↓"
                        label: "setting"
                    }

                    Hint {
                        key: "←→"
                        label: "change"
                    }

                    Hint {
                        key: "Space"
                        label: "camera"
                    }

                    Hint {
                        key: "Enter"
                        label: root.live ? "stop" : "record"
                    }

                    Hint {
                        key: "Esc"
                        label: "close"
                    }
                }
            }
        }
    }
}
