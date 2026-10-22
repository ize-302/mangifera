import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs

// The bar's volume module, with a music note while something plays (waybar's
// volume module can't know). Writes $XDG_RUNTIME_DIR/volume.json and signals
// waybar (SIGRTMIN+10). Class: "", "mid", "loud", "high", "over" or "muted",
// for style.css.
Scope {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property int percent: Math.round((sink?.audio?.volume ?? 0) * 100)
    readonly property bool playing: Mpris.players.values.some(player => player.isPlaying)

    readonly property string level: percent >= 101 ? "over" : percent >= 71 ? "high" : percent >= 51 ? "loud" : percent >= 31 ? "mid" : ""

    readonly property string status: {
        if (!sink)
            return JSON.stringify({
                text: ""
            });
        // Spacing after each glyph tuned so they look even
        const icon = playing && !muted ? Theme.musicIcon + " " : muted ? Theme.volumeMutedIcon + " " : percent >= 51 ? Theme.volumeHighIcon + "  " : Theme.volumeLowIcon + " ";
        return JSON.stringify({
            text: icon + percent + "%",
            class: muted ? "muted" : level
        });
    }

    onStatusChanged: file.setText(status + "\n")
    Component.onCompleted: file.setText(status + "\n")

    // Volumes are only there for tracked nodes
    PwObjectTracker {
        objects: [root.sink]
    }

    FileView {
        id: file

        path: Quickshell.env("XDG_RUNTIME_DIR") + "/volume.json"
        printErrors: false
        onSaved: Quickshell.execDetached(["pkill", "-RTMIN+10", "-x", "waybar"])
    }
}
