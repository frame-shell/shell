pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Package updates for the bar: repository ones the way checkupdates finds them (it
// syncs into a temporary database, so nothing changes on the system) and AUR ones from
// paru or yay. Checked a minute after start and then every 30 minutes; a click on the
// number opens Ghostty with the update and `frame update`, and checks again when it closes.
//
// list: [{ name, from, to, aur }]
Singleton {
    id: root

    property var list: []
    readonly property int total: list.length
    readonly property int aurCount: list.filter(p => p.aur).length
    property bool checking: false
    property bool updating: false

    function check() {
        if (checker.running || updating)
            return;
        checking = true;
        checker.running = true;
    }

    // "name 1.0-1 -> 1.1-1", one per line; the AUR helpers print the same
    function parse(text) {
        const out = [];
        for (const line of text.split("\n")) {
            const aur = line.startsWith("aur ");
            const m = /^(\S+) (\S+) -> (\S+)/.exec(aur ? line.slice(4) : line);
            if (m)
                out.push({ name: m[1], from: m[2], to: m[3], aur });
        }
        return out;
    }

    function update() {
        if (updating)
            return;
        updating = true;
        updater.running = true;
    }

    Process {
        id: checker
        // Like checkupdates, without pacman-contrib: a copy of the sync databases in /tmp
        // (memory, not disk), refreshed there, then compared with what is installed; the
        // system's own databases stay untouched. AUR lines get an "aur " prefix.
        command: ["sh", "-c", 'db="${TMPDIR:-/tmp}/frame-updates-$(id -u)"; mkdir -p "$db"; ln -sfn /var/lib/pacman/local "$db/local"; '
            + 'if command -v fakeroot >/dev/null && fakeroot -- pacman -Sy --dbpath "$db" --logfile /dev/null >/dev/null 2>&1; then '
            + 'pacman -Qu --dbpath "$db" 2>/dev/null; fi; '
            + 'if command -v paru >/dev/null; then paru -Qua 2>/dev/null; elif command -v yay >/dev/null; then yay -Qua 2>/dev/null; fi | sed "s/^/aur /"; true']
        stdout: StdioCollector {
            onStreamFinished: {
                root.list = root.parse(this.text);
                root.checking = false;
            }
        }
    }

    // Its own Ghostty process (not the single-instance one), so closing the window ends it
    Process {
        id: updater
        command: ["ghostty", "--gtk-single-instance=false", "--title=frameshell update", "-e", "sh", "-c",
            'if command -v paru >/dev/null; then paru -Syu; elif command -v yay >/dev/null; then yay -Syu; else sudo pacman -Syu; fi; '
            + '[ -x "$HOME/.local/bin/frame" ] && "$HOME/.local/bin/frame" update; '
            + 'printf "\\nDone. Enter closes this window."; read _']
        onExited: {
            root.updating = false;
            root.check();
        }
    }

    Timer {
        interval: 60 * 1000
        running: true
        onTriggered: root.check()
    }

    Timer {
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        onTriggered: root.check()
    }
}
