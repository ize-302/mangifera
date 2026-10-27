import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Pomodoro timer: focus, then a short break, a long one every pomodoroRounds.
// Each phase ends with a notification and waits to be started. Shown on the
// bar (Bar.qml). State persists across daemon restarts.
Scope {
    id: root

    // "focus", "short" or "long"
    property string phase: "focus"
    property bool running: false
    // ms since the epoch, while running
    property real endsAt: 0
    // Seconds
    property int left: lengthOf("focus")
    // Focus sessions since the last long break
    property int done: 0

    readonly property int length: lengthOf(phase)
    // Nothing started: the bar module hides
    readonly property bool idle: !running && phase === "focus" && left === length && done === 0
    readonly property string label: phase === "focus" ? "Focus" : phase === "short" ? "Short break" : "Long break"
    readonly property string clock: Math.floor(left / 60) + ":" + String(left % 60).padStart(2, "0")

    function lengthOf(phase) {
        return (phase === "focus" ? Theme.pomodoroFocus : phase === "short" ? Theme.pomodoroShortBreak : Theme.pomodoroLongBreak) * 60;
    }

    function start() {
        if (running)
            return;
        endsAt = Date.now() + left * 1000;
        running = true;
        save();
    }

    function pause() {
        if (!running)
            return;
        tick();
        running = false;
        save();
    }

    function toggle() {
        if (running)
            pause();
        else
            start();
    }

    // Without counting this one
    function skip() {
        advance(false);
    }

    function reset() {
        running = false;
        phase = "focus";
        done = 0;
        left = length;
        save();
    }

    function tick() {
        if (!running)
            return;
        left = Math.max(0, Math.ceil((endsAt - Date.now()) / 1000));
        if (left === 0)
            finish();
    }

    function finish() {
        const wasFocus = phase === "focus";
        advance(true);
        const body = wasFocus ? "Time for a " + (phase === "long" ? "long" : "short") + " break." : "Time to focus.";
        Quickshell.execDetached(["notify-send", "-a", "Pomodoro", "-i", "appointment-soon", (wasFocus ? "Focus" : "Break") + " over", body]);
    }

    // A finished focus session counts towards the long break
    function advance(finished) {
        running = false;
        if (phase === "focus") {
            if (finished)
                done += 1;
            phase = done >= Theme.pomodoroRounds ? "long" : "short";
        } else {
            if (phase === "long")
                done = 0;
            phase = "focus";
        }
        left = length;
        save();
    }

    function save() {
        stateFile.setText(JSON.stringify({
            phase: phase,
            running: running,
            endsAt: endsAt,
            left: left,
            done: done
        }));
    }

    Timer {
        running: root.running
        repeat: true
        interval: 1000
        onTriggered: root.tick()
    }

    // Also called over the launcher socket (shell.qml)
    property alias ipc: ipcHandler

    IpcHandler {
        id: ipcHandler
        target: "pomodoro"

        function toggle(): void {
            root.toggle();
        }

        function skip(): void {
            root.skip();
        }

        function reset(): void {
            root.reset();
        }
    }

    // Restores saved state; one that ended meanwhile finishes now
    FileView {
        id: stateFile

        path: Quickshell.statePath("pomodoro.json")
        blockLoading: true
        printErrors: false

        onLoaded: {
            try {
                const state = JSON.parse(text());
                root.phase = ["focus", "short", "long"].includes(state.phase) ? state.phase : "focus";
                root.done = state.done ?? 0;
                root.left = state.left ?? root.length;
                root.endsAt = state.endsAt ?? 0;
                root.running = state.running ?? false;
                // After the load, as finishing saves to this same file
                Qt.callLater(root.tick);
            } catch (error) {}
        }
    }
}
