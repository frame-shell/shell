import Quickshell
import qs.bar
import qs.controlcenter
import qs.launcher
import qs.lockscreen
import qs.media
import qs.notifications

// Entry point. Each module is added here as it gets built.
ShellRoot {
    Lock {
        id: lock

        // Panels leave the screen before the lockscreen takes its snapshot
        onAboutToLock: {
            controlCenter.hide();
            launcher.hide();
            history.hide();
        }
    }

    Bar {
        hidden: lock.active
        onControlCenterRequested: screen => {
            history.hide();
            controlCenter.toggle(screen);
        }
        onHistoryRequested: screen => {
            controlCenter.hide();
            history.toggle(screen);
        }
    }

    ControlCenter {
        id: controlCenter
        onLockRequested: lock.lock()
    }

    Launcher {
        id: launcher
    }

    // Popups step aside while a panel on the right is open
    Popups {
        rightOffset: controlCenter.open ? (controlCenter.mixerOpen ? 1318 : 626)
            : history.open ? 486
            : 14
    }

    History {
        id: history
    }

    SpotifyPopup {}
}
