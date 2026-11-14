pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.widgets

// Quick notepad: one plain-text note per day, saved as you type to
// ~/.local/share/mangifera/notes/<yyyy-mm-dd>.md, floating above the bar.
// Toggled by ~/.local/bin/notepad; `--pointer` centres it over the bar button.
// Keys: Alt+Left/Right the previous or next day, Ctrl+T today, Ctrl+Return
// makes the line a checklist item and then ticks or unticks it, Escape
// closes.
Scope {
    id: root

    property bool open: false

    // -1 until shell.qml reports the pointer
    property bool atPointer: false
    property real pointerX: -1
    property var pointerScreen: null
    property bool placeWaited: false
    readonly property bool placed: !atPointer || pointerX >= 0 || placeWaited

    readonly property string folder: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/mangifera/notes"
    // The day shown, as yyyy-mm-dd
    property string day: root.today()

    function today() {
        return Qt.formatDate(new Date(), "yyyy-MM-dd");
    }

    // "Today", "Yesterday", "Tomorrow", or "Wed 11 Nov" (with the year when
    // it isn't this one)
    function label(day) {
        const date = new Date(day + "T00:00:00");
        const now = new Date();
        now.setHours(0, 0, 0, 0);
        const days = Math.round((date - now) / 86400000);
        if (days === 0)
            return "Today";
        if (days === -1)
            return "Yesterday";
        if (days === 1)
            return "Tomorrow";
        return Qt.formatDate(date, date.getFullYear() === now.getFullYear() ? "ddd d MMM" : "ddd d MMM yyyy");
    }

    function step(days) {
        const date = new Date(root.day + "T00:00:00");
        date.setDate(date.getDate() + days);
        root.show(Qt.formatDate(date, "yyyy-MM-dd"));
    }

    // Saves the day shown before moving to another
    function show(day) {
        if (day === root.day)
            return;
        note.saveNow();
        root.day = day;
    }

    onOpenChanged: {
        if (open) {
            // A new day since it was last open starts on today; the same
            // one is read again, in case the file changed while closed
            if (root.day === root.today())
                note.reload();
            else
                root.show(root.today());
        } else {
            note.saveNow();
            atPointer = false;
            placeWaited = false;
        }
    }

    // Pointer not found: fall back to the right edge
    Timer {
        running: root.open && !root.placed
        interval: 500
        onTriggered: root.placeWaited = true
    }

    // Also called over the launcher socket (shell.qml)
    property alias ipc: ipcHandler

    IpcHandler {
        id: ipcHandler
        target: "notepad"

        function toggleNotepad(): void {
            root.open = !root.open;
        }

        function toggleNotepadAtPointer(): void {
            if (!root.open)
                root.atPointer = true;
            root.open = !root.open;
        }

        function openNotepad(): void {
            root.open = true;
        }

        function closeNotepad(): void {
            root.open = false;
        }
    }

    // The notes folder, made once
    Process {
        running: true
        command: ["mkdir", "-p", root.folder]
    }

    // The day's note. A day with nothing written gets no file
    FileView {
        id: note

        // Whether the editor has changes not on disk yet: an untouched day,
        // empty or not, writes nothing
        property bool dirty: false
        // While a load fills the editor, which isn't an edit
        property bool loading: false

        function fill(text) {
            loading = true;
            editor.text = text;
            loading = false;
            dirty = false;
        }

        function saveNow() {
            save.stop();
            if (!dirty)
                return;
            dirty = false;
            note.setText(editor.text);
        }

        path: root.folder + "/" + root.day + ".md"
        blockLoading: true
        printErrors: false
        // Edited in another editor while open: shown, unless there are
        // changes here not saved yet
        watchChanges: true
        onFileChanged: if (!dirty)
            reload()

        onLoaded: fill(note.text())
        onLoadFailed: fill("")
    }

    // Saves a moment after typing stops
    Timer {
        id: save
        interval: Theme.notepadSaveDelay
        onTriggered: note.saveNow()
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: window

        visible: root.open && root.placed
        screen: (root.atPointer && root.pointerX >= 0 ? root.pointerScreen : null) ?? Compositor.focusedScreen()
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        implicitWidth: Theme.notificationWidth
        implicitHeight: panel.height

        // No shadow: no panel to cast one
        WlrLayershell.namespace: "launcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

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
            editor.cursorPosition = editor.length;
            editor.forceActiveFocus();
            panel.appear();
        }

        Glass {
            id: panel

            floating: true
            color: "transparent"
            edgeColor: "transparent"

            width: parent.width
            height: card.height

            Rectangle {
                id: card

                width: parent.width
                height: Theme.notepadHeight
                radius: Theme.cornerRadius
                color: Theme.noteCardColor

                // The day, and arrows to the one before and after
                Item {
                    id: header

                    x: Theme.panelPadding
                    width: parent.width - x * 2
                    height: Theme.noteCardButtonHeight + Theme.rowSpacing * 2

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.label(root.day)
                        color: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.searchFontSize
                        font.weight: Font.DemiBold
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.keySpacing

                        Repeater {
                            model: [
                                {
                                    glyph: "‹",
                                    days: -1
                                },
                                {
                                    glyph: "›",
                                    days: 1
                                }
                            ]

                            Rectangle {
                                id: arrow

                                required property var modelData

                                width: Theme.noteCardButtonHeight
                                height: Theme.noteCardButtonHeight
                                radius: Theme.cornerRadius
                                color: arrowMouse.containsMouse ? Theme.keyColor : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: arrow.modelData.glyph
                                    color: Theme.keyTextColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.controlFontSize
                                }

                                MouseArea {
                                    id: arrowMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: root.step(arrow.modelData.days)
                                }
                            }
                        }
                    }
                }

                Flickable {
                    id: scroller

                    x: Theme.panelPadding
                    y: header.height
                    width: parent.width - x * 2
                    height: parent.height - y - Theme.panelPadding / 2
                    contentWidth: width
                    contentHeight: editor.contentHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    // Keeps the cursor in view as it moves
                    function follow(rect) {
                        if (rect.y < contentY)
                            contentY = rect.y;
                        else if (rect.y + rect.height > contentY + height)
                            contentY = rect.y + rect.height - height;
                    }

                    TextEdit {
                        id: editor

                        width: scroller.width
                        height: Math.max(contentHeight, scroller.height)
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        selectByMouse: true
                        color: Theme.textColor
                        selectionColor: Theme.dividerColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.searchFontSize

                        onCursorRectangleChanged: scroller.follow(cursorRectangle)
                        onTextChanged: {
                            if (note.loading)
                                return;
                            note.dirty = true;
                            save.restart();
                        }

                        Text {
                            visible: editor.length === 0
                            text: "Jot something down…"
                            color: Theme.dimColor
                            font: editor.font
                        }

                        // The line the cursor is on: plain, then "- [ ] ",
                        // then "- [x] " and back
                        function toggleTask() {
                            const start = text.lastIndexOf("\n", cursorPosition - 1) + 1;
                            const line = text.slice(start, start + 6);
                            const at = cursorPosition;
                            if (line.startsWith("- [ ] ")) {
                                remove(start + 3, start + 4);
                                insert(start + 3, "x");
                            } else if (line.startsWith("- [x] ")) {
                                remove(start + 3, start + 4);
                                insert(start + 3, " ");
                            } else {
                                insert(start, "- [ ] ");
                                cursorPosition = at + 6;
                                return;
                            }
                            cursorPosition = at;
                        }

                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            const alt = event.modifiers & Qt.AltModifier;
                            if (event.key === Qt.Key_Escape) {
                                root.open = false;
                            } else if (alt && event.key === Qt.Key_Left) {
                                root.step(-1);
                            } else if (alt && event.key === Qt.Key_Right) {
                                root.step(1);
                            } else if (ctrl && event.key === Qt.Key_T) {
                                root.show(root.today());
                            } else if (ctrl && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                                toggleTask();
                            } else {
                                return;
                            }
                            event.accepted = true;
                        }
                    }
                }
            }
        }
    }
}
