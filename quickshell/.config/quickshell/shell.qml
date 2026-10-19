import Quickshell
import qs.bar
import qs.controlcenter
import qs.hotkeys
import qs.launcher
import qs.lockscreen
import qs.media
import qs.notifications
import qs.osd
import qs.wallpapers

// Entry point. Each module is added here as it gets built.
ShellRoot {
    Lock {
        id: lock

        // Panels leave the screen before the lockscreen takes its snapshot
        onAboutToLock: {
            controlCenter.hide();
            launcher.hide();
            history.hide();
            wallpapers.hide();
            hotkeys.hide();
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
        onWallpapersRequested: wallpapers.show()
    }

    Launcher {
        id: launcher
    }

    // Separate wallpaper app (Super+W)
    WallpaperApp {
        id: wallpapers
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

    // Hold Super for three seconds (hypr/frame/hotkeys.lua); closed while locked
    HotkeyOverlay {
        id: hotkeys
        hidden: lock.active
    }

    // Shows fader, mute, volume and layout changes; never on the lockscreen
    Osd {
        hidden: lock.active
    }
}
