pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs

// Cheat sheet of the mango key bindings, toggled by ~/.local/bin/keybind-menu.
// Typing filters rows by every word (a matching group name keeps all its rows).
// Escape clears the search, or closes.
Scope {
    id: root

    property bool open: false
    // { name, rows: [{ label, keys: [{ text, cap }] }] }
    property var groups: []
    property string query: ""
    readonly property var columns: root.split(root.groups).map(column => root.search(column, root.query)).filter(column => column.length > 0)

    readonly property var keyNames: ({
            "SUPER": "Super",
            "Super_L": "Super",
            "SHIFT": "Shift",
            "CTRL": "Ctrl",
            "ALT": "Alt",
            "Return": "Enter",
            "Escape": "Esc",
            "space": "Space",
            "minus": "-",
            "slash": "/",
            "question": "?",
            "BackSpace": "Backspace",
            "Left": "←",
            "Right": "→",
            "Up": "↑",
            "Down": "↓",
            "XF86AudioRaiseVolume": "Volume +",
            "XF86AudioLowerVolume": "Volume −",
            "XF86AudioMute": "Mute",
            "XF86AudioMicMute": "Mic mute",
            "XF86MonBrightnessUp": "Brightness +",
            "XF86MonBrightnessDown": "Brightness −",
            "XF86AudioPlay": "Play",
            "XF86AudioPause": "Pause",
            "XF86AudioPrev": "Previous",
            "XF86AudioNext": "Next",
            "XF86AudioStop": "Stop"
        })

    // "SUPER+SHIFT", "r" -> ["Super", "Shift", "R"]. NONE and the key itself
    // (SUPER,Super_L) aren't modifiers; "XF86" is dropped
    function keys(modifiers, key) {
        const combo = modifiers.toUpperCase() === "NONE" ? [] : modifiers.split("+");
        return [...new Set(combo.concat([key]).map(key => root.keyNames[key] ?? root.keyNames[key.toUpperCase()] ?? (key.length === 1 ? key.toUpperCase() : key.replace(/^XF86/, ""))))];
    }

    // Label for a binding without its own comment: "focusdir left" -> "focus
    // left"
    function describe(func, args) {
        const resize = {
            "-10,+0": "shrink width",
            "+10,+0": "grow width",
            "+0,-10": "shrink height",
            "+0,+10": "grow height"
        };
        switch (func) {
        case "spawn":
        case "spawn_shell":
            return args.join(",");
        case "focusdir":
            return "focus " + args[0];
        case "move_client":
            return "move " + args[0];
        case "view":
            return "tag " + args[0];
        case "tag":
            return "move to tag " + args[0];
        case "tagsilent":
            return "send to tag " + args[0];
        case "resizewin":
            return resize[args.join(",")] ?? "resize " + args.join(" ");
        default:
            return [func.replace(/_/g, " ")].concat(args).join(" ");
        }
    }

    // Parses config.conf, then local.conf. A comment right above a lone binding
    // is its label; bindings in a run under a shared comment use their command.
    // Sections are "#", "# Name:", "#" blocks, plus key modes; before the
    // first, "General".
    // Rows with the same modifiers and label but for a number merge: "Super 1 –
    // 9".
    function parse(config) {
        const lines = config.split("\n").map(line => line.trim());
        const isBinding = line => /^bind[slrpc]*\s*=/.test(line ?? "");
        const rows = [];
        const merged = {};
        let comment = [];
        let mode = "";
        let section = "General";

        for (let index = 0; index < lines.length; index++) {
            const line = lines[index];
            const heading = line.match(/^#\s*([^#].*):$/);

            if (heading && lines[index - 1] === "#" && lines[index + 1] === "#") {
                section = heading[1];
                comment = [];
                continue;
            }
            const keyMode = line.match(/^key_mode\s*=\s*(\S+)$/);

            // A binding commented out names nothing
            if (/^#\s*bind/.test(line)) {
                comment = [];
                continue;
            }
            if (/^#\s*\S/.test(line)) {
                comment.push(line.replace(/^#+\s*/, ""));
                continue;
            }

            if (keyMode)
                mode = ["common", "default"].includes(keyMode[1]) ? "" : keyMode[1].charAt(0).toUpperCase() + keyMode[1].slice(1) + " mode";

            if (isBinding(line)) {
                const fields = line.replace(/^[^=]*=\s*/, "").split(",").map(field => field.trim());
                const combo = root.keys(fields[0], fields[1] ?? "");
                const func = fields[2] ?? "";
                const args = fields.slice(3).filter(arg => arg !== "");
                const command = root.describe(func, ["spawn", "spawn_shell"].includes(func) ? fields.slice(3) : args);
                const own = comment.length > 0 && !isBinding(lines[index + 1]);
                const label = own ? comment.join(" ") : command;
                const group = mode || section;
                const modifiers = combo.slice(0, -1);
                const id = [group, modifiers.join("+"), label.replace(/\d+/g, "#")].join("\n");

                if (!merged[id]) {
                    merged[id] = {
                        group: group,
                        label: label,
                        modifiers: modifiers,
                        last: [],
                        numbers: []
                    };
                    rows.push(merged[id]);
                }
                merged[id].last.push(combo[combo.length - 1]);
                const number = label.match(/\d+/);
                if (number)
                    merged[id].numbers.push(number[0]);
            }
            comment = [];
        }

        const groups = [];
        for (const row of rows) {
            let group = groups.find(group => group.name === row.group);
            if (!group) {
                group = {
                    name: row.group,
                    rows: []
                };
                groups.push(group);
            }
            group.rows.push({
                label: root.label(row),
                keys: root.caps(row)
            });
        }
        return groups;
    }

    function label(row) {
        const numbers = row.numbers;
        const text = new Set(numbers).size > 1 ? row.label.replace(/\d+/, numbers[0] + "–" + numbers[numbers.length - 1]) : row.label;
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    // A few keys apart, many as a range
    function caps(row) {
        const cap = text => ({
                text: text,
                cap: true
            });
        const between = text => ({
                text: text,
                cap: false
            });
        const last = row.last;
        let ends = [cap(last[0])];

        if (last.length > 2)
            ends = [cap(last[0]), between("–"), cap(last[last.length - 1])];
        else if (last.length === 2)
            ends = [cap(last[0]), between("/"), cap(last[1])];
        return row.modifiers.map(cap).concat(ends);
    }

    function search(groups, query) {
        const words = query.toLowerCase().split(/\s+/).filter(word => word);
        if (words.length === 0)
            return groups;
        const matches = text => words.every(word => text.toLowerCase().includes(word));
        return groups.map(group => ({
                    name: group.name,
                    rows: matches(group.name) ? group.rows : group.rows.filter(row => matches([group.name, row.label].concat(row.keys.map(key => key.text)).join(" ")))
                })).filter(group => group.rows.length > 0);
    }

    // Two columns of about equal height, groups kept whole and in order
    function split(groups) {
        const heights = groups.map(group => group.rows.length + 1);
        const total = heights.reduce((sum, height) => sum + height, 0);
        let best = groups.length;
        let tallest = total;
        let left = 0;

        for (let index = 0; index < groups.length; index++) {
            left += heights[index];
            const taller = Math.max(left, total - left);
            if (taller < tallest) {
                tallest = taller;
                best = index + 1;
            }
        }
        return [groups.slice(0, best), groups.slice(best)].filter(column => column.length > 0);
    }

    onOpenChanged: {
        if (!open)
            return;

        lister.running = true;
        input.text = "";
        scroller.contentY = 0;
        input.forceActiveFocus();
        panel.appear();
    }

    // Also called over the launcher socket (shell.qml)
    property alias ipc: ipcHandler

    IpcHandler {
        id: ipcHandler
        target: "keybinds"

        function toggleKeybindMenu(): void {
            root.open = !root.open;
        }
    }

    Process {
        id: lister
        command: ["sh", "-c", "cd \"${XDG_CONFIG_HOME:-$HOME/.config}/mango\" && cat config.conf; cat local.conf 2>/dev/null"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.groups = root.parse(text);
                } catch (error) {
                    root.groups = [];
                }
            }
        }
    }

    FontMetrics {
        id: metrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.keybindFontSize
        font.weight: Theme.fontWeight
    }

    PanelWindow { // qmllint disable uncreatable-type
        id: window

        // Stays mapped while closed, just empty and click-through: mapping a
        // surface again took ~40 ms each open
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

            // Kept while searching so the panel doesn't shrink while typing
            property real lockedWidth: 0
            property real lockedHeight: 0

            visible: root.open
            floating: true
            width: Math.max(sheet.width, title.implicitWidth, lockedWidth) + Theme.keybindPadding * 2
            height: bar.height + scroller.height + Theme.keybindPadding

            Connections {
                target: sheet

                function onWidthChanged() {
                    if (root.query === "")
                        panel.lockedWidth = sheet.width;
                }
            }

            Connections {
                target: scroller

                function onFittedHeightChanged() {
                    if (root.query === "")
                        panel.lockedHeight = scroller.fittedHeight;
                }
            }

            Item {
                id: bar

                width: parent.width
                height: Theme.keybindPadding * 2

                Text {
                    id: title

                    anchors.centerIn: parent
                    text: Theme.keybindTitle
                    color: Theme.textColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.searchFontSize
                    font.weight: Font.Bold
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.keybindPadding
                    anchors.verticalCenter: title.verticalCenter
                    width: Theme.keybindSearchWidth
                    height: Theme.keyHeight + 6
                    radius: Theme.cornerRadius
                    color: Theme.keyColor
                    border.width: 1
                    border.color: input.text !== "" ? Theme.keyTextColor : Theme.dividerColor

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.keyPadding
                        anchors.rightMargin: Theme.keyPadding
                        spacing: Theme.keySpacing * 2

                        Text {
                            id: searchIcon
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.searchIcon
                            color: Theme.dimColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.keybindFontSize - 1
                        }

                        TextInput {
                            id: input

                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - searchIcon.width - parent.spacing
                            color: Theme.textColor
                            selectionColor: Theme.dividerColor
                            selectedTextColor: Theme.textColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.keybindFontSize - 1
                            font.weight: Theme.fontWeight
                            clip: true

                            onTextChanged: {
                                root.query = text;
                                scroller.contentY = 0;
                            }

                            Keys.onPressed: event => {
                                const ctrl = event.modifiers & Qt.ControlModifier;
                                const step = Theme.keybindRowHeight * 3;
                                const end = Math.max(0, scroller.contentHeight - scroller.height);

                                if (event.key === Qt.Key_Escape && text !== "")
                                    text = "";
                                else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    root.open = false;
                                else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_J))
                                    scroller.contentY = Math.min(scroller.contentY + step, end);
                                else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_K))
                                    scroller.contentY = Math.max(scroller.contentY - step, 0);
                                else if (event.key === Qt.Key_PageDown)
                                    scroller.contentY = Math.min(scroller.contentY + scroller.height, end);
                                else if (event.key === Qt.Key_PageUp)
                                    scroller.contentY = Math.max(scroller.contentY - scroller.height, 0);
                                else
                                    return;
                                event.accepted = true;
                            }

                            Text {
                                visible: input.text.length === 0
                                text: Theme.placeholder
                                color: Theme.dimColor
                                font: input.font
                            }
                        }
                    }
                }
            }

            // Only while the sheet doesn't fit
            Item {
                id: scrollbar

                readonly property real end: Math.max(0, scroller.contentHeight - scroller.height)

                visible: scrollbar.end > 0
                anchors.top: scroller.top
                anchors.bottom: scroller.bottom
                anchors.right: parent.right
                anchors.rightMargin: (Theme.keybindPadding - width) / 2
                width: Theme.keybindScrollbarWidth

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Theme.keyColor
                }

                Rectangle {
                    id: thumb

                    width: parent.width
                    height: Math.max(Theme.keybindRowHeight, parent.height * scroller.visibleArea.heightRatio)
                    y: scrollbar.end > 0 ? scroller.contentY / scrollbar.end * (parent.height - height) : 0
                    radius: width / 2
                    color: drag.containsMouse || drag.pressed ? Theme.keyTextColor : Theme.dividerColor
                }

                MouseArea {
                    id: drag

                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    function scrollTo(y) {
                        const track = scrollbar.height - thumb.height;
                        const fraction = track > 0 ? (y - thumb.height / 2) / track : 0;
                        scroller.contentY = Math.max(0, Math.min(fraction, 1)) * scrollbar.end;
                    }

                    onPressed: mouse => scrollTo(mouse.y - 4)
                    onPositionChanged: mouse => {
                        if (pressed)
                            scrollTo(mouse.y - 4);
                    }
                }
            }

            Flickable {
                id: scroller

                anchors.top: bar.bottom
                x: Theme.keybindPadding
                width: sheet.width
                // While searching, keeps the unfiltered height
                readonly property real fittedHeight: Math.min(contentHeight, window.screen.height * Theme.keybindMaxHeight - bar.height - Theme.keybindPadding)

                height: root.query === "" ? fittedHeight : Math.max(fittedHeight, panel.lockedHeight)
                contentWidth: sheet.width
                contentHeight: Math.max(sheet.height, empty.visible ? Theme.keybindRowHeight * 3 : 0)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Text {
                    id: empty

                    anchors.centerIn: parent
                    visible: root.columns.length === 0
                    text: Theme.keybindEmptyText
                    color: Theme.dimColor
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.keybindFontSize
                }

                Row {
                    id: sheet

                    Repeater {
                        model: root.columns

                        delegate: Row {
                            id: column

                            required property var modelData
                            required property int index

                            // Divider between the columns. Only the line hangs
                            // down: a Row skips zero-height items, and a full-
                            // height one would set the Row's height.
                            Item {
                                visible: column.index > 0
                                width: Theme.keybindColumnGap * 2
                                height: 1

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 1
                                    height: sheet.height - Theme.keybindGroupGap
                                    color: Theme.dividerColor
                                }
                            }

                            Column {
                                id: groups

                                // Fitted to the longest description, so the
                                // keys line up
                                readonly property real labelWidth: Math.ceil(Math.min(metrics.averageCharacterWidth * Theme.keybindMaxLabel, column.modelData.reduce((widest, group) => group.rows.reduce((most, row) => Math.max(most, metrics.advanceWidth(row.label + ":")), widest), 0)))

                                spacing: Theme.keybindGroupGap

                                Repeater {
                                    model: column.modelData

                                    delegate: Column {
                                        id: group

                                        required property var modelData

                                        Text {
                                            height: Theme.keybindRowHeight
                                            verticalAlignment: Text.AlignVCenter
                                            text: group.modelData.name
                                            color: Theme.textColor
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.keybindFontSize
                                            font.weight: Font.Bold
                                        }

                                        Repeater {
                                            model: group.modelData.rows

                                            delegate: Row {
                                                id: row

                                                required property var modelData

                                                height: Theme.keybindRowHeight
                                                spacing: Theme.keybindLabelGap

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: groups.labelWidth
                                                    text: row.modelData.label + ":"
                                                    textFormat: Text.PlainText
                                                    color: Theme.keyTextColor
                                                    elide: Text.ElideRight
                                                    font: metrics.font
                                                }

                                                Row {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    spacing: Theme.keySpacing

                                                    Repeater {
                                                        model: row.modelData.keys

                                                        delegate: KeyCap {
                                                            required property var modelData

                                                            text: modelData.text
                                                            outlined: true
                                                            border.width: modelData.cap ? 1 : 0
                                                            textColor: modelData.cap ? Theme.keyTextColor : Theme.dimColor
                                                            minWidth: modelData.cap ? Theme.keyHeight : 0
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
