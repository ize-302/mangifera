pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs

// Session locker, started by ~/.local/bin/lock-screen. Preview with `qs -p
// ~/.config/quickshell/lock/test.qml`.
ShellRoot {
    LockContext {
        id: lockContext

        onUnlocked: {
            // Unlock before exiting, or mango stays locked with nothing to type
            // into
            lock.locked = false;
            Qt.quit();
        }
    }

    WlSessionLock {
        id: lock
        locked: true

        WlSessionLockSurface {
            color: Theme.background

            LockSurface {
                anchors.fill: parent
                context: lockContext
            }
        }
    }
}
