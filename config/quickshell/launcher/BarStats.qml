import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Readings for the bar's system modules, from /proc and /sys: CPU and memory
// every 2s, temperature every 5s, disk every 30s, network traffic every 5s.
// One for every screen's bar.
Scope {
    id: root

    // Percent
    property int cpu: 0
    property int memory: 0
    // GiB
    property real memoryUsed: 0
    property real memoryTotal: 0
    property real memoryFree: 0
    property real swapUsed: 0
    property real swapTotal: 0
    // °C
    property int temperature: 0
    // Percent, and bytes
    property int disk: 0
    property real diskUsed: 0
    property real diskFree: 0
    property real diskTotal: 0
    // Percent; -1 without a backlight, or with the screen off (lid shut)
    property int backlight: -1
    // Interface whose traffic and address to show, and what they are
    property string networkInterface: ""
    property string networkAddress: ""
    // Bytes a second
    property real download: 0
    property real upload: 0

    property var lastCpu: null
    property var lastTraffic: null

    readonly property string backlightPath: "/sys/class/backlight/" + backlightDevice + "/"
    property string backlightDevice: ""

    // "1.2kB/s", as waybar printed it
    function rate(bytes) {
        const units = ["B/s", "kB/s", "MB/s", "GB/s"];
        let unit = 0;
        while (bytes >= 1000 && unit < units.length - 1) {
            bytes /= 1000;
            unit++;
        }
        return (unit === 0 ? Math.round(bytes) : bytes.toFixed(1)) + units[unit];
    }

    function readCpu(text) {
        const fields = text.split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
        // idle + iowait
        const idle = fields[3] + fields[4];
        const total = fields.reduce((sum, value) => sum + value, 0);
        if (lastCpu && total > lastCpu.total)
            cpu = Math.round(100 * (1 - (idle - lastCpu.idle) / (total - lastCpu.total)));
        lastCpu = {
            idle: idle,
            total: total
        };
    }

    function readMemory(text) {
        const kib = {};
        for (const line of text.split("\n")) {
            const match = line.match(/^(\w+):\s+(\d+)/);
            if (match)
                kib[match[1]] = Number(match[2]);
        }
        const gib = 1024 * 1024;
        const total = kib.MemTotal ?? 0;
        const available = kib.MemAvailable ?? 0;
        memoryTotal = total / gib;
        memoryFree = available / gib;
        memoryUsed = (total - available) / gib;
        swapTotal = (kib.SwapTotal ?? 0) / gib;
        swapUsed = ((kib.SwapTotal ?? 0) - (kib.SwapFree ?? 0)) / gib;
        memory = total > 0 ? Math.round(100 * (total - available) / total) : 0;
    }

    function readTraffic(text) {
        const line = text.split("\n").find(line => line.trim().startsWith(networkInterface + ":"));
        if (!networkInterface || !line) {
            lastTraffic = null;
            download = upload = 0;
            return;
        }
        const fields = line.split(":")[1].trim().split(/\s+/).map(Number);
        const now = Date.now();
        const traffic = {
            interface: networkInterface,
            received: fields[0],
            sent: fields[8],
            at: now
        };
        if (lastTraffic?.interface === networkInterface && now > lastTraffic.at) {
            const seconds = (now - lastTraffic.at) / 1000;
            download = Math.max(0, (traffic.received - lastTraffic.received) / seconds);
            upload = Math.max(0, (traffic.sent - lastTraffic.sent) / seconds);
        }
        lastTraffic = traffic;
    }

    onNetworkInterfaceChanged: {
        lastTraffic = null;
        download = upload = 0;
        networkAddress = "";
        address.running = true;
    }

    FileView {
        id: stat
        path: "/proc/stat"
        printErrors: false
        onLoaded: root.readCpu(text())
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: root.readMemory(text())
    }

    FileView {
        id: thermal
        path: "/sys/class/thermal/thermal_zone0/temp"
        printErrors: false
        onLoaded: root.temperature = Math.round(Number(text()) / 1000)
    }

    FileView {
        id: netdev
        path: "/proc/net/dev"
        printErrors: false
        onLoaded: root.readTraffic(text())
    }

    // brightnessctl's writes show up as changes; the poll catches the rest
    FileView {
        id: brightness
        path: root.backlightDevice ? root.backlightPath + "brightness" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const max = Number(maxBrightness.text());
            const on = Number(power.text()) === 0;
            root.backlight = on && max > 0 ? Math.round(100 * Number(text()) / max) : -1;
        }
    }

    // 0 while the screen is on
    FileView {
        id: power
        path: root.backlightDevice ? root.backlightPath + "bl_power" : ""
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: maxBrightness
        path: root.backlightDevice ? root.backlightPath + "max_brightness" : ""
        blockLoading: true
        printErrors: false
    }

    // The first backlight, as waybar picked
    Process {
        running: true
        command: ["sh", "-c", "ls /sys/class/backlight | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: root.backlightDevice = text.trim()
        }
    }

    Process {
        id: diskUsage
        running: true
        command: ["df", "-B1", "--output=size,used,avail", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [size, used, free] = text.trim().split("\n").pop().trim().split(/\s+/).map(Number);
                if (!(size > 0))
                    return;
                root.diskTotal = size;
                root.diskUsed = used;
                root.diskFree = free;
                root.disk = Math.round(100 * used / size);
            }
        }
    }

    Process {
        id: address
        command: ["ip", "-j", "-4", "addr", "show", "dev", root.networkInterface]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.networkAddress = JSON.parse(text)[0]?.addr_info?.[0]?.local ?? "";
                } catch (error) {
                    root.networkAddress = "";
                }
            }
        }
    }

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 2000
        onTriggered: {
            stat.reload();
            meminfo.reload();
        }
    }

    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: 5000
        onTriggered: {
            thermal.reload();
            netdev.reload();
            if (root.backlightDevice) {
                power.reload();
                brightness.reload();
            }
        }
    }

    Timer {
        running: true
        repeat: true
        interval: 30000
        onTriggered: {
            diskUsage.running = true;
            if (root.networkInterface)
                address.running = true;
        }
    }
}
