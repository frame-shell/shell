pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.config

// Every notification: desktop ones over D-Bus (this shell is the notification daemon)
// and Discord events from the Vencord bridge. Popups are shown by notifications/Popups.qml,
// everything also lands in `history` for the bell in the bar.
//
// Entry: { uid, app, title, body, image, glyph, kind ("normal" | "voice" | "call" | "mini"),
//   critical, timeout (ms, 0 = stays until handled), time, actions: [{ id, label, style }],
//   notification (D-Bus object or null), onAction(id), callChannel }
Singleton {
    id: root

    property var popups: []
    property var history: []
    // Arrived while "silent" was on and not seen yet
    property int missed: 0
    property int nextUid: 1
    // Starts the Discord socket together with the notifications
    readonly property bool discordConnected: DiscordBridge.connected

    function toArray(list) {
        const out = [];
        for (let i = 0; i < (list?.length ?? 0); i++)
            out.push(list[i]);
        return out;
    }

    NotificationServer {
        keepOnReload: false
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        bodyMarkupSupported: false

        onNotification: n => {
            n.tracked = true;
            const critical = n.urgency === NotificationUrgency.Critical;
            root.push({
                app: (n.appName || "app").toLowerCase(),
                title: n.summary,
                body: n.body,
                image: n.image || n.appIcon || "",
                critical,
                timeout: critical ? 0 : n.expireTimeout > 0 ? n.expireTimeout : Config.notificationTimeout,
                actions: root.toArray(n.actions)
                    .filter(a => a.identifier !== "default")
                    .map(a => ({ id: a.identifier, label: a.text.toLowerCase(), style: "" })),
                notification: n,
                onAction: id => {
                    const action = root.toArray(n.actions).find(a => a.identifier === id);
                    if (action)
                        action.invoke();
                }
            });
        }
    }

    function push(entry) {
        const full = Object.assign({
            uid: nextUid++,
            time: new Date(),
            app: "app",
            title: "",
            body: "",
            image: "",
            kind: "normal",
            critical: false,
            timeout: Config.notificationTimeout,
            actions: [],
            notification: null,
            onAction: null,
            callChannel: ""
        }, entry);
        if (!entry.glyph)
            full.glyph = (full.title || full.app).charAt(0).toUpperCase();

        history = [full].concat(history).slice(0, 50);

        // Silent keeps everything but calls and critical ones off the screen
        if (Toggles.silent && !full.critical && full.kind !== "call") {
            missed += 1;
            return;
        }

        // At most three on screen; the oldest non-call goes first
        let list = [full].concat(popups);
        while (list.length > Config.notificationsMax) {
            let drop = -1;
            for (let i = list.length - 1; i >= 0; i--)
                if (list[i].kind !== "call") {
                    drop = i;
                    break;
                }
            list.splice(drop < 0 ? list.length - 1 : drop, 1);
        }
        popups = list;
    }

    // expired: the timer ran out (the app hears "expired" instead of "dismissed")
    function dismiss(uid, expired) {
        const entry = popups.find(p => p.uid === uid);
        popups = popups.filter(p => p.uid !== uid);
        if (!entry?.notification)
            return;
        try {
            if (expired)
                entry.notification.expire();
            else
                entry.notification.dismiss();
        } catch (e) {
            // The app closed it already
        }
    }

    function invoke(uid, actionId) {
        const entry = popups.find(p => p.uid === uid) ?? history.find(h => h.uid === uid);
        if (entry?.onAction)
            entry.onAction(actionId);
        dismiss(uid, false);
    }

    function removeWhere(test) {
        popups = popups.filter(p => !test(p));
    }

    function markSeen() {
        missed = 0;
    }

    function clearHistory() {
        history = [];
        missed = 0;
    }

    // "now", "5m", "2h"
    function ago(date) {
        const minutes = Math.floor((Date.now() - date.getTime()) / 60000);
        return minutes < 1 ? "now" : minutes < 60 ? `${minutes}m` : `${Math.floor(minutes / 60)}h`;
    }
}
