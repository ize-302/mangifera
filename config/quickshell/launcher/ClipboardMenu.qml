import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Clipboard history (cliphist). Enter copies the entry again.
Scope {
    id: root

    property alias open: menu.open
    // `cliphist list` lines, newest first: "<id>\t<preview>"
    property list<string> entries

    // cliphist's image preview: "[[ binary data 326 KiB png 1919x1026 ]]"
    function image(entry) {
        return entry.match(/\t\[\[ binary data (\S+ \S+) (\S+) (\d+)x(\d+) \]\]$/);
    }

    function search(query, entries) {
        const words = query.toLowerCase().split(/\s+/).filter(word => word);
        if (words.length === 0)
            return entries;

        return entries.filter(entry => {
            const text = entry.toLowerCase();
            return words.every(word => text.includes(word));
        });
    }

    onOpenChanged: if (open)
        lister.running = true

    IpcHandler {
        target: "clipboard"

        function toggleClipboardMenu(): void {
            root.open = !root.open;
        }
    }

    Process {
        id: lister
        command: ["cliphist", "list"]

        stdout: StdioCollector {
            onStreamFinished: root.entries = text.split("\n").filter(line => line)
        }
    }

    SearchMenu {
        id: menu

        floating: true
        aboveBar: true
        showCount: true
        panelWidth: Theme.clipboardWidth
        results: root.search(query, root.entries)
        label: entry => root.image(entry) ? "Image" : entry.slice(entry.indexOf("\t") + 1)
        hint: entry => {
            const image = root.image(entry);
            return image ? [image[2].toUpperCase(), image[3] + "×" + image[4], image[1]] : [];
        }
        emptyText: Theme.clipboardEmptyText

        // cliphist finds the entry by its leading id
        onAccepted: entry => Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "sh", entry])
    }
}
