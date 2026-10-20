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
// `qs ipc call lock preview` shows the same screens for a few seconds without locking
// the session (for screen recordings): snapshot, the surfaces as overlays, then the
// unlock animation by itself.
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
    // Preview: the lock surfaces as overlays instead of a session lock
    property bool previewMode: false
    property bool previewing: false
    readonly property bool active: hidingForLock || capturing || sessionLock.locked || previewing

    // The screen that shows clock, password and panels; the others only show the blur.
    // It is the monitor you are on when locking.
    property string loginScreen: ""

    function lock() {
        // A real lock (Super+L, hypridle, before sleep) wins over a running preview,
        // including one whose unlock animation is still playing
        if (previewing || previewMode)
            cancelPreview();
        if (active)
            return;
        previewMode = false;
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
        if (sessionLock.locked || previewing)
            return;
        fallback.stop();
        if (previewMode) {
            previewing = true;
            previewEnd.restart();
        } else {
            sessionLock.locked = true;
        }
        capturing = false;
        // The snapshot is taken; the moving wallpaper behind it can rest now
        wallpapers("pause");
    }

    // Like lock(), but the surfaces come as overlays and leave again after `seconds`
    function preview(seconds) {
        if (active)
            return;
        previewMode = true;
        previewEnd.interval = Math.max(1, seconds) * 1000;
        lockContext.reset();
        loginScreen = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
        hidingForLock = true;
        root.aboutToLock();
        exitDelay.restart();
    }

    // Drops a preview at once, without its unlock animation
    function cancelPreview() {
        previewEnd.stop();
        release.stop();
        exitDelay.stop();
        fallback.stop();
        capturing = false;
        previewing = false;
        previewMode = false;
        hidingForLock = false;
        lockContext.reset();
    }

    Timer {
        id: previewEnd
        interval: 4000
        onTriggered: {
            // Only ever ends a preview: a real lock is released by the password alone
            if (!root.previewing || sessionLock.locked)
                return;
            lockContext.unlocking = true;
            release.restart();
        }
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
            previewEnd.stop();
            sessionLock.locked = false;
            root.previewing = false;
            root.previewMode = false;
            lockContext.reset();
            root.hidingForLock = false;
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

    // Preview: the same surfaces as overlays, no session lock behind them
    Variants {
        model: root.previewing ? Quickshell.screens : []

        PanelWindow {
            id: previewWindow

            required property ShellScreen modelData

            screen: modelData
            color: Theme.bg
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-lock-preview"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            LockSurface {
                anchors.fill: parent
                context: lockContext
                snapshot: root.snapshotPath(previewWindow.modelData)
                showLogin: Quickshell.screens.length === 1 || previewWindow.modelData.name === root.loginScreen
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

    // ── Idle and sleep (what hypridle used to do) ────────────

    // Lock after Config.idleLockMinutes without input; Stay awake in the control center
    // (an idle inhibitor) and video players that inhibit idle hold it off
    IdleMonitor {
        enabled: Config.idleLockMinutes > 0
        timeout: Config.idleLockMinutes * 60
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.lock()
    }

    // Screens off a while later, on again with the first input
    IdleMonitor {
        enabled: Config.idleScreenOffMinutes > 0
        timeout: Config.idleScreenOffMinutes * 60
        respectInhibitors: true
        onIsIdleChanged: root.dpms(!isIdle)
    }

    function dpms(on) {
        Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.dpms({ action = "${on ? "on" : "off"}" })`]);
    }

    // logind's signals: PrepareForSleep before suspend (lock first) and after it (screens
    // on), Lock from `loginctl lock-session`. gdbus comes with glib2.
    Process {
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes("PrepareForSleep (true")) {
                    root.lock();
                    sleepRelease.restart();
                } else if (line.includes("PrepareForSleep (false")) {
                    root.dpms(true);
                    sleepDelay.running = true;
                } else if (/\.Session\.Lock \(\)/.test(line)) {
                    root.lock();
                }
            }
        }
    }

    // Holds suspend back (a delay lock, a few seconds at most) until the lockscreen is up,
    // so waking up never shows the desktop for a moment
    Process {
        id: sleepDelay
        running: true
        command: ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=frameshell",
            "--why=lock the screen before sleep", "sleep", "infinity"]
    }

    // Lets the system sleep once the lock is engaged, or after 2 s whatever happens
    Timer {
        id: sleepRelease
        interval: 100
        repeat: true
        property int waited: 0
        onTriggered: {
            waited += interval;
            if (sessionLock.locked || waited >= 2000) {
                stop();
                waited = 0;
                sleepDelay.running = false;
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

        // For screen recordings: the lockscreen for `seconds`, then the unlock animation
        function preview(seconds: int): void {
            root.preview(seconds > 0 ? seconds : 4);
        }
    }
}
