pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Clipboard history for the launcher (;), from cliphist. Hyprland starts
// `wl-paste --watch cliphist store` (hypr/frame/shell.lua), which records every copy.
//
// entries: [{ line (as cliphist prints it, needed to decode or delete), id, text, image,
//   preview (path of the decoded picture once it is there, else "") }]
// Pictures are decoded once into $XDG_RUNTIME_DIR/qs-clip so the launcher can show them.
Singleton {
    id: root

    property var entries: []
    property bool loaded: false
    readonly property string previewDir: `${Quickshell.env("XDG_RUNTIME_DIR")}/qs-clip`

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
            const id = line.slice(0, tab);
            // "5 MiB png 2560x1440": the format is the third word
            const ext = bin ? (bin[1].split(" ")[2] ?? "png") : "";
            out.push({ line, id, text: bin ? bin[1] : body, image: !!bin, preview: "", file: bin ? `${previewDir}/${id}.${ext}` : "" });
        }
        entries = out;
        loaded = true;
        decodePictures();
    }

    // Writes every picture that is not decoded yet (the newest 40), drops thumbnails of
    // entries that left the history, then marks the entries whose file is there
    function decodePictures() {
        const pictures = entries.filter(e => e.image).slice(0, 40);
        if (pictures.length === 0)
            return;
        thumbs.command = ["sh", "-c", `
            dir=$1; shift
            mkdir -p "$dir"
            keep=" "
            for line in "$@"; do
                id=$(printf '%s' "$line" | cut -f1)
                ext=$(printf '%s' "$line" | awk '{print $7}')
                keep="$keep$id.$ext "
                f="$dir/$id.$ext"
                [ -s "$f" ] || printf '%s' "$line" | cliphist decode > "$f" 2>/dev/null || rm -f "$f"
            done
            for f in "$dir"/*; do
                [ -e "$f" ] || continue
                case "$keep" in *" $(basename "$f") "*) ;; *) rm -f "$f" ;; esac
            done`, "clip-thumbs", previewDir].concat(pictures.map(e => e.line));
        thumbs.running = true;
    }

    Process {
        id: thumbs
        onExited: {
            root.entries = root.entries.map(e => e.image ? Object.assign({}, e, { preview: e.file }) : e);
        }
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
