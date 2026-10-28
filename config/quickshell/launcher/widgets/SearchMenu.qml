pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services

// Searchable list in the corner panel, or a strip of cards when `card` is set.
// The owner filters `results` by `query` and handles `accepted`.
PanelWindow { // qmllint disable uncreatable-type
    id: window

    property bool open: false
    // Already filtered by `query`
    property var results: []
    readonly property alias query: input.text
    property var label: item => ""
    property var icon: null
    // A hint that is a list is drawn as key caps
    property var hint: null
    // Property that groups rows under headers, and whether to show the result
    // count
    property string section: ""
    property bool showCount: false
    property string emptyText: ""
    // Fraction of the screen width
    property real panelWidth: Theme.panelWidth
    // Centred on screen instead of in the corner
    property bool floating: false
    // Centred just above the bar
    property bool aboveBar: false
    property bool shadow: floating
    property int cornerRadius: Theme.panelRadius
    property color panelColor: Theme.glassPanelColor
    property int panelPadding: Theme.panelPadding
    // Card delegate for a full-width strip on the bar. Gets `modelData` and
    // `index`; ListView.isCurrentItem marks the selection.
    property Component card: null
    readonly property bool strip: card !== null
    // Header above a strip of cards, with the card count
    property string title: ""
    readonly property int cardWidth: Math.round(screen.width * Theme.cardWidth)
    readonly property Item view: strip ? cards : list
    // Called with the key event and selected result first; returns true when
    // handled
    property var keyHandler: null

    // Without the search row, results aren't filtered and keys go straight to
    // the menu
    property bool searchable: true

    signal accepted(var item)

    function accept(item) {
        if (item === undefined)
            return;

        open = false;
        accepted(item);
    }

    function handleKey(event) {
        const selected = window.results[window.view.currentIndex];
        if (window.keyHandler && selected !== undefined && window.keyHandler(event, selected)) {
            event.accepted = true;
            return;
        }

        const ctrl = event.modifiers & Qt.ControlModifier;
        const count = window.results.length;
        const view = window.view;
        const current = view.currentIndex;
        const page = window.strip ? Math.max(1, Math.floor(cards.width / window.cardWidth)) : Theme.maxRows;
        // h and l move along a strip with no search field
        const vim = window.strip && !window.searchable && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));

        if (event.key === Qt.Key_Escape) {
            window.open = false;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            window.accept(window.results[current]);
        } else if (count === 0) {
            return;
        } else if (event.key === Qt.Key_Tab || (ctrl && event.key === Qt.Key_N) || (window.strip && event.key === Qt.Key_Right) || (vim && event.key === Qt.Key_L)) {
            view.currentIndex = (current + 1) % count;
        } else if (event.key === Qt.Key_Backtab || (ctrl && event.key === Qt.Key_P) || (window.strip && event.key === Qt.Key_Left) || (vim && event.key === Qt.Key_H)) {
            view.currentIndex = (current + count - 1) % count;
        } else if (event.key === Qt.Key_Down) {
            view.currentIndex = (current + 1) % count;
        } else if (event.key === Qt.Key_Up) {
            view.currentIndex = (current + count - 1) % count;
        } else if (event.key === Qt.Key_PageDown) {
            view.currentIndex = Math.min(current + page, count - 1);
        } else if (event.key === Qt.Key_PageUp) {
            view.currentIndex = Math.max(current - page, 0);
        } else {
            return;
        }
        event.accepted = true;
    }

    // Stays mapped, so it'd stay on the monitor it was made on (even once
    // that's switched off) without following focus
    screen: Compositor.focusedScreen()
    // Stays mapped while closed, just empty and click-through: mapping a
    // surface again took ~40 ms each open
    visible: !Compositor.remapping
    mask: Region {
        item: window.open ? panel : null
    }
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    implicitWidth: strip ? screen.width : Math.round(screen.width * panelWidth)
    implicitHeight: panel.height

    WlrLayershell.namespace: shadow ? "launcher-shadow" : "launcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // No edges anchored: the layer shell centres it
    anchors {
        bottom: !window.floating || window.strip || window.aboveBar
        left: !window.floating || window.strip
        right: window.strip
    }
    margins.bottom: window.floating && window.aboveBar ? Theme.centredGap : 0

    onOpenChanged: {
        if (!open) {
            panel.disappear();
            return;
        }

        input.text = "";
        window.view.currentIndex = 0;
        // The strip keeps its scroll while closed
        if (strip)
            cards.positionViewAtBeginning();
        (searchable ? input : keys).forceActiveFocus();
        panel.appear();
    }

    Glass {
        id: panel

        visible: window.open || hiding
        floating: window.floating
        slideDistance: Theme.launcherSlide
        slideDuration: Theme.launcherSlideDuration
        cornerRadius: window.cornerRadius
        fullWidth: window.strip
        color: window.panelColor
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: parent.width
        height: content.implicitHeight + window.panelPadding * 2

        Item {
            id: keys
            Keys.onPressed: event => window.handleKey(event)
        }

        Column {
            id: content

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: window.panelPadding
            spacing: Theme.searchPadding

            Row {
                x: Theme.rowPadding
                width: parent.width - x * 2
                visible: window.searchable
                spacing: Theme.iconSpacing

                Text {
                    id: searchIcon
                    text: Theme.searchIcon
                    color: Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.searchFontSize
                }

                TextInput {
                    id: input

                    width: parent.width - searchIcon.width - parent.spacing - (count.visible ? count.width + parent.spacing : 0)
                    color: Theme.textColor
                    selectionColor: Theme.dividerColor
                    selectedTextColor: Theme.textColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.searchFontSize
                    font.weight: Theme.fontWeight
                    clip: true

                    onTextChanged: window.view.currentIndex = 0

                    Keys.onPressed: event => window.handleKey(event)

                    Text {
                        visible: input.text.length === 0
                        text: Theme.placeholder
                        color: Theme.dimColor
                        font: input.font
                    }
                }

                Text {
                    id: count
                    visible: window.showCount
                    text: window.results.length
                    color: Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.sectionFontSize
                    font.weight: Theme.fontWeight
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                visible: window.searchable
                color: Theme.dividerColor
            }

            SectionHeader {
                width: parent.width
                visible: window.strip && window.title !== ""
                text: window.title
                summary: window.results.length > 0 ? String(window.results.length) : ""
            }

            // Always room for maxRows (or one row of cards)
            Item {
                width: parent.width
                height: window.strip ? Math.round(window.screen.height * Theme.cardHeight) : Theme.maxRows * (Theme.rowHeight + Theme.rowSpacing) - Theme.rowSpacing

                ListView {
                    id: cards

                    // Narrowed to its cards and centred while they don't
                    // fill the strip. From the card count, as contentWidth
                    // would loop through the width
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, window.results.length * window.cardWidth)
                    visible: window.strip
                    orientation: ListView.Horizontal
                    // Kept while closed: rebuilding the cards and decoding
                    // their previews delayed each open by up to ~90 ms
                    model: window.strip ? window.results : []
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0
                    delegate: window.card

                    // Wheel scrolls the strip half a card a notch
                    WheelHandler {
                        orientation: Qt.Vertical
                        onWheel: event => {
                            const delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * window.cardWidth / 2;
                            const end = cards.originX + Math.max(0, cards.contentWidth - cards.width);
                            cards.contentX = Math.max(cards.originX, Math.min(cards.contentX - delta, end));
                        }
                    }
                }

                Repeater {
                    model: window.strip ? [false, true] : []

                    delegate: Rectangle {
                        id: fade

                        required property bool modelData
                        readonly property bool atRight: modelData

                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: atRight ? undefined : parent.left
                        anchors.right: atRight ? parent.right : undefined
                        width: Theme.stripFadeWidth
                        opacity: (atRight ? cards.atXEnd : cards.atXBeginning) ? 0 : 1
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop {
                                position: 0
                                color: fade.atRight ? "transparent" : window.panelColor
                            }
                            GradientStop {
                                position: 1
                                color: fade.atRight ? window.panelColor : "transparent"
                            }
                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Theme.animationDuration
                            }
                        }
                    }
                }

                ListView {
                    id: list

                    anchors.fill: parent
                    visible: !window.strip
                    // Empty while closed: rows for every app took tens of MB.
                    // Kept while sliding away so it doesn't blank mid-slide.
                    model: window.strip || !(window.open || panel.hiding) ? [] : window.results
                    spacing: Theme.rowSpacing
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0

                    section.property: window.section
                    section.delegate: window.section ? sectionHeader : null

                    delegate: Rectangle {
                        id: row

                        required property var modelData
                        required property int index

                        width: list.width
                        height: Theme.rowHeight
                        color: ListView.isCurrentItem ? Theme.currentRowColor : "transparent"
                        radius: Theme.cornerRadius

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.rowPadding
                            width: parent.width - x * 2
                            spacing: Theme.iconSpacing

                            IconImage {
                                id: icon
                                anchors.verticalCenter: parent.verticalCenter
                                visible: window.icon !== null
                                implicitSize: Theme.iconSize
                                source: visible ? window.icon(row.modelData) : ""
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - (icon.visible ? icon.width + parent.spacing : 0) - (hint.visible ? hint.width + parent.spacing : 0)
                                text: window.label(row.modelData)
                                // Clipboard contents can look like markup
                                textFormat: Text.PlainText
                                color: row.ListView.isCurrentItem ? Theme.selectedColor : Theme.unselectedColor
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.weight: row.ListView.isCurrentItem ? Theme.selectedWeight : Theme.unselectedWeight
                            }

                            Row {
                                id: hint

                                readonly property var value: visible ? window.hint(row.modelData) : ""
                                readonly property bool caps: typeof value === "object"

                                anchors.verticalCenter: parent.verticalCenter
                                visible: window.hint !== null
                                spacing: Theme.keySpacing

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: !hint.caps
                                    text: hint.caps ? "" : hint.value
                                    textFormat: Text.PlainText
                                    color: Theme.dimColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.weight: Theme.fontWeight
                                }

                                Repeater {
                                    model: hint.caps ? hint.value : []

                                    delegate: KeyCap {
                                        required property string modelData

                                        y: (hint.height - height) / 2
                                        text: modelData
                                        lit: row.ListView.isCurrentItem
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: list.currentIndex = row.index
                            onClicked: window.accept(row.modelData)
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: window.results.length === 0
                    text: window.emptyText
                    color: Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }

    Component {
        id: sectionHeader

        SectionHeader {
            required property string section

            width: ListView.view.width
            text: section
        }
    }
}
