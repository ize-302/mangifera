import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import qs

// State shared by every monitor's lock surface.
Scope {
    id: root

    signal unlocked
    signal failed

    property string currentText: ""
    property bool showPrompt: false
    property bool unlockInProgress: false
    property string message: ""
    property bool messageIsError: false
    // Last PAM message this attempt, e.g. pam_faillock's lockout notice
    property string pamInfo: ""
    property bool capsLock: false

    onCurrentTextChanged: {
        if (currentText !== "")
            message = "";
        promptTimer.restart();
    }

    onShowPromptChanged: {
        if (!showPrompt) {
            currentText = "";
            message = "";
        }
    }

    function tryUnlock() {
        if (currentText === "" || unlockInProgress)
            return;

        unlockInProgress = true;
        message = "";
        pamInfo = "";
        pam.start();
    }

    function fail(text) {
        currentText = "";
        message = text;
        messageIsError = true;
        unlockInProgress = false;
        failed();
    }

    Timer {
        id: promptTimer
        interval: Theme.promptTimeout * 1000
        running: root.showPrompt && !root.unlockInProgress
        onTriggered: root.showPrompt = false
    }

    PamContext {
        id: pam

        // Same stack swaylock uses
        config: "login"

        onPamMessage: {
            if (responseRequired) {
                respond(root.currentText);
            } else if (message !== "") {
                root.pamInfo = message;
                root.message = message;
                root.messageIsError = messageIsError;
            }
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                root.unlockInProgress = false;
                root.unlocked();
            } else if (result === PamResult.MaxTries) {
                root.fail("Too many attempts");
            } else if (result === PamResult.Error) {
                root.fail("Authentication error");
            } else {
                // Keep PAM's reason: a locked-out account rejects the right
                // password too
                root.fail(root.pamInfo || "Wrong password");
            }
        }

        onError: error => root.fail("Authentication error: " + PamError.toString(error))
    }

    // Caps lock lights, same loop as the launcher's CapsLock.qml
    Process {
        id: capsWatcher

        command: ["setpriv", "--pdeathsig", "KILL", "bash", "-c", `
enable -f /usr/lib/bash/sleep sleep 2>/dev/null
last=
while :; do
	lit=0
	for path in /sys/class/leds/*::capslock/brightness; do
		read -r value <"$path" 2>/dev/null && [ -n "$value" ] && [ "$value" != 0 ] && lit=1
	done
	if [ "$lit" != "$last" ]; then
		echo "$lit"
		last=$lit
	fi
	sleep ${Theme.capsLockPoll / 1000}
done
`]
        running: true

        stdout: SplitParser {
            onRead: line => root.capsLock = line.trim() === "1"
        }
    }
}
