import QtQuick
import Quickshell
import qs

// Lock UI in a normal window: `qs -p ~/.config/quickshell/lock/test.qml`. PAM
// still checks the password, and the face if howdy is set up.
// LOCK_PREVIEW=prompt|typed|error|busy|face|noface opens it in that state.
ShellRoot {
    LockContext {
        id: lockContext
        onUnlocked: Qt.quit()

        Component.onCompleted: {
            const state = Quickshell.env("LOCK_PREVIEW") ?? "";
            if (state === "")
                return;
            showPrompt = true;
            if (state === "typed" || state === "busy")
                currentText = "password";
            if (state === "busy")
                unlockInProgress = true;
            if (state === "error")
                Qt.callLater(() => fail("Wrong password"));
            if (state === "face")
                faceScanning = true;
            if (state === "noface") {
                message = Theme.faceFailedText;
                messageIsError = false;
            }
        }
    }

    FloatingWindow {
        implicitWidth: 960
        implicitHeight: 540
        color: Theme.background

        LockSurface {
            anchors.fill: parent
            context: lockContext
        }
    }

    Connections {
        target: Quickshell
        function onLastWindowClosed() {
            Qt.quit();
        }
    }
}
