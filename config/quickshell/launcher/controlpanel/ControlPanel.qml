pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs
import qs.services
import qs.widgets

// The bar's sound, Wi-Fi and bluetooth popup. The main view has each section's
// slider or switch; lists (audio devices, networks, bluetooth devices) and
// details open as pages. Toggled by ~/.local/bin/control-panel; `--pointer`
// centres it over the clicked bar module.
Scope {
    id: root

    property bool open: false
    property int current: 0
    // Page opened from the bar ("Network", "Bluetooth"); going back from it
    // closes the panel
    property string entryPage: ""

    // -1 until shell.qml reports the pointer
    property bool atPointer: false
    property real pointerX: -1
    property var pointerScreen: null
    property bool placeWaited: false
    readonly property bool placed: !atPointer || pointerX >= 0 || placeWaited

    // One that's playing, else one with a track
    readonly property MprisPlayer player: {
        const players = Mpris.players.values.filter(player => player.trackTitle || player.isPlaying);
        return players.find(player => player.isPlaying) ?? players[0] ?? null;
    }

    readonly property list<PwNode> sinks: Pipewire.nodes.values.filter(node => node.type === PwNodeType.AudioSink)
    readonly property list<PwNode> sources: Pipewire.nodes.values.filter(node => node.type === PwNodeType.AudioSource)

    readonly property NetworkDevice wifiDevice: Networking.devices.values.find(device => device.type === DeviceType.Wifi) ?? null
    readonly property list<NetworkDevice> wiredDevices: Networking.devices.values.filter(device => device.type === DeviceType.Wired && device.hasLink)
    // Connected first, then saved ones
    readonly property list<WifiNetwork> networks: {
        if (!wifiDevice || !Networking.wifiEnabled)
            return [];
        const rank = network => network.connected ? 0 : network.known ? 1 : 2;
        const networks = wifiDevice.networks.values.filter(network => network.name);
        return networks.sort((a, b) => rank(a) - rank(b) || b.signalStrength - a.signalStrength).slice(0, Theme.maxNetworks);
    }
    // Network the password prompt is for, and recent failures (name ->
    // ConnectionFailReason)
    property WifiNetwork passwordFor: null
    property var failures: ({})
    property string newPassword: ""
    property bool passwordBusy: false
    property string passwordError: ""

    // "" for the main view; also "Details" and "Join" under the Network page
    property string page: ""

    property WifiNetwork detailsFor: null
    property var details: ({})
    property BluetoothDevice deviceFor: null
    property var audio: ({})
    property string joinName: ""
    property string joinPassword: ""
    property bool joinBusy: false
    property string joinError: ""

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool bluetoothOn: adapter?.enabled ?? false
    // Paired devices, plus named ones nearby while searching; connected first
    readonly property list<BluetoothDevice> bluetoothDevices: {
        if (!bluetoothOn)
            return [];
        const searching = adapter.discovering;
        const devices = adapter.devices.values.filter(device => device.paired || (searching && device.deviceName));
        const rank = device => device.connected ? 0 : device.paired ? 1 : 2;
        return devices.sort((a, b) => rank(a) - rank(b) || a.name.localeCompare(b.name));
    }

    // One per row: { kind, section, list, ... }. List rows are on the section's
    // page, the rest on the main view.
    readonly property var rows: {
        const rows = [];
        const add = (section, devices, fallback) => {
            if (fallback)
                rows.push({
                    section: section,
                    kind: "volume",
                    node: fallback
                });
            for (const node of devices)
                rows.push({
                    section: section,
                    kind: "device",
                    list: true,
                    node: node
                });
        };
        if (player)
            rows.push({
                section: "Now playing",
                kind: "media",
                player: player
            });
        add("Output", sinks, Pipewire.defaultAudioSink);
        add("Input", sources, Pipewire.defaultAudioSource);
        if (wifiDevice) {
            rows.push({
                section: "Network",
                kind: "wifi",
                list: true
            });
        }
        for (const device of wiredDevices)
            rows.push({
                section: "Network",
                kind: "wired",
                list: true,
                device: device
            });
        if (wifiDevice) {
            for (const network of networks)
                rows.push({
                    section: "Network",
                    kind: "network",
                    list: true,
                    network: network
                });
            if (Networking.wifiEnabled)
                rows.push({
                    section: "Network",
                    kind: "join",
                    list: true
                });
        }
        if (adapter) {
            rows.push({
                section: "Bluetooth",
                kind: "bluetooth",
                list: true
            });
            for (const device of bluetoothDevices)
                rows.push({
                    section: "Bluetooth",
                    kind: "bluetoothDevice",
                    list: true,
                    device: device
                });
        }
        if (page === "Details")
            return detailsRows();
        if (page === "Device")
            return deviceRows();
        if (page === "Join")
            return joinRows();
        return rows.filter(row => page === "" ? !row.list : row.section === page && row.list);
    }

    function detailsRows() {
        const network = detailsFor;
        if (!network)
            return [];
        const section = network.name;
        const rows = [];
        const info = (label, value) => {
            if (value)
                rows.push({
                    section: section,
                    kind: "info",
                    list: true,
                    label: label,
                    value: String(value)
                });
        };
        info("Status", network.connected ? "Connected" : network.known ? "Saved" : "Not saved");
        info("Signal", details.signal !== undefined ? details.signal + "%" : "");
        info("Band", root.band(details.frequency));
        info("Link speed", details.rate);
        info("Security", details.security);
        info("IP address", details.ip);
        info("Gateway", details.gateway);
        info("DNS", (details.dns ?? []).join(", "));
        info("MAC address", details.mac);
        rows.push({
            section: section,
            kind: "connect",
            list: true,
            network: network
        });
        if (details.uuid)
            rows.push({
                section: section,
                kind: "autoconnect",
                list: true
            });
        if (network.known)
            rows.push({
                section: section,
                kind: "forget",
                list: true,
                network: network
            });
        return rows;
    }

    function deviceRows() {
        const device = deviceFor;
        if (!device)
            return [];
        const section = device.name || device.address;
        const rows = [];
        const info = (label, value) => {
            if (value)
                rows.push({
                    section: section,
                    kind: "info",
                    list: true,
                    label: label,
                    value: String(value)
                });
        };
        info("Type", root.deviceType(device.icon));
        info("Status", device.connected ? "Connected" : device.paired ? "Paired" : "Not paired");
        info("Battery", device.batteryAvailable ? Math.round(device.battery * 100) + "%" : "");
        info("Address", device.address);
        rows.push({
            section: section,
            kind: "btConnect",
            list: true,
            device: device
        });
        if (device.paired)
            rows.push({
                section: section,
                kind: "btTrust",
                list: true,
                device: device
            });
        if (device.connected)
            for (const profile of audio.profiles ?? [])
                rows.push({
                    section: section,
                    kind: "profile",
                    list: true,
                    device: device,
                    name: profile.name,
                    label: profile.label,
                    codec: profile.codec
                });
        if (device.paired)
            rows.push({
                section: section,
                kind: "btForget",
                list: true,
                device: device
            });
        return rows;
    }

    // "audio-headset" -> "Headphones"
    function deviceType(icon) {
        const types = {
            "audio-headset": "Headphones",
            "audio-headphones": "Headphones",
            "audio-card": "Speaker",
            "input-keyboard": "Keyboard",
            "input-mouse": "Mouse",
            "input-tablet": "Tablet",
            "input-gaming": "Game controller",
            "phone": "Phone",
            "computer": "Computer",
            "camera-video": "Camera",
            "printer": "Printer"
        };
        return types[icon] ?? "";
    }

    function openDevice(device) {
        deviceFor = device;
        audio = {};
        page = "Device";
        current = 0;
        root.loadAudio();
        pageSlide.direction = 1;
        pageSlide.restart();
    }

    function loadAudio() {
        if (!deviceFor?.connected)
            return;
        audioProcess.command = [Theme.bluetoothAudio, "show", deviceFor.address];
        audioProcess.running = true;
    }

    function setProfile(name) {
        audio = Object.assign({}, audio, {
            active: name
        });
        Quickshell.execDetached([Theme.bluetoothAudio, "set", deviceFor.address, name]);
    }

    function joinRows() {
        const section = "Join other network";
        const rows = [
            {
                section: section,
                kind: "joinName",
                list: true
            },
            {
                section: section,
                kind: "joinPassword",
                list: true
            }
        ];
        if (joinBusy || joinError)
            rows.push({
                section: section,
                kind: "joinStatus",
                list: true,
                error: !joinBusy
            });
        return rows;
    }

    // "5280 MHz" -> "5 GHz"
    function band(frequency) {
        const mhz = parseInt(frequency ?? "");
        if (!mhz)
            return "";
        return mhz >= 5925 ? "6 GHz" : mhz >= 4900 ? "5 GHz" : "2.4 GHz";
    }

    function openDetails(network) {
        detailsFor = network;
        details = {};
        page = "Details";
        current = 0;
        root.loadDetails();
        pageSlide.direction = 1;
        pageSlide.restart();
    }

    function loadDetails() {
        if (!detailsFor)
            return;
        detailsProcess.command = [Theme.networkInfo, "show", detailsFor.name];
        detailsProcess.running = true;
    }

    function setAutoconnect(on) {
        if (!details.uuid)
            return;
        details = Object.assign({}, details, {
            autoconnect: on
        });
        Quickshell.execDetached([Theme.networkInfo, "autoconnect", details.uuid, on ? "yes" : "no"]);
    }

    function openJoin() {
        joinName = "";
        joinPassword = "";
        joinError = "";
        page = "Join";
        current = 0;
        pageSlide.direction = 1;
        pageSlide.restart();
    }

    function focusRow(index) {
        current = index;
        Qt.callLater(() => rowRepeater.itemAt(index)?.focusField());
    }

    function join() {
        if (!joinName || joinBusy)
            return;
        joinBusy = true;
        joinError = "";
        joinProcess.command = [Theme.networkInfo, "join", joinName];
        joinProcess.running = true;
    }

    function isSlider(row) {
        return row.kind === "volume";
    }

    // "HDMI / DisplayPort 3 Output" -> "HDMI / DisplayPort 3"
    function deviceName(node) {
        return (node.nickname || node.description || node.name).replace(/ Output$/, "");
    }

    function isDefault(node) {
        return node === Pipewire.defaultAudioSink || node === Pipewire.defaultAudioSource;
    }

    // Unmutes too
    function setVolume(row, volume) {
        row.node.audio.muted = false;
        row.node.audio.volume = volume;
    }

    function toggleMute(row) {
        row.node.audio.muted = !row.node.audio.muted;
    }

    // Never pushes past 100%, but leaves a volume already past it there
    function step(row, direction) {
        const value = row.node.audio.volume;
        const next = Math.round((value + direction * Theme.volumeStep) * 100) / 100;
        root.setVolume(row, Math.max(0, Math.min(next, Math.max(value, 1))));
    }

    // An rfkill block can't be undone over bluez
    function toggleBluetooth() {
        if (adapter.state === BluetoothAdapterState.Blocked)
            Quickshell.execDetached(["sh", "-c", "rfkill unblock bluetooth && sleep 1 && bluetoothctl power on"]);
        else
            adapter.enabled = !adapter.enabled;
    }

    // Connected devices are trusted, so they reconnect by themselves
    function toggleDevice(device) {
        if (device.pairing) {
            device.cancelPair();
        } else if (!device.paired) {
            device.pair();
        } else if (device.connected) {
            device.disconnect();
        } else {
            device.trusted = true;
            device.connect();
        }
    }

    function networkIcon(network) {
        const strength = network.signalStrength > 1 ? network.signalStrength / 100 : network.signalStrength;
        const bars = Math.max(0, Math.min(3, Math.floor(strength * 4)));
        return Theme.wifiStrengthIcons[bars];
    }

    function wifiGlyph() {
        if (!Networking.wifiEnabled)
            return Theme.wifiOffIcon;
        const connected = wifiDevice?.networks.values.find(network => network.connected);
        return connected ? root.networkIcon(connected) : Theme.wifiStrengthIcons[0];
    }

    function isSecured(network) {
        return network.security !== WifiSecurityType.Open && network.security !== WifiSecurityType.Owe;
    }

    function setFailure(network, reason) {
        const failures = Object.assign({}, root.failures);
        if (reason === undefined)
            delete failures[network.name];
        else
            failures[network.name] = reason;
        root.failures = failures;
    }

    function toggleNetwork(network) {
        root.setFailure(network);
        if (network.connected) {
            network.disconnect();
        } else if (network.known || !root.isSecured(network)) {
            network.connect();
        } else {
            root.askPassword(network);
        }
    }

    function askPassword(network) {
        if (passwordFor !== network)
            passwordError = "";
        passwordFor = network;
    }

    // Through network-info, which hands the password to iwd when it's the
    // backend
    function submitPassword(password) {
        const network = passwordFor;
        if (!network || !password || passwordBusy)
            return;
        root.setFailure(network);
        passwordError = "";
        passwordBusy = true;
        newPassword = password;
        passwordProcess.command = [Theme.networkInfo, "connect", network.name];
        passwordProcess.running = true;
    }

    // Asks for a password when one is missing or wrong, panel open or not
    function connectionFailed(network, reason) {
        root.setFailure(network, reason);
        if (reason !== ConnectionFailReason.NoSecrets && reason !== ConnectionFailReason.WifiAuthTimeout)
            return;
        root.askPassword(network);
    }

    function cancelPassword() {
        if (passwordBusy)
            return;
        passwordFor = null;
        passwordError = "";
        list.forceActiveFocus();
    }

    function hasPage(section) {
        if (section === "Output" || section === "Input")
            return true;
        if (section === "Network")
            return wifiDevice !== null || wiredDevices.length > 0;
        if (section === "Bluetooth")
            return adapter !== null;
        return false;
    }

    function openPage(section) {
        if (!root.hasPage(section))
            return;
        page = section;
        current = 0;
        pageSlide.direction = 1;
        pageSlide.restart();
    }

    function closePage() {
        const section = page;
        // Opened on this page from the bar: nothing to go back to
        if (section === entryPage) {
            open = false;
            return;
        }
        if (section === "Device") {
            const device = deviceFor;
            page = "Bluetooth";
            deviceFor = null;
            current = Math.max(0, rows.findIndex(row => row.device === device));
        } else if (section === "Details" || section === "Join") {
            const network = detailsFor;
            page = "Network";
            detailsFor = null;
            current = Math.max(0, rows.findIndex(row => section === "Join" ? row.kind === "join" : row.network === network));
            list.forceActiveFocus();
        } else {
            page = "";
            current = Math.max(0, rows.findIndex(row => row.section === section));
        }
        pageSlide.direction = -1;
        pageSlide.restart();
    }

    function summary(section) {
        if (section === "Output")
            return Pipewire.defaultAudioSink ? root.deviceName(Pipewire.defaultAudioSink) : "";
        if (section === "Input")
            return Pipewire.defaultAudioSource ? root.deviceName(Pipewire.defaultAudioSource) : "";
        if (section === "Network")
            return wiredDevices.some(device => device.connected) ? "Ethernet" : wifiDevice?.networks.values.find(network => network.connected)?.name ?? "";
        if (section === "Bluetooth")
            return bluetoothDevices.filter(device => device.connected).map(device => device.name).join(", ");
        if (section === "Now playing") {
            // "Mozilla zen" -> "Zen"
            const name = (player?.identity ?? "").replace(/^Mozilla /, "");
            return name.charAt(0).toUpperCase() + name.slice(1);
        }
        return "";
    }

    function toggleSearch() {
        if (bluetoothOn)
            adapter.discovering = !adapter.discovering;
    }

    function activate(row) {
        if (row.kind === "media") {
            row.player.togglePlaying();
        } else if (row.kind === "device") {
            if (row.node.type === PwNodeType.AudioSink)
                Pipewire.preferredDefaultAudioSink = row.node;
            else
                Pipewire.preferredDefaultAudioSource = row.node;
        } else if (row.kind === "volume") {
            root.toggleMute(row);
        } else if (row.kind === "bluetooth") {
            root.toggleBluetooth();
        } else if (row.kind === "bluetoothDevice") {
            root.toggleDevice(row.device);
        } else if (row.kind === "wifi") {
            Networking.wifiEnabled = !Networking.wifiEnabled;
        } else if (row.kind === "network") {
            root.toggleNetwork(row.network);
        } else if (row.kind === "wired") {
            if (row.device.connected)
                row.device.disconnect();
            else
                row.device.network?.connect();
        } else if (row.kind === "join") {
            root.openJoin();
        } else if (row.kind === "connect") {
            root.toggleNetwork(row.network);
            if (row.network.connected || row.network.known || !root.isSecured(row.network))
                return;
            root.closePage();
        } else if (row.kind === "autoconnect") {
            root.setAutoconnect(!details.autoconnect);
        } else if (row.kind === "forget") {
            row.network.forget();
            root.closePage();
        } else if (row.kind === "btConnect") {
            root.toggleDevice(row.device);
        } else if (row.kind === "btTrust") {
            row.device.trusted = !row.device.trusted;
        } else if (row.kind === "profile") {
            root.setProfile(row.name);
        } else if (row.kind === "btForget") {
            row.device.forget();
            root.closePage();
        }
    }

    // Search and scan only while open
    onOpenChanged: {
        if (wifiDevice)
            wifiDevice.scannerEnabled = open;
        if (open) {
            page = "";
        } else {
            entryPage = "";
            atPointer = false;
            placeWaited = false;
            detailsFor = null;
            deviceFor = null;
            if (adapter?.discovering)
                adapter.discovering = false;
        }
    }

    // Also called over the launcher socket (shell.qml)
    property alias ipc: ipcHandler

    IpcHandler {
        id: ipcHandler
        target: "controlPanel"

        function toggleControlPanel(): void {
            root.toggleSound(false);
        }

        function toggleControlPanelAtPointer(): void {
            root.toggleSound(true);
        }

        function showControlPanel(): void {
            root.entryPage = "";
            root.page = "";
            root.open = true;
        }

        // Again on the same page closes it
        function openSection(section: string): void {
            root.toggleSection(section, false);
        }

        function openSectionAtPointer(section: string): void {
            root.toggleSection(section, true);
        }
    }

    function toggleSound(atPointer) {
        if (open && page === "") {
            open = false;
            return;
        }
        if (!open)
            root.atPointer = atPointer;
        entryPage = "";
        page = "";
        current = 0;
        open = true;
    }

    function toggleSection(section, atPointer) {
        if (open && page === section) {
            open = false;
            return;
        }
        if (!open)
            root.atPointer = atPointer;
        open = true;
        entryPage = section;
        root.openPage(section);
    }

    // Pointer not found: fall back to the right edge
    Timer {
        running: root.open && !root.placed
        interval: 500
        onTriggered: root.placeWaited = true
    }

    Process {
        id: detailsProcess

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.details = JSON.parse(text);
                } catch (error) {}
            }
        }
    }

    // Refresh while the details are open
    Timer {
        running: root.open && root.page === "Details"
        repeat: true
        interval: 4000
        onTriggered: if (!detailsProcess.running)
            root.loadDetails()
    }

    Process {
        id: audioProcess

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.audio = JSON.parse(text);
                } catch (error) {}
            }
        }
    }

    Connections {
        target: root.deviceFor

        function onConnectedChanged() {
            root.loadAudio();
        }
    }

    Timer {
        running: root.open && root.page === "Device" && (root.deviceFor?.connected ?? false)
        repeat: true
        interval: 4000
        onTriggered: if (!audioProcess.running)
            root.loadAudio()
    }

    // Every nearby network, so a saved one whose password changed asks too
    Instantiator {
        model: root.wifiDevice ? root.wifiDevice.networks.values : []

        delegate: Connections {
            required property WifiNetwork modelData

            target: modelData

            function onConnectionFailed(reason) {
                root.connectionFailed(modelData, reason);
            }

            function onConnectedChanged() {
                if (modelData.connected && root.failures[modelData.name] !== undefined)
                    root.setFailure(modelData);
            }
        }
    }

    Process {
        id: passwordProcess

        stdinEnabled: true

        onStarted: {
            write(root.newPassword + "\n");
            root.newPassword = "";
        }

        stdout: StdioCollector {
            onStreamFinished: {
                root.passwordBusy = false;
                let result = {};
                try {
                    result = JSON.parse(text);
                } catch (error) {}
                if (result.ok) {
                    root.passwordFor = null;
                    root.passwordError = "";
                    list.forceActiveFocus();
                } else {
                    root.passwordError = result.error || "Couldn't connect";
                }
            }
        }
    }

    Process {
        id: joinProcess

        stdinEnabled: true

        onStarted: {
            write(root.joinPassword + "\n");
            root.joinPassword = "";
        }

        stdout: StdioCollector {
            onStreamFinished: {
                root.joinBusy = false;
                let result = {};
                try {
                    result = JSON.parse(text);
                } catch (error) {
                    result = {
                        error: "Couldn't join"
                    };
                }
                if (result.ok) {
                    if (root.page === "Join")
                        root.closePage();
                } else {
                    root.joinError = result.error || "Couldn't join";
                }
            }
        }
    }

    // Volumes are only there for tracked nodes
    PwObjectTracker {
        objects: root.open ? [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] : []
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: window

        visible: root.open && root.placed
        screen: (root.atPointer && root.pointerX >= 0 ? root.pointerScreen : null) ?? Compositor.focusedScreen()
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: Math.round((screen?.width ?? 1920) * Theme.controlWidth)
        implicitHeight: panel.height

        WlrLayershell.namespace: "launcher-shadow"
        WlrLayershell.layer: WlrLayer.Overlay
        // Keys go to the password prompt while it's up
        WlrLayershell.keyboardFocus: root.passwordFor ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

        anchors {
            bottom: true
            right: true
        }
        margins.bottom: Theme.floatingGap
        margins.right: {
            if (!root.atPointer || root.pointerX < 0 || !screen)
                return Theme.floatingGap;
            const right = screen.width - root.pointerX - implicitWidth / 2;
            return Math.round(Math.max(Theme.floatingGap, Math.min(right, screen.width - implicitWidth - Theme.floatingGap)));
        }

        onVisibleChanged: {
            if (!visible)
                return;

            root.current = 0;
            list.forceActiveFocus();
            panel.appear();
        }

        Glass {
            id: panel

            floating: true

            width: parent.width
            height: list.height + Theme.panelPadding * 2

            Column {
                id: list

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Theme.panelPadding

                transform: Translate {
                    id: listSlide
                }

                ParallelAnimation {
                    id: pageSlide

                    property int direction: 1

                    NumberAnimation {
                        target: listSlide
                        property: "x"
                        from: pageSlide.direction * Theme.pageSlide
                        to: 0
                        duration: Theme.animationDuration
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: list
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: Theme.animationDuration
                    }
                }

                Keys.onPressed: event => {
                    const ctrl = event.modifiers & Qt.ControlModifier;
                    const count = root.rows.length;
                    const row = root.rows[Math.min(root.current, count - 1)];

                    if (event.key === Qt.Key_Escape && root.page !== "") {
                        root.closePage();
                    } else if (event.key === Qt.Key_Escape) {
                        root.open = false;
                    } else if (event.key === Qt.Key_Backspace && root.page !== "") {
                        root.closePage();
                    } else if (count === 0) {
                        return;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.activate(row);
                    } else if (event.key === Qt.Key_Space && root.page === "") {
                        root.openPage(row.section);
                    } else if (event.key === Qt.Key_S && root.page === "Bluetooth") {
                        root.toggleSearch();
                    } else if (row.kind === "media" && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) {
                        row.player.next();
                    } else if (row.kind === "media" && (event.key === Qt.Key_Left || event.key === Qt.Key_H)) {
                        row.player.previous();
                    } else if (event.key === Qt.Key_M && row.kind === "volume") {
                        root.toggleMute(row);
                    } else if (event.key === Qt.Key_Delete && row.kind === "bluetoothDevice" && row.device.paired) {
                        row.device.forget();
                    } else if (event.key === Qt.Key_Delete && row.kind === "network" && row.network.known) {
                        row.network.forget();
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || event.key === Qt.Key_J || (ctrl && event.key === Qt.Key_N)) {
                        root.current = (root.current + 1) % count;
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || event.key === Qt.Key_K || (ctrl && event.key === Qt.Key_P)) {
                        root.current = (root.current + count - 1) % count;
                    } else if (root.page === "Network" && row.kind === "network" && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) {
                        root.openDetails(row.network);
                    } else if (root.page === "Bluetooth" && row.kind === "bluetoothDevice" && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) {
                        root.openDevice(row.device);
                    } else if (!root.isSlider(row) && root.page === "" && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) {
                        root.openPage(row.section);
                    } else if (!root.isSlider(row) && root.page !== "" && (event.key === Qt.Key_Left || event.key === Qt.Key_H)) {
                        root.closePage();
                    } else if (root.isSlider(row) && (event.key === Qt.Key_Right || event.key === Qt.Key_L)) {
                        root.step(row, 1);
                    } else if (root.isSlider(row) && (event.key === Qt.Key_Left || event.key === Qt.Key_H)) {
                        root.step(row, -1);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Repeater {
                    id: rowRepeater

                    model: root.rows

                    ControlRow {
                        panel: root
                    }
                }

                Text {
                    visible: root.rows.length === 0
                    x: Theme.rowPadding
                    height: Theme.rowHeight
                    verticalAlignment: Text.AlignVCenter
                    text: Theme.controlEmptyText
                    color: Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                }
            }
        }
    }

    WifiPassword {
        panel: root
    }
}
