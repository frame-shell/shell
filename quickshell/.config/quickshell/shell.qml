import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.bar
import qs.canvas
import qs.controlcenter
import qs.editor
import qs.gallery
import qs.hotkeys
import qs.keyboard
import qs.launcher
import qs.lockscreen
import qs.media
import qs.notifications
import qs.osd
import qs.screenshot
import qs.services
import qs.settings
import qs.wallpapers

// Entry point. Each module is added here as it gets built.
ShellRoot {
    // Singletons only come to life when something uses them; the Spotify one must listen
    // for the Spicetify extension from the start, not from the first "s" in the launcher
    Scope {
        Component.onCompleted: {
            Spotify.refresh();
            // A shell that died while the screen was locked left the wallpaper frozen
            // (frame-wallpaper pause); this one lets it run again
            Quickshell.execDetached(["sh", "-c", 'w="$HOME/.local/bin/frame-wallpaper"; [ -x "$w" ] && "$w" resume-if-paused']);
        }
    }

    // The media keys (frame/shell.lua): qs ipc call player toggle|next|prev. Like the bar:
    // whatever is playing, then Spotify, then any player; no playerctl needed
    Scope {
        id: mediaKeys

        readonly property MprisPlayer player: {
            const list = Mpris.players.values;
            return list.find(p => p.isPlaying) ?? list.find(p => p.identity === "Spotify") ?? list[0] ?? null;
        }

        IpcHandler {
            target: "player"

            function toggle(): void { mediaKeys.player?.togglePlaying(); }
            function next(): void { mediaKeys.player?.next(); }
            function prev(): void { mediaKeys.player?.previous(); }
        }
    }

    Lock {
        id: lock

        // Panels leave the screen before the lockscreen takes its snapshot
        onAboutToLock: {
            controlCenter.hide();
            launcher.hide();
            history.hide();
            wallpapers.hide();
            keyboard.hide();
            hotkeys.hide();
            overview.close();
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
        onKeyboardRequested: keyboard.show()
        onSettingsRequested: settings.show()
    }

    Launcher {
        id: launcher
    }

    // Separate wallpaper app (Super+W)
    // Still wallpapers and the plain background (the moving ones come from frame-wallpaper)
    Backdrop {}

    WallpaperApp {
        id: wallpapers
    }

    // AULA F75 lighting, Fn keys and per-key colors (Super+K, keyboard package)
    KeyboardApp {
        id: keyboard
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

    // Hold Super for 1.5 seconds (hypr/frame/hotkeys.lua); closed while locked or
    // while Super is busy with the canvas overview
    HotkeyOverlay {
        id: hotkeys
        hidden: lock.active || overview.open
    }

    // Infinite canvas: Super+wheel zooms out to every window (frame layout canvas)
    CanvasOverview {
        id: overview
        hidden: lock.active
    }

    // Infinite canvas: dragging empty canvas moves the view
    CanvasDesk {}

    // Infinite canvas: pictures of the windows on screen, for the overview's off-screen ones
    CanvasThumbs {}

    // Shows fader, mute, volume and layout changes; never on the lockscreen
    Osd {
        hidden: lock.active
    }

    // Print: region or window, Shift+Print: the screen (hypr/frame/shell.lua)
    Screenshot {
        hidden: lock.active
    }

    // Editors for recordings (cuts, blur boxes, pictures, levels per channel) and pictures
    // (blur, pictures, crop): "edit" on a notification or in the media app; own window
    EditorWindow {}

    // Screenshots and recordings: browse, delete many at once, open in the editor (Super+G)
    MediaApp {
        id: media
    }

    // Theme, layout, the shell's own settings, sound, modules and system (Super+, or
    // "settings" in the control center)
    SettingsApp {
        id: settings
        onWallpapersRequested: wallpapers.show()
        onKeyboardRequested: keyboard.show()
    }
}
