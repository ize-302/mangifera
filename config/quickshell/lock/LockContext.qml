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
    // howdy is installed and has this user's face
    property bool faceAvailable: false
    property bool faceScanning: false
    // Set once either check passes, so the other can't unlock twice
    property bool done: false

    onCurrentTextChanged: {
        if (currentText !== "")
            message = "";
        promptTimer.restart();
    }

    onShowPromptChanged: {
        if (showPrompt) {
            startFace();
        } else {
            currentText = "";
            message = "";
            // Turn the camera off with the field
            stopFace();
        }
    }

    function tryUnlock() {
        if (unlockInProgress)
            return;
        // Enter on an empty field looks again
        if (currentText === "") {
            startFace();
            return;
        }

        unlockInProgress = true;
        message = "";
        pamInfo = "";
        pam.start();
    }

    function startFace() {
        if (!faceAvailable || faceScanning || done)
            return;
        message = "";
        faceScanning = facePam.start();
    }

    function stopFace() {
        if (facePam.active)
            facePam.abort();
        faceScanning = false;
    }

    function succeed() {
        if (done)
            return;
        done = true;
        stopFace();
        if (pam.active)
            pam.abort();
        unlockInProgress = false;
        unlocked();
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
                root.succeed();
            } else if (root.done) {
                return;
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

    // Face check beside the password one, from pam/face. A failed scan only
    // leaves a note: the typed password stays and nothing shakes.
    PamContext {
        id: facePam

        configDirectory: Quickshell.shellPath("pam")
        config: "face"

        onPamMessage: {
            // howdy never asks for input; answering keeps PAM from waiting
            if (responseRequired)
                respond("");
        }

        onCompleted: result => {
            root.faceScanning = false;
            if (result === PamResult.Success) {
                root.succeed();
            } else if (!root.done && root.showPrompt && root.message === "") {
                root.message = Theme.faceFailedText;
                root.messageIsError = false;
            }
        }

        onError: () => root.faceScanning = false
    }

    // Face unlock is on when howdy is installed and has this user's face
    Process {
        command: ["sh", "-c", 'test -e /usr/lib/security/pam_howdy.so && test -r "/etc/howdy/models/$USER.dat"']
        running: true
        onExited: code => {
            root.faceAvailable = code === 0;
            // The field can be up before this answers
            if (root.faceAvailable && root.showPrompt)
                root.startFace();
        }
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
