import QtQuick
import Quickshell
import Quickshell.Hyprland
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
//
// As the login screen (`frame login`): greetd starts the session without a greeter and
// ~/.local/state/frameshell/login says "lock", so the shell locks as soon as it is up.
// A marker in $XDG_RUNTIME_DIR remembers the first unlock, so a restarted shell in the
// same session does not lock again.
Scope {
    id: root

    readonly property string loginStatePath: `${Quickshell.env("HOME")}/.local/state/frameshell/login`
    readonly property string unlockedMarker: `${Quickshell.env("XDG_RUNTIME_DIR")}/frame-session-unlocked`

    // Only the very first shell of the session locks; any other start lets wallpapers that
    // a previous shell paused run again (it may have gone away while the screen was locked)
    Process {
        id: loginCheck
        command: ["sh", "-c", `[ "$(cat "$1" 2>/dev/null)" = lock ] && [ ! -e "$2" ]`, "frame-login", root.loginStatePath, root.unlockedMarker]
        running: true
        onExited: code => {
            if (code === 0)
                root.lock();
            else
                root.wallpapers("resume-if-paused");
        }
    }

    function markUnlocked() {
        Quickshell.execDetached(["touch", unlockedMarker]);
    }

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

    // The screen that shows clock, password and panels; the others only show the blur.
    // It is the monitor you are on when locking.
    property string loginScreen: ""

    function lock() {
        if (active)
            return;
        lockContext.reset();
        loginScreen = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
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
        // The snapshot is taken; the moving wallpaper behind it can rest now
        wallpapers("pause");
    }

    // frame-wallpaper pause|resume (wallpaper package); nothing happens without it
    function wallpapers(action) {
        Quickshell.execDetached(["sh", "-c", `w="$HOME/.local/bin/frame-wallpaper"; [ -x "$w" ] && "$w" "$1"`, "frame-lock", action]);
    }

    Timer {
        id: fallback
        interval: 1500
        onTriggered: root.engage()
    }

    LockContext {
        id: lockContext

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
            lockContext.reset();
            root.hidingForLock = false;
            root.markUnlocked();
            root.wallpapers("resume");
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
                context: lockContext
                snapshot: surface.screen ? root.snapshotPath(surface.screen) : ""
                showLogin: Quickshell.screens.length === 1 || surface.screen?.name === root.loginScreen
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
