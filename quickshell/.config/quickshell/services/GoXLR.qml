pragma Singleton

import QtQuick
import Quickshell
import qs.config

// Fader levels and fader mute buttons of the GoXLR, from the goxlr-utility HTTP API.
// Levels are display only, the faders are physical; mutes can be toggled.
//
// Expected from GET /api/get-devices (goxlr-utility status JSON):
//   mixers.<serial>.levels.volumes.<Channel>   0..255
//   mixers.<serial>.fader_status.<A..D>         { channel: "Mic", mute_state: "Unmuted" }
//   mixers.<serial>.cough_button.state           "Unmuted" | "MutedToX" | "MutedToAll"  (mic mute button)
// If your goxlr-utility version names things differently, adjust parse() and setMuted().
// goxlr-utility also has a websocket with live patches; polling keeps this simple.
Singleton {
    id: root

    property bool available: false
    property string serial: ""
    // [{ key, label, fader }] in fader order A..D. Only replaced when a fader is assigned
    // another channel, so the rows in the control center stay put between polls
    property var faders: []
    // key → { level (0..100), muted }, replaced only when a value changed
    property var live: ({})
    // Every channel's volume, lowercase name → 0..100 (system, game, chat, music, mic, …),
    // faders or not; a Mini has no fader for System, so the bar and the control center
    // set that one over the API
    property var volumes: ({})
    readonly property bool systemOnFader: faders.some(f => f.channel === "system")
    // Mic mute button on the GoXLR (cough button), separate from the mic fader's mute
    property bool micButtonMuted: false
    // Poll faster while the control center shows the levels; the normal rate keeps the OSD quick enough
    property bool fast: false

    // { key, label, fader, level, muted } or null
    function fader(key) {
        const f = faders.find(f => f.key === key);
        if (!f)
            return null;
        const l = live[key] ?? { level: 0, muted: false };
        return { key: f.key, label: f.label, fader: f.fader, level: l.level, muted: l.muted };
    }

    function state(key) {
        return live[key] ?? { level: 0, muted: false };
    }

    function request(method, path, body, onDone) {
        const xhr = new XMLHttpRequest();
        xhr.open(method, `${Config.goxlrApi}${path}`);
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            if (xhr.status !== 200) {
                root.available = false;
                return;
            }
            if (onDone)
                onDone(xhr.responseText);
        };
        if (body !== null)
            xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(body);
    }

    function refresh() {
        request("GET", "/api/get-devices", null, text => {
            try {
                parse(JSON.parse(text));
            } catch (e) {
                console.warn(`goxlr: ${e}`);
                root.available = false;
            }
        });
    }

    function parse(data) {
        const id = Object.keys(data.mixers ?? {})[0];
        if (!id) {
            available = false;
            return;
        }
        const mixer = data.mixers[id];
        const volumes = mixer.levels?.volumes ?? {};
        const status = mixer.fader_status ?? {};
        const list = [];
        const next = {};
        const all = {};
        const now = Date.now();
        for (const name of Object.keys(volumes)) {
            const key = name.toLowerCase();
            // Set from here a moment ago: a poll answered before the device took the new
            // value would make the slider jump back
            all[key] = now - (setAt[key] ?? 0) < 600 && root.volumes[key] !== undefined
                ? root.volumes[key] : Math.round((volumes[name] ?? 0) / 255 * 100);
        }
        if (JSON.stringify(all) !== JSON.stringify(root.volumes))
            root.volumes = all;
        for (const letter of Object.keys(status).sort()) {
            // Each fader is its own channel (Game and System are two, also on a Mini)
            const channel = String(status[letter].channel ?? "");
            const key = channel.toLowerCase();
            list.push({ key, label: key, fader: letter, channel: key });
            next[key] = {
                level: Math.round((volumes[channel] ?? 0) / 255 * 100),
                muted: String(status[letter].mute_state ?? "Unmuted") !== "Unmuted"
            };
        }
        const sameFaders = list.length === faders.length
            && list.every((f, i) => f.key === faders[i].key && f.fader === faders[i].fader && f.label === faders[i].label && f.channel === faders[i].channel);
        if (!sameFaders)
            faders = list;
        if (JSON.stringify(next) !== JSON.stringify(live))
            live = next;
        micButtonMuted = String(mixer.cough_button?.state ?? "Unmuted") !== "Unmuted";
        serial = id;
        available = true;
    }

    function setMuted(key, muted) {
        const target = fader(key);
        if (!target || serial === "")
            return;
        const body = JSON.stringify({ Command: [serial, { SetFaderMuteState: [target.fader, muted ? "MutedToAll" : "Unmuted"] }] });
        // Show it right away; the next poll confirms
        live = Object.assign({}, live, { [key]: Object.assign({}, state(key), { muted }) });
        request("POST", "/api/command", body, () => refresh());
    }

    // Sets a channel's volume (0..100) over the API, e.g. "System" on a Mini, which has no
    // fader for it. Shown right away; the next poll confirms.
    // A slider sends a value on every mouse move; only the newest one goes out, every 60 ms
    function setChannelVolume(channel, level) {
        if (serial === "")
            return;
        level = Math.max(0, Math.min(100, Math.round(level)));
        const name = channel.charAt(0).toUpperCase() + channel.slice(1).toLowerCase();
        const key = name.toLowerCase();
        volumes = Object.assign({}, volumes, { [key]: level });
        setAt = Object.assign({}, setAt, { [key]: Date.now() });
        pendingVolumes = Object.assign({}, pendingVolumes, { [name]: level });
        if (!sendVolumes.running)
            sendVolumes.start();
    }

    // When each channel was last set from the shell (ms), see parse()
    property var setAt: ({})
    property var pendingVolumes: ({})

    Timer {
        id: sendVolumes
        interval: 60
        onTriggered: {
            const pending = root.pendingVolumes;
            root.pendingVolumes = {};
            for (const name of Object.keys(pending)) {
                const body = JSON.stringify({ Command: [root.serial, { SetVolume: [name, Math.round(pending[name] / 100 * 255)] }] });
                root.request("POST", "/api/command", body, () => {});
            }
        }
    }

    function stepSystem(delta) {
        setChannelVolume("System", (volumes.system ?? 0) + delta);
    }

    Timer {
        interval: root.fast ? 300 : 600
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
