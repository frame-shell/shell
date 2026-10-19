pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Unix socket the Vencord plugin (vencord/plugins/shellBridge) connects to.
// One JSON object per line in both directions.
//
// Discord → shell:
//   { type: "message", author, channel, guild, content, avatar, channelId, guildId }
//   { type: "voice", action: "join" | "leave", user, channel, count, avatar, channelId, watched }
//   { type: "event", name, guild, channel, location, channelId, guildId }
//   { type: "call", state: "ringing" | "ended", caller, avatar, channelId }
//   { type: "self", muted, deafened, channel }
// shell → Discord:
//   { cmd: "accept_call" | "decline_call" | "join_voice" | "open_channel" | "toggle_mute" | "toggle_deafen",
//     channelId?, guildId? }
Singleton {
    id: root

    readonly property string path: `${Quickshell.env("XDG_RUNTIME_DIR")}/qs-discord.sock`
    property var clients: []
    readonly property bool connected: clients.length > 0

    function send(command) {
        const line = `${JSON.stringify(command)}\n`;
        for (const client of clients) {
            client.write(line);
            client.flush();
        }
    }

    function handle(event) {
        switch (event.type) {
        case "message":
            Notifications.push({
                app: "discord",
                title: event.guild ? `${event.author} · #${event.channel}` : event.author,
                body: event.content,
                image: event.avatar ?? "",
                actions: [{ id: "open", label: "open", style: "" }],
                onAction: () => root.send({ cmd: "open_channel", channelId: event.channelId, guildId: event.guildId })
            });
            break;
        case "voice":
            // Your own channel: just the news. A watched channel: offer to join
            Notifications.push({
                app: event.watched ? "discord · watching" : "discord · voice",
                kind: "voice",
                title: `${event.user} ${event.action === "join" ? "joined" : "left"} ${event.channel}`,
                body: `${event.count} in the channel`,
                image: event.avatar ?? "",
                actions: event.watched && event.action === "join" ? [{ id: "join", label: "join", style: "" }] : [],
                onAction: () => root.send({ cmd: "join_voice", channelId: event.channelId })
            });
            break;
        case "event":
            // Stage/voice events can be joined directly, external ones only opened
            Notifications.push({
                app: "discord · event",
                kind: "voice",
                title: `${event.name} started`,
                body: [event.guild, event.channel || event.location].filter(Boolean).join(" · "),
                actions: event.channelId ? [{ id: "join", label: "join", style: "ok" }] : [{ id: "open", label: "open", style: "" }],
                onAction: id => root.send(id === "join"
                    ? { cmd: "join_voice", channelId: event.channelId }
                    : { cmd: "open_channel", channelId: event.channelId, guildId: event.guildId })
            });
            break;
        case "call":
            if (event.state === "ringing")
                Notifications.push({
                    app: "discord · call",
                    kind: "call",
                    timeout: 0,
                    title: `${event.caller} is calling`,
                    body: "direct call · ringing",
                    image: event.avatar ?? "",
                    callChannel: event.channelId,
                    actions: [
                        { id: "accept", label: "accept", style: "ok" },
                        { id: "decline", label: "decline", style: "no" }
                    ],
                    onAction: id => root.send({ cmd: id === "accept" ? "accept_call" : "decline_call", channelId: event.channelId })
                });
            else
                Notifications.removeWhere(p => p.callChannel === event.channelId);
            break;
        case "self":
            Notifications.push({
                app: "discord",
                kind: "mini",
                timeout: 2500,
                glyph: event.muted || event.deafened ? "✕" : "✓",
                title: event.deafened ? "you are deafened" : event.muted ? "you muted yourself" : "you unmuted yourself",
                body: event.channel ? `in ${event.channel}` : "",
                actions: event.deafened ? [{ id: "undeafen", label: "undeafen", style: "" }]
                    : event.muted ? [{ id: "unmute", label: "unmute", style: "" }] : [],
                onAction: id => root.send({ cmd: id === "undeafen" ? "toggle_deafen" : "toggle_mute" })
            });
            break;
        default:
            console.warn(`discord bridge: unknown event ${event.type}`);
        }
    }

    SocketServer {
        active: true
        path: root.path

        handler: Socket {
            id: client

            onConnectedChanged: {
                if (connected)
                    root.clients = root.clients.concat([client]);
                else
                    root.clients = root.clients.filter(c => c !== client);
            }

            parser: SplitParser {
                onRead: line => {
                    try {
                        root.handle(JSON.parse(line));
                    } catch (e) {
                        console.warn(`discord bridge: ${e}`);
                    }
                }
            }
        }
    }
}
