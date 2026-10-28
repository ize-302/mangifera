pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services
import qs.widgets

// The scratchpad as a full-screen overview, like macOS Mission Control: the
// desktop dims behind a centred grid of previews, each sized to its window's
// shape. Theme.scratchpadStyle "overview" picks it over the strip.
PanelWindow { // qmllint disable uncreatable-type
    id: window

    property bool open: false
    // { id, appId, title, toplevel, width, height }
    property var entries: []
    // Client id -> preview URL
    property var previews: ({})
    property var icon: entry => ""
    property string emptyText: ""
    // Called with the key event and selected entry first; returns true when
    // handled
    property var keyHandler: null
    property int currentIndex: 0
    // Widest a preview gets
    property int previewWidth: 0
    readonly property var rects: layout(entries, area.width, area.height)

    signal accepted(var entry)
    signal closeClicked(var entry)

    function accept(entry) {
        if (entry === undefined)
            return;

        open = false;
        accepted(entry);
    }

    // Rows of previews at one height, the most rows' worth that keeps them
    // biggest. Returns { x, y, width, height } per entry, centred in the area.
    function layout(entries, areaWidth, areaHeight) {
        const count = entries.length;
        if (count === 0 || areaWidth <= 0 || areaHeight <= 0)
            return [];

        const gap = Theme.overviewGap;
        const titleHeight = Theme.overviewTitleHeight;
        const maxHeight = areaHeight * Theme.overviewMaxHeight;
        const maxWidth = window.previewWidth;
        const aspects = entries.map(entry => entry.width > 0 && entry.height > 0 ? entry.width / entry.height : 16 / 10);

        let best = null;
        for (let rows = 1; rows <= count; rows++) {
            const perRow = Math.ceil(count / rows);
            const split = [];
            for (let i = 0; i < count; i += perRow)
                split.push(aspects.slice(i, i + perRow));

            let height = Math.min(maxHeight, (areaHeight - gap * (split.length - 1)) / split.length - titleHeight);
            for (const row of split) {
                const total = row.reduce((sum, aspect) => sum + Math.min(aspect, maxWidth / height), 0);
                height = Math.min(height, (areaWidth - gap * (row.length - 1)) / total);
            }
            if (best === null || height > best.height)
                best = { height, split };
        }

        const result = [];
        const rowHeight = best.height + titleHeight;
        let y = (areaHeight - (best.split.length * rowHeight + (best.split.length - 1) * gap)) / 2;
        for (const row of best.split) {
            const widths = row.map(aspect => Math.min(aspect * best.height, maxWidth));
            let x = (areaWidth - widths.reduce((sum, width) => sum + width, 0) - gap * (row.length - 1)) / 2;
            widths.forEach((width, index) => {
                // Shorter than the row only when capped; keeps its shape
                const height = Math.min(best.height, width / row[index]);
                result.push({ x: Math.round(x), y: Math.round(y + best.height - height), width: Math.round(width), height: Math.round(height) });
                x += width + gap;
            });
            y += rowHeight + gap;
        }
        return result;
    }

    // The nearest preview in the row above or below, by centre
    function vertical(step) {
        const current = window.rects[window.currentIndex];
        if (current === undefined)
            return window.currentIndex;

        const centre = current.x + current.width / 2;
        let best = -1;
        let bestRow = Infinity;
        let bestDistance = Infinity;
        window.rects.forEach((rect, index) => {
            const rowDistance = (rect.y + rect.height - current.y - current.height) * step;
            if (rowDistance <= 0)
                return;
            const distance = Math.abs(rect.x + rect.width / 2 - centre);
            if (rowDistance < bestRow - 1 || (Math.abs(rowDistance - bestRow) <= 1 && distance < bestDistance)) {
                best = index;
                bestRow = rowDistance;
                bestDistance = distance;
            }
        });
        return best === -1 ? window.currentIndex : best;
    }

    function handleKey(event) {
        const selected = window.entries[window.currentIndex];
        if (window.keyHandler && selected !== undefined && window.keyHandler(event, selected)) {
            event.accepted = true;
            return;
        }

        const count = window.entries.length;
        const current = window.currentIndex;
        const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));

        if (event.key === Qt.Key_Escape) {
            window.open = false;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            window.accept(selected);
        } else if (count === 0) {
            return;
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Right || (plain && event.key === Qt.Key_L)) {
            window.currentIndex = (current + 1) % count;
        } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Left || (plain && event.key === Qt.Key_H)) {
            window.currentIndex = (current + count - 1) % count;
        } else if (event.key === Qt.Key_Down || (plain && event.key === Qt.Key_J)) {
            window.currentIndex = window.vertical(1);
        } else if (event.key === Qt.Key_Up || (plain && event.key === Qt.Key_K)) {
            window.currentIndex = window.vertical(-1);
        } else {
            return;
        }
        event.accepted = true;
    }

    onOpenChanged: {
        if (open) {
            window.currentIndex = 0;
            keys.forceActiveFocus();
        }
    }

    // Mapped only while shown: a full-screen blurred layer would blur the
    // desktop even while clear
    screen: Compositor.focusedScreen()
    visible: (open || backdrop.opacity > 0) && !Compositor.remapping
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    Item {
        id: keys
        Keys.onPressed: event => window.handleKey(event)
    }

    Rectangle {
        id: backdrop

        anchors.fill: parent
        color: Theme.overviewScrimColor
        opacity: window.open ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.overviewDuration
                easing.type: Easing.OutCubic
            }
        }

        // A click on the desktop closes it
        MouseArea {
            anchors.fill: parent
            onClicked: window.open = false
        }

        Text {
            anchors.centerIn: parent
            visible: window.entries.length === 0
            text: window.emptyText
            color: Theme.dimColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.searchFontSize
            font.weight: Theme.fontWeight
        }
    }

    Item {
        id: area

        anchors.fill: parent
        anchors.margins: Theme.overviewMargin
        // Zooms in a little as it opens
        opacity: backdrop.opacity
        scale: 0.94 + 0.06 * backdrop.opacity

        Repeater {
            model: window.entries

            delegate: Item {
                id: cell

                required property var modelData
                required property int index
                readonly property var rect: window.rects[index] ?? { x: 0, y: 0, width: 0, height: 0 }
                readonly property bool selected: window.currentIndex === index
                readonly property bool closing: closeButton.hovered
                readonly property string iconSource: window.icon(modelData)

                x: rect.x
                y: rect.y
                width: rect.width
                height: rect.height + Theme.overviewTitleHeight
                // Grows as a whole, so the close tab stays in its corner
                scale: selected ? 1.03 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animationDuration * 2
                        easing.type: Easing.OutCubic
                    }
                }

                ClippingRectangle {
                    id: thumbnail

                    width: parent.width
                    height: cell.rect.height
                    radius: Theme.overviewRadius
                    color: Theme.panelColor

                    Image {
                        id: preview
                        anchors.fill: parent
                        source: window.previews[cell.modelData.id] ?? ""
                        fillMode: Image.PreserveAspectCrop
                        verticalAlignment: Image.AlignTop
                        asynchronous: true
                        cache: false
                        smooth: true
                        // Decoded at the largest preview's size, not the
                        // window's
                        sourceSize.width: window.previewWidth
                    }

                    // Until the preview is ready, or when it can't be grabbed
                    IconImage {
                        anchors.centerIn: parent
                        visible: preview.status !== Image.Ready
                        implicitSize: Theme.iconSize * 3
                        source: cell.iconSource
                        opacity: 0.5
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: cell.closing ? Theme.scratchpadCloseColor : "black"
                        opacity: cell.closing ? 0.1 : cell.selected ? 0 : 0.2

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.animationDuration
                            }
                        }
                    }

                    // Drawn over the preview, so it isn't clipped
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.overviewRadius
                        color: "transparent"
                        border.width: cell.selected || cell.closing ? 3 : 1
                        border.color: cell.closing ? Theme.scratchpadCloseColor : cell.selected ? Theme.selectedColor : Theme.edgeColor

                        Behavior on border.color {
                            ColorAnimation {
                                duration: Theme.animationDuration
                            }
                        }
                    }
                }

                // App icon on the preview's bottom edge
                IconImage {
                    anchors.horizontalCenter: thumbnail.horizontalCenter
                    anchors.verticalCenter: thumbnail.bottom
                    implicitSize: Theme.iconSize * 1.6
                    source: cell.iconSource
                }

                // Title pill, for the selected one only
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    width: Math.min(parent.width, title.implicitWidth + Theme.rowPadding * 2)
                    height: Theme.overviewPillHeight
                    radius: height / 2
                    color: Theme.panelColor
                    opacity: cell.selected ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.animationDuration
                        }
                    }

                    Text {
                        id: title
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - Theme.rowPadding * 2)
                        text: cell.modelData.title
                        textFormat: Text.PlainText
                        color: Theme.textColor
                        elide: Text.ElideRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.keyFontSize
                        font.weight: Theme.fontWeight
                    }
                }

                MouseArea {
                    id: cellMouse
                    width: parent.width
                    height: cell.rect.height
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: window.currentIndex = cell.index
                    onClicked: window.accept(cell.modelData)
                }

                CloseButton {
                    id: closeButton
                    // Centred on the preview's top right corner
                    anchors.horizontalCenter: thumbnail.right
                    anchors.verticalCenter: thumbnail.top
                    outside: true
                    shown: cellMouse.containsMouse || hovered
                    onClicked: window.closeClicked(cell.modelData)
                }
            }
        }
    }
}
