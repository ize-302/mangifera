pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs

// A tray app's menu, drawn like the launcher's menus instead of Qt's: rows
// over glass, centred above the tray icon. Submenus open in place, with a
// row back. Opened by the bar (Bar.qml). Up/Down (k/j) pick, Enter runs,
// Right (l) opens a submenu, Left (h) goes back, Escape closes.
Scope {
    id: root

    property bool open: false
    // The app's QsMenuHandle, and where its tray icon is
    property var menu: null
    property var screen: null
    property real centreX: 0
    // Submenus opened, innermost last
    property var path: []
    property int current: -1

    readonly property var entries: opener.children?.values ?? []
    readonly property var runnable: entries.filter(entry => !entry.isSeparator && entry.enabled)
    readonly property bool hasChecks: entries.some(entry => entry.buttonType !== QsMenuButtonType.None)
    readonly property bool hasIcons: entries.some(entry => entry.icon)

    function show(menu, screen, centreX) {
        root.menu = menu;
        root.screen = screen;
        root.centreX = centreX;
        root.path = [];
        root.current = -1;
        root.open = true;
    }

    function enter(entry) {
        root.path = root.path.concat([entry]);
        root.current = -1;
    }

    function back() {
        root.path = root.path.slice(0, -1);
        root.current = -1;
    }

    function run(entry) {
        if (!entry || entry.isSeparator || !entry.enabled)
            return;
        if (entry.hasChildren) {
            root.enter(entry);
            return;
        }
        entry.triggered();
        root.open = false;
    }

    // Moves the highlight to the next row that can run, skipping
    // separators and disabled ones
    function step(by) {
        const rows = root.entries;
        if (root.runnable.length === 0)
            return;
        let index = root.current;
        do {
            index = (index + by + rows.length) % rows.length;
        } while (rows[index].isSeparator || !rows[index].enabled);
        root.current = index;
    }

    // "_Open" is a mnemonic, "__" a real underscore
    function label(entry) {
        return entry.text.replace(/__/g, "\u0000").replace(/_/g, "").replace(/\u0000/g, "_");
    }

    function checkGlyph(entry) {
        const checked = entry.checkState === Qt.Checked;
        if (entry.buttonType === QsMenuButtonType.RadioButton)
            return checked ? Theme.trayRadioOnIcon : Theme.trayRadioOffIcon;
        if (entry.buttonType === QsMenuButtonType.CheckBox)
            return checked ? Theme.trayCheckOnIcon : Theme.trayCheckOffIcon;
        return "";
    }

    onOpenChanged: if (!open)
        path = []

    QsMenuOpener {
        id: opener
        menu: root.path.length > 0 ? root.path[root.path.length - 1] : root.menu
    }

    // Widest label, so the panel fits it
    FontMetrics {
        id: metrics

        readonly property real widest: Math.max(advanceWidth(Theme.trayBackText), ...root.entries.map(entry => advanceWidth(root.label(entry))))

        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.weight: Theme.selectedWeight
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: window

        visible: root.open && root.menu !== null
        screen: root.screen
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: panel.width
        implicitHeight: panel.height

        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        anchors {
            bottom: true
            left: true
        }
        margins.bottom: Theme.floatingGap
        margins.left: {
            const width = screen?.width ?? implicitWidth;
            const left = root.centreX - implicitWidth / 2;
            return Math.round(Math.max(Theme.floatingGap, Math.min(left, width - implicitWidth - Theme.floatingGap)));
        }

        onVisibleChanged: {
            if (!visible)
                return;
            rows.forceActiveFocus();
            panel.appear();
        }

        Glass {
            id: panel

            readonly property real leading: (root.hasChecks || root.hasIcons || root.path.length > 0 ? Theme.trayIconSize + Theme.iconSpacing : 0)

            floating: true
            width: Math.min(Theme.trayMenuMaxWidth, Math.ceil(leading + metrics.widest + Theme.iconSpacing + Theme.trayIconSize) + Theme.rowPadding * 2 + Theme.powerPanelPadding * 2)
            height: rows.height + Theme.powerPanelPadding * 2

            Column {
                id: rows

                anchors.centerIn: parent
                width: parent.width - Theme.powerPanelPadding * 2

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
                        root.open = false;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.run(root.entries[root.current]);
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J || event.key === Qt.Key_Tab) {
                        root.step(1);
                    } else if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.key === Qt.Key_Backtab) {
                        root.step(-1);
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        const entry = root.entries[root.current];
                        if (entry?.hasChildren && entry.enabled)
                            root.enter(entry);
                    } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_H || event.key === Qt.Key_Backspace) && root.path.length > 0) {
                        root.back();
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                // Back out of a submenu
                MenuRow {
                    visible: root.path.length > 0
                    glyph: Theme.backIcon
                    text: Theme.trayBackText
                    onActivated: root.back()
                }

                Rectangle {
                    visible: root.path.length > 0
                    width: rows.width
                    height: Theme.rowSpacing * 2 + 1
                    color: "transparent"

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - Theme.rowPadding * 2
                        height: 1
                        color: Theme.dividerColor
                    }
                }

                Repeater {
                    model: root.entries

                    Item {
                        id: entryItem

                        required property QsMenuEntry modelData
                        required property int index

                        width: rows.width
                        height: modelData.isSeparator ? Theme.rowSpacing * 2 + 1 : entryRow.height

                        Rectangle {
                            visible: entryItem.modelData.isSeparator
                            anchors.centerIn: parent
                            width: parent.width - Theme.rowPadding * 2
                            height: 1
                            color: Theme.dividerColor
                        }

                        MenuRow {
                            id: entryRow

                            visible: !entryItem.modelData.isSeparator
                            selected: root.current === entryItem.index
                            enabled: entryItem.modelData.enabled
                            glyph: root.checkGlyph(entryItem.modelData)
                            icon: entryItem.modelData.icon
                            text: root.label(entryItem.modelData)
                            submenu: entryItem.modelData.hasChildren
                            leading: root.hasChecks || root.hasIcons || root.path.length > 0

                            onHovered: root.current = entryItem.index
                            onActivated: root.run(entryItem.modelData)
                        }
                    }
                }
            }
        }
    }

    // One row: a check, icon or glyph in front, the label, a chevron for a
    // submenu
    component MenuRow: Rectangle {
        id: row

        property bool selected: false
        property string glyph: ""
        property string icon: ""
        property string text: ""
        property bool submenu: false
        property bool leading: true

        signal hovered
        signal activated

        readonly property color textColor: !enabled ? Theme.dimColor : selected ? Theme.selectedColor : Theme.unselectedColor

        width: parent?.width ?? 0
        height: Theme.rowHeight + Theme.rowSpacing
        radius: Theme.cornerRadius
        color: selected && enabled ? Theme.currentRowColor : "transparent"

        Item {
            id: lead

            visible: row.leading
            anchors.left: parent.left
            anchors.leftMargin: Theme.rowPadding
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.trayIconSize
            height: Theme.trayIconSize

            Text {
                visible: row.glyph !== ""
                anchors.centerIn: parent
                text: row.glyph
                color: row.textColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.trayIconSize - 2
            }

            IconImage {
                visible: row.glyph === "" && row.icon !== ""
                anchors.fill: parent
                source: row.icon
                opacity: row.enabled ? 1 : 0.5
            }
        }

        Text {
            anchors.left: row.leading ? lead.right : parent.left
            anchors.leftMargin: row.leading ? Theme.iconSpacing : Theme.rowPadding
            anchors.right: chevron.left
            anchors.rightMargin: Theme.iconSpacing
            anchors.verticalCenter: parent.verticalCenter
            text: row.text
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: row.textColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.weight: row.selected && row.enabled ? Theme.selectedWeight : Theme.unselectedWeight
        }

        Text {
            id: chevron

            anchors.right: parent.right
            anchors.rightMargin: Theme.rowPadding
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.trayIconSize
            horizontalAlignment: Text.AlignHCenter
            visible: row.submenu
            text: Theme.pageIcon
            color: row.textColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.trayIconSize - 2
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.enabled
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: row.hovered()
            onClicked: row.activated()
        }
    }
}
