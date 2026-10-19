import Quickshell
import qs.bar
import qs.controlcenter
import qs.launcher
import qs.lockscreen

// Entry point. Each module is added here as it gets built.
ShellRoot {
    Lock {
        id: lock

        // Panels leave the screen before the lockscreen takes its snapshot
        onAboutToLock: {
            controlCenter.hide();
            launcher.hide();
        }
    }

    Bar {
        hidden: lock.active
        onControlCenterRequested: screen => controlCenter.toggle(screen)
    }

    ControlCenter {
        id: controlCenter
        onLockRequested: lock.lock()
    }

    Launcher {
        id: launcher
    }
}
