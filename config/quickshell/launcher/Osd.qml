import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs

// Volume popup on the right edge, shown briefly when the output volume or a
// mute changes. Clicks go through it.
Scope {
    id: root

    // The control panel shows the same thing
    property bool suppressed: false
    property bool shown: false
    // "output" or "input"
    property string mode: "output"
    // Volumes report in once at startup; that isn't a change
    property bool armed: false

    readonly property var focusedScreen: Compositor.focusedScreen()
    readonly property PwNode node: mode === "input" ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink
    readonly property bool muted: node?.audio?.muted ?? false
    readonly property real level: node?.audio?.volume ?? 0

    function show(mode) {
        if (!armed || suppressed)
            return;

        root.mode = mode;
        if (!shown) {
            shown = true;
            panel.appear();
        }
        hide.restart();
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    Connections {
        target: Pipewire.defaultAudioSink?.audio ?? null

        function onVolumesChanged() {
            root.show("output");
        }

        function onMutedChanged() {
            root.show("output");
        }
    }

    // Mic volume is ignored: apps change it by themselves
    Connections {
        target: Pipewire.defaultAudioSource?.audio ?? null

        function onMutedChanged() {
            root.show("input");
        }
    }

    Timer {
        running: Pipewire.ready
        interval: 1000
        onTriggered: root.armed = true
    }

    Timer {
        id: hide
        interval: Theme.osdTimeout
        onTriggered: root.shown = false
    }

    onSuppressedChanged: if (suppressed)
        shown = false

    PanelWindow { // qmllint disable uncreatable-type
        visible: root.shown
        screen: root.focusedScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: panel.width
        implicitHeight: panel.height
        // Clicks go through
        mask: Region {}

        // Only the right edge anchored: the layer shell centres it vertically
        anchors.right: true
        margins.right: Theme.floatingGap

        // Blurred, no shadow
        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Glass {
            id: panel

            floating: true
            fromRight: true
            width: Theme.osdWidth
            height: Theme.osdHeight
            color: Theme.popupColor
            edgeColor: Theme.popupEdgeColor

            Column {
                anchors.centerIn: parent
                spacing: Theme.iconSpacing

                Text {
                    id: percent

                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.muted ? "mute" : Math.round(root.level * 100) + "%"
                    color: Theme.keyTextColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.osdFontSize
                    font.weight: Theme.fontWeight
                }

                // Filled from the bottom
                Rectangle {
                    id: track

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.sliderHeight
                    height: panel.height - Theme.panelPadding * 2 - percent.height - icon.height - parent.spacing * 2
                    radius: width / 2
                    color: Theme.sliderTrackColor

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(track.width, track.height * Math.max(0, Math.min(root.level, 1)))
                        radius: parent.radius
                        color: Theme.sliderColor(root.level, root.muted)
                        visible: root.level > 0

                        Behavior on height {
                            NumberAnimation {
                                duration: Theme.animationDuration
                            }
                        }
                    }
                }

                Text {
                    id: icon

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Theme.iconSize
                    horizontalAlignment: Text.AlignHCenter
                    text: root.mode === "input" ? (root.muted ? Theme.micMutedIcon : Theme.micIcon) : Theme.volumeIcon(root.level, root.muted)
                    color: Theme.volumeColor(root.level, root.muted)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.controlFontSize
                }
            }
        }
    }
}
