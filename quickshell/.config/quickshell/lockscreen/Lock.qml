import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config

// Session lock with a blurred snapshot of the desktop behind it.
//
// `qs ipc call lock lock` (Super+L, hypridle) runs:
//   1. aboutToLock() and `active`, so the bar and open panels leave the screen (400 ms)
//   2. a ScreencopyView snapshot of every screen, saved to $XDG_RUNTIME_DIR
//   3. the real session lock; each LockSurface blurs its snapshot in
// Unlocking plays the surface animation backwards, then releases the lock.
Scope {
    id: root

    signal aboutToLock()

    // True while the snapshots are taken, before the session is locked
    property bool capturing: false
    property int pendingSnapshots: 0

    function snapshotPath(screen) {
        return `${Quickshell.env("XDG_RUNTIME_DIR")}/qs-lock-${screen?.name ?? "screen"}.png`;
    }

    // True from Super+L until the session is unlocked again; the bar hides meanwhile
    property bool hidingForLock: false
    readonly property bool active: hidingForLock || capturing || sessionLock.locked

    function lock() {
        if (active)
            return;
        context.reset();
        hidingForLock = true;
        root.aboutToLock();
        // Give the bar and open panels time to leave before the snapshot
        exitDelay.restart();
    }

    function capture() {
        pendingSnapshots = Quickshell.screens.length;
        capturing = true;
        // Lock anyway if a snapshot never arrives
        fallback.restart();
    }

    Timer {
        id: exitDelay
        interval: 400
        onTriggered: root.capture()
    }

    function snapshotDone() {
        pendingSnapshots -= 1;
        if (pendingSnapshots <= 0)
            engage();
    }

    function engage() {
        if (sessionLock.locked)
            return;
        fallback.stop();
        sessionLock.locked = true;
        capturing = false;
    }

    Timer {
        id: fallback
        interval: 1500
        onTriggered: root.engage()
    }

    LockContext {
        id: context

        onUnlocked: {
            unlocking = true;
            release.restart();
        }
    }

    // Lets the exit animation finish before the lock goes away
    Timer {
        id: release
        interval: Theme.anim.slow
        onTriggered: {
            sessionLock.locked = false;
            context.reset();
            root.hidingForLock = false;
        }
    }

    // Step 2: a transparent overlay per screen that grabs one frame of the desktop
    Variants {
        model: root.capturing ? Quickshell.screens : []

        PanelWindow {
            id: snapshotWindow

            required property ShellScreen modelData

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-lock-snapshot"
            // Keeps keystrokes away from apps during the short capture
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            ScreencopyView {
                id: view

                anchors.fill: parent
                captureSource: snapshotWindow.modelData
                live: false

                onHasContentChanged: {
                    if (!hasContent)
                        return;
                    grabToImage(result => {
                        result.saveToFile(root.snapshotPath(snapshotWindow.modelData));
                        root.snapshotDone();
                    });
                }
            }
        }
    }

    // Step 3: the actual lock, one surface per screen
    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            id: surface

            color: Theme.bg

            LockSurface {
                anchors.fill: parent
                context: context
                snapshot: root.snapshotPath(surface.screen)
            }
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            root.lock();
        }

        function isLocked(): bool {
            return sessionLock.locked;
        }
    }
}
