pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Installed apps from .desktop files, fuzzy search and launch counts.
// Counts live in launcher-usage.json in Quickshell's state folder:
//   { "<desktop entry id>": <launches>, … }
Singleton {
    id: root

    readonly property var entries: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name))

    property var usage: ({})

    FileView {
        id: store
        path: Quickshell.statePath("launcher-usage.json")
        printErrors: false
        onLoaded: {
            try {
                root.usage = JSON.parse(text());
            } catch (e) {
                root.usage = {};
            }
        }
    }

    function uses(entry) {
        return usage[entry.id] ?? 0;
    }

    // Subsequence match: consecutive letters and word starts score higher.
    // Returns { score, idx } with the matched character positions, or null.
    function fuzzy(text, query) {
        const t = text.toLowerCase();
        const q = query.toLowerCase();
        const idx = [];
        let score = 0, last = -2, from = 0;
        for (const ch of q) {
            if (ch === " ")
                continue;
            const found = t.indexOf(ch, from);
            if (found < 0)
                return null;
            score += 1;
            if (found === last + 1)
                score += 3;
            if (found === 0 || t[found - 1] === " ")
                score += 4;
            idx.push(found);
            last = found;
            from = found + 1;
        }
        return { score: score - t.length * 0.02, idx };
    }

    // [{ entry, idx }] best first; empty query lists the most used apps
    function search(query) {
        if (query === "")
            return entries.map(entry => ({ entry, idx: [] }))
                .sort((a, b) => uses(b.entry) - uses(a.entry));

        const hits = [];
        for (const entry of entries) {
            const byName = fuzzy(entry.name, query);
            // Fall back to "Web Browser", keywords … without highlighting
            const extra = byName ? null : fuzzy(`${entry.genericName} ${(entry.keywords ?? []).join(" ")}`, query);
            const match = byName ?? (extra ? { score: extra.score - 3, idx: [] } : null);
            if (match)
                hits.push({ entry, idx: match.idx, score: match.score + Math.log(1 + uses(entry)) * 0.6 });
        }
        return hits.sort((a, b) => b.score - a.score);
    }

    // Short, lowercase category for the list ("audio", "development" …)
    function categoryOf(entry) {
        const map = {
            TerminalEmulator: "terminal", WebBrowser: "internet", Network: "internet",
            InstantMessaging: "chat", Chat: "chat", Development: "development", IDE: "development",
            Audio: "audio", Music: "audio", Video: "video", AudioVideo: "media", Game: "games",
            Graphics: "graphics", Office: "office", Settings: "system", System: "system",
            FileManager: "files", Utility: "tools"
        };
        for (const c of entry.categories ?? [])
            if (map[c])
                return map[c];
        return "app";
    }

    function launch(entry) {
        const next = Object.assign({}, usage);
        next[entry.id] = (next[entry.id] ?? 0) + 1;
        usage = next;
        store.setText(JSON.stringify(next));

        if (entry.runInTerminal)
            Quickshell.execDetached(["ghostty", "-e", ...entry.command]);
        else
            entry.execute();
    }
}
