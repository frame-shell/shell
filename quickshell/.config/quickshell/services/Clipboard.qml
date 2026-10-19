pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Clipboard history for the launcher (;), from cliphist. Hyprland starts
// `wl-paste --watch cliphist store` (hypr/frame/shell.lua), which records every copy.
//
// entries: [{ line (as cliphist prints it, needed to decode or delete), id, text, image }]
Singleton {
    id: root

    property var entries: []
    property bool loaded: false

    function refresh() {
        list.running = true;
    }

    function parse(text) {
        const out = [];
        for (const line of text.split("\n")) {
            const tab = line.indexOf("\t");
            if (tab < 0)
                continue;
            const body = line.slice(tab + 1);
            // Pictures show up as "[[ binary data 1.2 MiB png 1920x1080 ]]"
            const bin = /^\[\[ binary data (.+) \]\]$/.exec(body);
            out.push({ line, id: line.slice(0, tab), text: bin ? bin[1] : body, image: !!bin });
        }
        entries = out;
        loaded = true;
    }

    function copy(entry) {
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$0" | cliphist decode | wl-copy', entry.line]);
    }

    function remove(entry) {
        entries = entries.filter(e => e.id !== entry.id);
        Quickshell.execDetached(["sh", "-c", 'printf "%s" "$0" | cliphist delete', entry.line]);
    }

    Process {
        id: list
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }
}
