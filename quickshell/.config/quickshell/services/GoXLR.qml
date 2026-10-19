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
    // [{ key, label, fader, level (0..100), muted }] in fader order A..D
    property var faders: []
    // Mic mute button on the GoXLR (cough button), separate from the mic fader's mute
    property bool micButtonMuted: false
    // Poll faster while the control center shows the levels; the normal rate keeps the OSD quick enough
    property bool fast: false

    function fader(key) {
        return faders.find(f => f.key === key) ?? null;
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
        faders = Object.keys(status).sort().map(letter => {
            const channel = String(status[letter].channel ?? "");
            const key = ["game", "system"].includes(channel.toLowerCase()) ? "game" : channel.toLowerCase();
            return {
                key,
                label: key === "game" ? "game · sys" : channel.toLowerCase(),
                fader: letter,
                level: Math.round((volumes[channel] ?? 0) / 255 * 100),
                muted: String(status[letter].mute_state ?? "Unmuted") !== "Unmuted"
            };
        });
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
        faders = faders.map(f => f.key === key ? Object.assign({}, f, { muted }) : f);
        request("POST", "/api/command", body, () => refresh());
    }

    Timer {
        interval: root.fast ? 300 : 600
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
