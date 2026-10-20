pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// File and folder search for the launcher (/), with plain find (no extra package). Hidden
// folders and the usual build and dependency folders (node_modules, target, build, dist,
// __pycache__, venvs) are skipped, so caches and build output stay out. The last word is
// the name to look for; words before it narrow down the path ("/ dev notes" finds notes
// under Dev).
//
// results: [{ path, name, dir (parent folder), isDir, depth }]
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string base: Config.fileSearchRoot !== "" ? Config.fileSearchRoot : home

    property string query: ""
    property var results: []
    property bool searching: false

    function search(text) {
        const q = text.trim();
        if (q === query)
            return;
        query = q;
        if (q === "") {
            results = [];
            searching = false;
            return;
        }
        searching = true;
        debounce.restart();
    }

    // "~/Dev/notes.md" for the launcher
    function pretty(path) {
        return path.startsWith(home) ? `~${path.slice(home.length)}` : path;
    }

    function rank(lines, q) {
        const words = q.toLowerCase().split(/\s+/);
        const name = words[words.length - 1];
        const narrow = words.slice(0, -1);
        const out = [];
        for (const line of lines) {
            const tab = line.indexOf("\t");
            if (tab < 0)
                continue;
            const isDir = line.slice(0, tab) === "d";
            const path = line.slice(tab + 1).replace(/\/$/, "");
            const lower = path.slice(base.length).toLowerCase();
            if (!narrow.every(w => lower.includes(w)))
                continue;
            const fileName = path.slice(path.lastIndexOf("/") + 1);
            const n = fileName.toLowerCase();
            const depth = lower.split("/").length;
            const score = (n === name ? 100 : n.startsWith(name) ? 50 : 20) + (isDir ? 5 : 0) - depth * 2;
            out.push({ path, name: fileName, dir: path.slice(0, path.lastIndexOf("/")) || "/", isDir, depth, score });
        }
        return out.sort((a, b) => b.score - a.score);
    }

    Timer {
        id: debounce
        interval: 200
        onTriggered: {
            const words = root.query.split(/\s+/);
            proc.running = false;
            proc.wanted = root.query;
            // The name is matched as text, so * ? [ in it are escaped for find's pattern;
            // head stops find after 60 hits instead of walking the whole home folder
            const name = words[words.length - 1].replace(/[*?[\]\\]/g, "\\$&");
            proc.command = ["sh", "-c",
                'find "$0" -mindepth 1 \\( -name ".*" -o -name node_modules -o -name target -o -name build -o -name dist '
                + '-o -name __pycache__ -o -name venv -o -name .venv \\) -prune -o \\( -type d -o -type f \\) -iname "*$1*" '
                + '-printf "%y\\t%p\\n" 2>/dev/null | head -n 60',
                root.base, name];
            proc.running = true;
        }
    }

    Process {
        id: proc
        property string wanted: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (proc.wanted !== root.query)
                    return;
                root.results = root.rank(text.split("\n").filter(l => l !== ""), root.query);
                root.searching = false;
            }
        }
    }
}
