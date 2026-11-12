import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.widgets

// The tag's number, flashed in the middle of the focused screen when the
// focused monitor changes tag, as the bar shows only icons for a tag with
// windows. Clicks go through it.
Scope {
    id: root

    property bool shown: false
    property int number: 0

    readonly property var focusedScreen: Compositor.focusedScreen()
    readonly property var activeTag: Compositor.focusedMonitor?.tags?.find(tag => tag.is_active) ?? null
    // The monitor too, so moving to the same number on another one doesn't
    // flash it
    readonly property string key: activeTag ? Compositor.focusedMonitorName + " " + activeTag.index : ""

    // The first tag seen, at startup or when mango restarts, isn't a change
    property string lastKey: ""

    onKeyChanged: {
        if (!key)
            return;
        const first = !lastKey;
        const sameMonitor = lastKey.split(" ")[0] === Compositor.focusedMonitorName;
        lastKey = key;
        if (first || !sameMonitor)
            return;

        number = activeTag.index;
        if (!shown) {
            shown = true;
            panel.appear();
        }
        hide.restart();
    }

    Timer {
        id: hide
        interval: Theme.tagNumberTimeout
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

        // Nothing anchored: the layer shell centres it

        // Blurred, no shadow
        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Glass {
            id: panel

            floating: true
            width: Theme.tagNumberSize
            height: Theme.tagNumberSize
            color: Theme.popupColor
            edgeColor: Theme.popupEdgeColor

            Text {
                anchors.centerIn: parent
                text: root.number
                color: Theme.keyTextColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.tagNumberFontSize
                font.weight: Theme.fontWeight
            }
        }
    }
}
