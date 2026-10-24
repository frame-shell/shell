pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Installed apps from .desktop files, fuzzy search and launch counts. An app that already
// runs is not started again: Enter brings its window to the current view.
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

    // The window of an app that already runs, else null: the class Hyprland reports against
    // the entry's id, its StartupWMClass and the program it runs (each also without a
    // reverse-domain prefix: dev.zed.Zed is "zed"); of several windows the one used last.
    // Hyprland.toplevels is refreshed when the launcher opens (Launcher.qml).
    function windowOf(entry) {
        const names = new Set();
        const add = s => {
            s = String(s ?? "").trim().toLowerCase();
            if (s !== "") {
                names.add(s);
                names.add(s.slice(s.lastIndexOf(".") + 1));
            }
        };
        add(entry.id);
        add(entry.startupClass);
        const exe = String((entry.command ?? [])[0] ?? String(entry.execString ?? "").split(" ")[0]);
        add(exe.slice(exe.lastIndexOf("/") + 1));

        let best = null;
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject ?? {};
            const cls = String(o.class ?? t.wayland?.appId ?? "").toLowerCase();
            if (cls === "" || !(names.has(cls) || names.has(cls.slice(cls.lastIndexOf(".") + 1))))
                continue;
            if (o.mapped === false || o.hidden === true)
                continue;
            const order = Number(o.focusHistoryID ?? 1e9);
            if (!best || order < best.order)
                best = { order, address: String(o.address ?? t.address ?? ""), title: String(o.title ?? ""), workspace: String(o.workspace?.name ?? "") };
        }
        return best;
    }

    // Brings a running window to the current view: on the canvas into the middle of the
    // focused screen (canvas.lua summon), otherwise onto the active workspace, and focuses
    // it. A game on the games workspace (shell.lua, Super+Tab) stays there: the screen goes
    // to it; seen from the games, an app is not pulled over either, the screen goes to it
    function summon(address) {
        if (CanvasLayout.enabled) {
            CanvasLayout.summon(address);
            return;
        }
        const a = String(address).replace(/[^0-9a-fx]/gi, "");
        Quickshell.execDetached(["hyprctl", "eval",
            `local w = hl.get_window("address:${a}") local ws = hl.get_active_workspace() `
            + `if w and ws and ws.name ~= "gaming" and not (w.workspace and w.workspace.name == "gaming") then `
            + `hl.dispatch(hl.dsp.window.move({ workspace = tostring(ws.id), follow = false, window = "address:${a}" })) end `
            + `if w then hl.dispatch(hl.dsp.focus({ window = "address:${a}" })) end`]);
    }

    // Enter: the app's window if it already runs (fresh false), else a new start
    function launch(entry, fresh) {
        const next = Object.assign({}, usage);
        next[entry.id] = (next[entry.id] ?? 0) + 1;
        usage = next;
        store.setText(JSON.stringify(next));

        if (!fresh) {
            const win = windowOf(entry);
            if (win) {
                summon(win.address);
                return;
            }
        }

        if (entry.runInTerminal)
            Quickshell.execDetached(["ghostty", "-e", ...entry.command]);
        else
            entry.execute();
    }
}
