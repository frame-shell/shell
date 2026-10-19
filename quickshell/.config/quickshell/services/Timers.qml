pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Timers (launcher t) and alarms (launcher a). Both survive a shell restart; they live in
// alarms.json in Quickshell's state folder:
//   { nextId, timers: [{ id, label, ends (ms since 1970), total (s) }],
//     alarms: [{ id, label, hour, minute, days: [0–6, 0 = Sunday] (empty = once), enabled, next (ms) }] }
// When one goes off, its notification stays until you pick snooze or done, and a sound
// plays for up to a minute (sound-theme-freedesktop, pw-play).
Singleton {
    id: root

    property var timers: []
    property var alarms: []
    property int nextId: 1
    property real now: Date.now()
    // Notifications still ringing (uid list); the sound stops when it is empty
    property var ringing: []
    property int rings: 0

    readonly property var dayNames: ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    readonly property string sound: "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"

    // ── Timers ───────────────────────────────────────────────

    function addTimer(seconds, label) {
        now = Date.now();
        timers = timers.concat([{ id: nextId++, label: label ?? "", ends: now + seconds * 1000, total: seconds }]);
        save();
    }

    function cancelTimer(id) {
        timers = timers.filter(t => t.id !== id);
        save();
    }

    function left(timer) {
        return Math.max(0, Math.round((timer.ends - now) / 1000));
    }

    // ── Alarms ───────────────────────────────────────────────

    // The next time after `from` (ms) that matches hour:minute on one of the days
    function nextOccurrence(hour, minute, days, from) {
        const d = new Date(from);
        d.setHours(hour, minute, 0, 0);
        for (let i = 0; i < 8; i++) {
            if (d.getTime() > from && (days.length === 0 || days.includes(d.getDay())))
                return d.getTime();
            d.setDate(d.getDate() + 1);
            d.setHours(hour, minute, 0, 0);
        }
        return 0;
    }

    function addAlarm(hour, minute, days, label) {
        const alarm = { id: nextId++, label: label ?? "", hour, minute, days, enabled: true, next: nextOccurrence(hour, minute, days, Date.now()) };
        alarms = alarms.concat([alarm]).sort((a, b) => a.hour * 60 + a.minute - b.hour * 60 - b.minute);
        save();
        return alarm;
    }

    function toggleAlarm(id) {
        alarms = alarms.map(a => a.id !== id ? a : Object.assign({}, a, {
            enabled: !a.enabled,
            next: a.enabled ? a.next : nextOccurrence(a.hour, a.minute, a.days, Date.now())
        }));
        save();
    }

    function removeAlarm(id) {
        alarms = alarms.filter(a => a.id !== id);
        save();
    }

    // "mon–fri", "mon, wed, fri", "every day", "once"
    function daysText(days) {
        if (days.length === 0)
            return "once";
        if (days.length === 7)
            return "every day";
        const sorted = days.slice().sort((a, b) => (a + 6) % 7 - (b + 6) % 7);
        const ids = sorted.map(d => (d + 6) % 7);
        const contiguous = ids.every((d, i) => i === 0 || d === ids[i - 1] + 1);
        if (contiguous && sorted.length > 2)
            return `${dayNames[sorted[0]]}–${dayNames[sorted[sorted.length - 1]]}`;
        return sorted.map(d => dayNames[d]).join(", ");
    }

    function clock(hour, minute) {
        return `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`;
    }

    // "today 07:30", "tomorrow 07:30", "fri 07:30"
    function whenText(ms) {
        if (!ms)
            return "–";
        const d = new Date(ms);
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const day = Math.round((new Date(d).setHours(0, 0, 0, 0) - today.getTime()) / 86400000);
        const name = day === 0 ? "today" : day === 1 ? "tomorrow" : dayNames[d.getDay()];
        return `${name} ${clock(d.getHours(), d.getMinutes())}`;
    }

    // ── Going off ────────────────────────────────────────────

    function ring(app, title, body, label) {
        const uid = Notifications.nextUid;
        Notifications.push({
            app,
            kind: "alarm",
            timeout: 0,
            title,
            body,
            actions: [
                { id: "snooze", label: `snooze ${Config.snoozeMinutes}m`, style: "" },
                { id: "done", label: "done", style: "ok" }
            ],
            onAction: id => {
                root.ringing = root.ringing.filter(u => u !== uid);
                if (id === "snooze")
                    root.addTimer(Config.snoozeMinutes * 60, label === "" ? "snoozed" : `${label} · snoozed`);
            }
        });
        ringing = ringing.concat([uid]);
        rings = 0;
        playSound();
    }

    // The sound runs as a tracked process, so done or snooze can cut it off at once
    function playSound() {
        soundProc.running = false;
        soundProc.command = ["pw-play", sound];
        soundProc.running = true;
    }

    function stopSound() {
        soundProc.running = false;
    }

    Process {
        id: soundProc
    }

    onRingingChanged: {
        if (ringing.length === 0)
            stopSound();
    }

    function check() {
        now = Date.now();
        let changed = false;

        const due = timers.filter(t => t.ends <= now);
        if (due.length > 0) {
            timers = timers.filter(t => t.ends > now);
            changed = true;
            for (const t of due) {
                const late = now - t.ends > 60000;
                ring("timer", t.label || "timer", late ? `ran out at ${clock(new Date(t.ends).getHours(), new Date(t.ends).getMinutes())} while the shell was off`
                    : `${formatSeconds(t.total)} are over`, t.label);
            }
        }

        const next = [];
        for (const a of alarms) {
            if (!a.enabled || !a.next || a.next > now) {
                next.push(a);
                continue;
            }
            changed = true;
            // Missed by more than an hour (computer was off): say so instead of ringing
            if (now - a.next > 3600000)
                Notifications.push({ app: "alarm", title: `missed alarm · ${a.label || clock(a.hour, a.minute)}`, body: `was set for ${whenText(a.next)}` });
            else
                ring("alarm", a.label || "alarm", `${clock(a.hour, a.minute)} · ${daysText(a.days)}`, a.label);
            // A one-time alarm is used up; repeating ones move on
            if (a.days.length > 0)
                next.push(Object.assign({}, a, { next: nextOccurrence(a.hour, a.minute, a.days, now) }));
        }
        if (changed) {
            alarms = next;
            save();
        }
    }

    // 90 → "1:30", 3600 → "1:00:00"
    function formatSeconds(total) {
        const h = Math.floor(total / 3600), m = Math.floor(total % 3600 / 60), s = total % 60;
        const two = n => String(n).padStart(2, "0");
        return h > 0 ? `${h}:${two(m)}:${two(s)}` : `${m}:${two(s)}`;
    }

    // ── Storage ──────────────────────────────────────────────

    function save() {
        store.setText(JSON.stringify({ nextId, timers, alarms }, null, 1));
    }

    FileView {
        id: store
        path: Quickshell.statePath("alarms.json")
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.timers = data.timers ?? [];
                root.alarms = data.alarms ?? [];
                root.nextId = data.nextId ?? 1;
            } catch (e) {
                console.warn(`timers: alarms.json unreadable, starting empty (${e})`);
            }
            root.check();
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.timers.length > 0 || root.alarms.some(a => a.enabled)
        onTriggered: root.check()
    }

    // Rings again every 5 s for a minute or until snooze/done
    Timer {
        interval: 5000
        repeat: true
        running: root.ringing.length > 0
        onTriggered: {
            root.rings += 1;
            if (root.rings >= 12)
                root.ringing = [];
            else
                root.playSound();
        }
    }
}
