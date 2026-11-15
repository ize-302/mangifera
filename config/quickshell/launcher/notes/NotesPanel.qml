pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.widgets

// Notes: every Markdown file under ~/Notes, subfolders too, in a list beside
// an editor. Super+M toggles it (`launcher-call notes toggle`). It saves as
// you type; a note's first line is its title. New notes go in ~/Notes.
//
// Ctrl+N new note, Ctrl+F search, Alt+Up/Down the previous or next note,
// Ctrl+Shift+Backspace moves the note to the trash, Escape closes.
Scope {
    id: root

    property bool open: false
    readonly property string folder: Quickshell.env("HOME") + "/Notes"

    // { path: relative to folder, modified: ms since 1970, text }, newest
    // first
    property var notes: []
    property bool listed: false
    property string query: ""
    readonly property var shown: matching(notes, query)
    // The editor's note in `shown`, or -1 (a new note, or one the search
    // hides)
    readonly property int current: shown.findIndex(note => note.path === editing)
    // The editor's note; "" for a new one, which gets a file once it has text
    property string editing: ""
    // Typed since the last save
    property bool dirty: false
    // Asking whether to move the note to the trash
    property bool confirming: false
    // Set while the editor's text is replaced, so that isn't an edit
    property bool filling: false

    // Also called over the launcher socket (shell.qml)
    property alias ipc: ipcHandler

    // Every word of the query in the note's path or text
    function matching(notes, query) {
        const words = query.toLowerCase().split(/\s+/).filter(word => word);
        return notes.filter(note => {
            const text = (note.path + " " + note.text).toLowerCase();
            return words.every(word => text.includes(word));
        });
    }

    // The first line with text, without Markdown's leading #s. Else the file's
    // name (devs for growth/devs.md), or "New note" before it has one
    function title(text, path) {
        const line = text.split("\n").find(line => line.trim() !== "");
        if (line)
            return line.replace(/^\s*#+\s*/, "").trim() || line.trim();
        return path ? path.slice(path.lastIndexOf("/") + 1).replace(/\.md$/, "") : "New note";
    }

    // "ideas" for ideas/1-qa-app.md, "" at the top
    function folderOf(path) {
        const slash = path.lastIndexOf("/");
        return slash < 0 ? "" : path.slice(0, slash);
    }

    // 14:05 today, 3 Nov this year, 3 Nov 2025 before
    function when(ms) {
        const date = new Date(ms);
        const now = new Date();
        if (date.toDateString() === now.toDateString())
            return Qt.formatDateTime(date, "hh:mm");
        return Qt.formatDateTime(date, date.getFullYear() === now.getFullYear() ? "d MMM" : "d MMM yyyy");
    }

    function fill(text) {
        filling = true;
        editor.text = text;
        editor.cursorPosition = text.length;
        filling = false;
    }

    function show(note) {
        save();
        confirming = false;
        editing = note.path;
        dirty = false;
        fill(note.text);
    }

    function newNote() {
        save();
        confirming = false;
        // Before the search is cleared, which would show its first match
        editor.forceActiveFocus();
        search.text = "";
        editing = "";
        dirty = false;
        fill("");
    }

    // The previous or next note in the list
    function step(by) {
        const count = shown.length;
        if (count === 0)
            return;
        const from = current < 0 ? (by > 0 ? -1 : 0) : current;
        show(shown[(from + by + count) % count]);
    }

    // Writes the editor's note, giving a new one its file once it has text
    function save() {
        saveTimer.stop();
        if (!dirty)
            return;
        dirty = false;
        const text = editor.text;
        if (editing === "") {
            if (text.trim() === "")
                return;
            editing = Qt.formatDateTime(new Date(), "yyyy-MM-dd-hhmmss") + ".md";
        }
        file.path = folder + "/" + editing;
        file.setText(text);

        const path = editing;
        notes = [
            {
                path: path,
                modified: Date.now(),
                text: text
            }
        ].concat(notes.filter(note => note.path !== path));
    }

    // Moves the note to the trash (gio trash, so it can be got back), and
    // shows the next one
    function remove() {
        confirming = false;
        saveTimer.stop();
        dirty = false;
        if (editing !== "") {
            trash.command = ["gio", "trash", folder + "/" + editing];
            trash.running = true;
            const at = Math.max(current, 0);
            const path = editing;
            notes = notes.filter(note => note.path !== path);
            const next = shown[Math.min(at, shown.length - 1)];
            if (next) {
                show(next);
                return;
            }
        }
        newNote();
    }

    onOpenChanged: {
        if (!open) {
            save();
            confirming = false;
            panel.disappear();
            return;
        }
        listing.running = true;
        editor.forceActiveFocus();
        panel.appear();
    }

    IpcHandler {
        id: ipcHandler
        target: "notes"

        function toggle(): void {
            root.open = !root.open;
        }

        function openNotes(): void {
            root.open = true;
        }

        function closeNotes(): void {
            root.open = false;
        }
    }

    // Saves a moment after typing stops
    Timer {
        id: saveTimer
        interval: 400
        onTriggered: root.save()
    }

    FileView {
        id: file
        // Only written: the text comes from the listing
        preload: false
        atomicWrites: true
    }

    Process {
        id: trash
    }

    // Every note's path, time and text in one go: fields split by \037,
    // notes by \036. Makes ~/Notes first, for new notes. Hidden folders
    // (.git, .obsidian) are skipped
    Process {
        id: listing
        command: ["sh", "-c", "mkdir -p \"$1\" && cd \"$1\" && find . -type f -name '*.md' -not -path '*/.*' -printf '%T@\\037%P\\037' -exec cat {} \\; -printf '\\036'", "sh", root.folder]

        stdout: StdioCollector {
            onStreamFinished: {
                const notes = [];
                for (const record of text.split("\x1e")) {
                    const [modified, path, ...body] = record.split("\x1f");
                    if (path)
                        notes.push({
                            path: path,
                            modified: parseFloat(modified) * 1000,
                            text: body.join("\x1f")
                        });
                }
                notes.sort((a, b) => b.modified - a.modified);
                root.notes = notes;

                if (!root.listed) {
                    // First open: the newest note
                    root.listed = true;
                    if (notes.length > 0 && root.editing === "" && editor.text === "")
                        root.show(notes[0]);
                } else if (root.editing !== "" && !root.dirty) {
                    // Changed by another editor while closed
                    const note = notes.find(note => note.path === root.editing);
                    if (note && note.text !== editor.text)
                        root.fill(note.text);
                }
            }
        }
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: window

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

        // Only the bottom anchored: the layer shell centres it across
        anchors.bottom: true
        margins.bottom: Theme.centredGap

        WlrLayershell.namespace: "launcher-shadow"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Glass {
            id: panel

            visible: root.open || hiding
            floating: true
            width: Math.round(window.screen.width * Theme.notesWidth)
            height: Math.round(window.screen.height * Theme.notesHeight)

            // The list: search, then the notes
            Item {
                id: side

                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: Theme.panelPadding
                width: Math.round(panel.width * Theme.notesListWidth)

                Row {
                    id: searchRow

                    x: Theme.rowPadding
                    width: parent.width - x * 2
                    height: Theme.rowHeight
                    spacing: Theme.iconSpacing

                    Text {
                        id: searchIcon
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.searchIcon
                        color: Theme.dimColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.searchFontSize
                    }

                    TextInput {
                        id: search

                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - searchIcon.width - parent.spacing
                        color: Theme.textColor
                        selectionColor: Theme.dividerColor
                        selectedTextColor: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.searchFontSize
                        font.weight: Theme.fontWeight
                        clip: true

                        // Shows the first match as you type
                        onTextChanged: {
                            root.query = text;
                            if (activeFocus && root.shown.length > 0)
                                root.show(root.shown[0]);
                        }

                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            if (event.key === Qt.Key_Escape && text !== "")
                                text = "";
                            else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                editor.forceActiveFocus();
                            else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab)
                                root.step(1);
                            else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab)
                                root.step(-1);
                            else if (ctrl && event.key === Qt.Key_N)
                                root.newNote();
                            else
                                return;
                            event.accepted = true;
                        }

                        Text {
                            visible: search.text.length === 0
                            text: Theme.notesSearchText
                            color: Theme.dimColor
                            font: search.font
                        }
                    }
                }

                Rectangle {
                    id: searchLine
                    anchors.top: searchRow.bottom
                    anchors.topMargin: Theme.searchPadding / 2
                    width: parent.width
                    height: 1
                    color: Theme.dividerColor
                }

                ListView {
                    id: list

                    anchors.top: searchLine.bottom
                    anchors.topMargin: Theme.searchPadding
                    anchors.bottom: parent.bottom
                    width: parent.width
                    model: root.open || panel.hiding ? root.shown : []
                    currentIndex: root.current
                    spacing: Theme.rowSpacing
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    highlightMoveDuration: 0

                    delegate: Rectangle {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property bool selected: index === root.current
                        readonly property string place: root.folderOf(modelData.path)

                        width: list.width
                        height: Theme.notesRowHeight
                        radius: Theme.cornerRadius
                        color: selected ? Theme.currentRowColor : hover.containsMouse ? Theme.hoverColor : "transparent"

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.rowPadding
                            width: parent.width - x * 2
                            spacing: 2

                            Text {
                                width: parent.width
                                text: root.title(row.modelData.text, row.modelData.path)
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: row.selected ? Theme.selectedColor : Theme.unselectedColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.weight: row.selected ? Theme.selectedWeight : Theme.unselectedWeight
                            }

                            Text {
                                width: parent.width
                                text: root.when(row.modelData.modified) + (row.place ? "  ·  " + row.place : "")
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                color: Theme.dimColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.sectionFontSize
                            }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.show(row.modelData);
                                editor.forceActiveFocus();
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.shown.length === 0 && root.listed
                        text: root.query !== "" ? Theme.notesNoMatchText : Theme.notesEmptyText
                        color: Theme.dimColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }
            }

            Rectangle {
                id: divider
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: side.right
                anchors.leftMargin: Theme.panelPadding
                width: 1
                color: Theme.dividerColor
            }

            // The note, then the keys
            Item {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: divider.right
                anchors.right: parent.right
                anchors.margins: Theme.panelPadding

                Flickable {
                    id: scroller

                    anchors.top: parent.top
                    anchors.bottom: footer.top
                    anchors.bottomMargin: Theme.searchPadding
                    width: parent.width
                    contentWidth: width
                    contentHeight: editor.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    // Keeps the cursor in view
                    function follow(rect) {
                        if (rect.y < contentY)
                            contentY = rect.y;
                        else if (rect.y + rect.height > contentY + height)
                            contentY = rect.y + rect.height - height;
                    }

                    TextEdit {
                        id: editor

                        width: scroller.width
                        padding: Theme.rowPadding
                        wrapMode: TextEdit.Wrap
                        textFormat: TextEdit.PlainText
                        selectByMouse: true
                        persistentSelection: true
                        color: Theme.textColor
                        selectionColor: Theme.dividerColor
                        selectedTextColor: Theme.textColor
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.notesFontSize
                        font.weight: Theme.fontWeight

                        onCursorRectangleChanged: scroller.follow(cursorRectangle)
                        onTextChanged: {
                            if (root.filling)
                                return;
                            root.dirty = true;
                            root.confirming = false;
                            saveTimer.restart();
                        }

                        Keys.onPressed: event => {
                            const ctrl = event.modifiers & Qt.ControlModifier;
                            const shift = event.modifiers & Qt.ShiftModifier;
                            const alt = event.modifiers & Qt.AltModifier;
                            const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;

                            if (root.confirming && enter) {
                                root.remove();
                            } else if (root.confirming && event.key === Qt.Key_Escape) {
                                root.confirming = false;
                            } else if (event.key === Qt.Key_Escape) {
                                root.open = false;
                            } else if (ctrl && shift && event.key === Qt.Key_Backspace) {
                                root.confirming = root.editing !== "" || editor.text !== "";
                            } else if (ctrl && event.key === Qt.Key_N) {
                                root.newNote();
                            } else if (ctrl && event.key === Qt.Key_F) {
                                search.selectAll();
                                search.forceActiveFocus();
                            } else if (alt && event.key === Qt.Key_Down) {
                                root.step(1);
                            } else if (alt && event.key === Qt.Key_Up) {
                                root.step(-1);
                            } else {
                                if (root.confirming)
                                    root.confirming = false;
                                return;
                            }
                            event.accepted = true;
                        }

                        Text {
                            x: editor.padding
                            y: editor.padding
                            visible: editor.text.length === 0
                            text: Theme.notesPlaceholder
                            color: Theme.dimColor
                            font: editor.font
                        }
                    }
                }

                // The keys, or the question before trashing
                Row {
                    id: footer

                    anchors.bottom: parent.bottom
                    x: Theme.rowPadding
                    height: Theme.keyHeight
                    spacing: Theme.iconSpacing * 2

                    Repeater {
                        model: root.confirming ? [
                            {
                                keys: ["Enter"],
                                label: "Move “" + root.title(editor.text, root.editing) + "” to the trash"
                            },
                            {
                                keys: ["Esc"],
                                label: "Keep it"
                            }
                        ] : [
                            {
                                keys: ["Ctrl", "N"],
                                label: "New"
                            },
                            {
                                keys: ["Alt", "↑↓"],
                                label: "Switch"
                            },
                            {
                                keys: ["Ctrl", "Shift", "⌫"],
                                label: "Delete"
                            },
                            {
                                keys: ["Esc"],
                                label: "Close"
                            }
                        ]

                        delegate: Row {
                            id: hint

                            required property var modelData

                            spacing: Theme.keySpacing

                            Repeater {
                                model: hint.modelData.keys

                                delegate: KeyCap {
                                    required property string modelData
                                    text: modelData
                                    lit: root.confirming
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                leftPadding: Theme.keySpacing
                                text: hint.modelData.label
                                textFormat: Text.PlainText
                                color: root.confirming ? Theme.textColor : Theme.dimColor
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.sectionFontSize
                            }
                        }
                    }
                }
            }
        }
    }
}
