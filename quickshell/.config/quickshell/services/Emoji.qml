pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Emoji for the launcher (#), read from Unicode's emoji-test.txt (package unicode-emoji).
// Skin-tone variants are left out to keep the list short. Recently picked ones come first
// for an empty search; they live in emoji-recent.json in Quickshell's state folder.
//
// list: [{ char, name, group }]
Singleton {
    id: root

    property var list: []
    property var recent: []
    readonly property bool available: list.length > 0

    function parse(text) {
        const out = [];
        let group = "";
        for (const line of text.split("\n")) {
            if (line.startsWith("# subgroup: ")) {
                group = line.slice(12).trim();
                continue;
            }
            const m = /; fully-qualified\s+# (\S+) E\d+\.\d+ (.+)$/.exec(line);
            if (m && !m[2].includes("skin tone"))
                out.push({ char: m[1], name: m[2], group });
        }
        list = out;
    }

    // Every word of the query has to start a word of the name (or its group)
    function search(query) {
        const words = query.toLowerCase().split(/\s+/).filter(w => w !== "");
        if (words.length === 0)
            return recent.map(c => list.find(e => e.char === c)).filter(Boolean);
        const out = [];
        for (const e of list) {
            const name = e.name.toLowerCase();
            const nameWords = name.split(/[\s:,-]+/);
            const groupWords = e.group.split("-");
            let score = 0, ok = true;
            for (const w of words) {
                if (nameWords.some(n => n.startsWith(w)))
                    score += nameWords.includes(w) ? 3 : 2;
                else if (groupWords.some(g => g.startsWith(w)))
                    score += 1;
                else {
                    ok = false;
                    break;
                }
            }
            if (ok)
                out.push({ e, score: score - nameWords.length * 0.1 + (recent.includes(e.char) ? 2 : 0) });
        }
        return out.sort((a, b) => b.score - a.score).slice(0, 40).map(x => x.e);
    }

    function used(char) {
        recent = [char].concat(recent.filter(c => c !== char)).slice(0, 18);
        recentStore.setText(JSON.stringify(recent));
    }

    FileView {
        path: "/usr/share/unicode/emoji/emoji-test.txt"
        printErrors: false
        onLoaded: root.parse(text())
    }

    FileView {
        id: recentStore
        path: Quickshell.statePath("emoji-recent.json")
        printErrors: false
        onLoaded: {
            try {
                root.recent = JSON.parse(text());
            } catch (e) {
                root.recent = [];
            }
        }
    }
}
