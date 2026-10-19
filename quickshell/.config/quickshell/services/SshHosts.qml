pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Hosts from ~/.ssh/config for the launcher (ssh). Patterns like "Host *" are skipped,
// Include lines are not followed.
//
// hosts: [{ name, hostname, user, port }]
Singleton {
    id: root

    property var hosts: []

    function parse(text) {
        const out = [];
        let current = [];
        for (const raw of text.split("\n")) {
            const line = raw.trim();
            if (line === "" || line.startsWith("#"))
                continue;
            const m = /^(\S+)\s*=?\s*(.*)$/.exec(line);
            if (!m)
                continue;
            const key = m[1].toLowerCase();
            const value = m[2].trim();
            if (key === "host" || key === "match") {
                current = key === "host" ? value.split(/\s+/).filter(n => !/[*?!]/.test(n)).map(name => ({ name, hostname: "", user: "", port: "" })) : [];
                out.push(...current);
            } else if (key === "hostname" || key === "user" || key === "port") {
                for (const h of current)
                    h[key] = value;
            }
        }
        hosts = out;
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.ssh/config`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse(text())
    }
}
