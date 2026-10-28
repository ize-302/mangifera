pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.widgets

// Caps lock popup, centred above the bar while caps lock is on, and briefly
// after it's turned off. Reads the keyboard LEDs (/sys/class/leds/*::capslock),
// polled since sysfs doesn't notify.
Scope {
    id: root

    property bool on: false
    property bool shown: false
    // The first reading only shows the popup if caps lock is already on
    property bool armed: false

    readonly property var focusedScreen: Compositor.focusedScreen()

    function update(lit) {
        if (lit === on && armed)
            return;
        on = lit;
        const first = !armed;
        armed = true;
        if (first && !lit)
            return;
        if (!shown) {
            shown = true;
            panel.appear();
        }
        if (lit)
            hide.stop();
        else
            hide.restart();
    }

    // One bash loop printing 1 or 0 on change, re-globbing for new keyboards (a
    // FileView kept a stale value). Builtins only (loadable sleep when
    // available) so it forks nothing; setpriv kills it with the shell, as it
    // never writes to notice.
    Process {
        id: watcher

        command: ["setpriv", "--pdeathsig", "KILL", "bash", "-c", `
enable -f /usr/lib/bash/sleep sleep 2>/dev/null
last=
while :; do
	lit=0
	for path in /sys/class/leds/*::capslock/brightness; do
		read -r value <"$path" 2>/dev/null && [ -n "$value" ] && [ "$value" != 0 ] && lit=1
	done
	if [ "$lit" != "$last" ]; then
		echo "$lit"
		last=$lit
	fi
	sleep ${Theme.capsLockPoll / 1000}
done
`]
        running: true

        stdout: SplitParser {
            onRead: line => root.update(line.trim() === "1")
        }

        // Restart, throttled
        onExited: restart.start()
    }

    Timer {
        id: restart
        interval: 5000
        onTriggered: watcher.running = true
    }

    Timer {
        id: hide
        interval: Theme.capsLockTimeout
        onTriggered: root.shown = false
    }

    PanelWindow { // qmllint disable uncreatable-type
        visible: root.shown
        screen: root.focusedScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: panel.width
        implicitHeight: panel.height
        // Clicks go through
        mask: Region {}

        // Only the bottom anchored: the layer shell centres it across
        anchors.bottom: true
        margins.bottom: Theme.centredGap

        // Blurred, no shadow
        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Glass {
            id: panel

            floating: true
            width: Theme.capsLockSize
            height: Theme.capsLockSize
            color: Theme.popupColor
            edgeColor: Theme.popupEdgeColor

            Column {
                anchors.centerIn: parent
                spacing: Theme.rowSpacing

                Image {
                    id: icon
                    visible: false
                    width: Theme.capsLockIconSize
                    height: Theme.capsLockIconSize
                    sourceSize: Qt.size(width, height)
                    source: Qt.resolvedUrl("icons/capslock.svg")
                }

                MultiEffect {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: icon.width
                    height: icon.height
                    source: icon
                    colorization: 1
                    colorizationColor: root.on ? Theme.keyTextColor : Theme.dimColor
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.on ? "ON" : "OFF"
                    color: root.on ? Theme.keyTextColor : Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.capsLockFontSize
                    font.weight: Theme.fontWeight
                }
            }
        }
    }
}
