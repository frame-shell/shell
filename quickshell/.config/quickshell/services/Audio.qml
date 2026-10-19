pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.config

// App audio streams and their GoXLR routing through PipeWire.
// goxlr-utility creates one PipeWire output per channel (system, game, chat,
// music) and inputs for the mics; moving a stream there routes the app.
// WirePlumber remembers the target per app, so routing survives restarts.
Singleton {
    id: root

    readonly property var nodes: Pipewire.nodes.values.filter(n => n.audio)
    // Apps that play audio (they output into a sink)
    readonly property var playback: nodes.filter(n => n.isStream && !n.isSink && !isMonitor(n))
    // Apps that record audio (they take input from a source)
    readonly property var recording: nodes.filter(n => n.isStream && n.isSink && !isMonitor(n))
    readonly property var sinks: nodes.filter(n => !n.isStream && n.isSink)
    readonly property var sources: nodes.filter(n => !n.isStream && !n.isSink)

    // Route keys that exist on this machine, in Config order
    readonly property var outputRoutes: Object.keys(Config.goxlrOutputs).filter(k => findDevice(sinks, Config.goxlrOutputs[k]) !== null)
    readonly property var inputRoutes: Object.keys(Config.goxlrInputs).filter(k => findDevice(sources, Config.goxlrInputs[k]) !== null)

    // Volume and mute only work on tracked nodes
    PwObjectTracker {
        objects: root.playback.concat(root.recording)
    }

    function isMonitor(node) {
        const props = node.properties ?? {};
        return props["stream.monitor"] === "true" || props["stream.monitor"] === true;
    }

    // "GoXLR Music" in the config matches "GoXLR Music" and "GoXLRMini Music" (the Mini
    // names its devices that way); spaces and case do not matter
    function channelKey(text) {
        return String(text ?? "").toLowerCase().replace(/\s+/g, "").replace(/^goxlr(mini)?/, "");
    }

    function findDevice(list, label) {
        const wanted = channelKey(label);
        if (wanted === "")
            return null;
        return list.find(n => channelKey(n.description) === wanted || channelKey(n.nickname) === wanted) ?? null;
    }

    function appName(node) {
        const props = node.properties ?? {};
        return props["application.name"] || node.description || node.name || "unknown";
    }

    function mediaName(node) {
        return (node.properties ?? {})["media.name"] ?? "";
    }

    function iconName(node) {
        const props = node.properties ?? {};
        return props["application.icon-name"] || appName(node).toLowerCase().replace(/\s+/g, "-");
    }

    // The link between a stream and its device, if any
    function linkOf(node) {
        return Pipewire.linkGroups.values.find(g => node.isSink ? g.target === node : g.source === node) ?? null;
    }

    function deviceOf(node) {
        const link = linkOf(node);
        return link ? (node.isSink ? link.source : link.target) : null;
    }

    // No running link means the app is paused or silent
    function isIdle(node) {
        const link = linkOf(node);
        return !link || link.state !== PwLinkState.Active;
    }

    // "music", "chat mic" … or "" when the stream is on a non-GoXLR device
    function routeOf(node) {
        const device = deviceOf(node);
        if (!device)
            return "";
        const map = node.isSink ? Config.goxlrInputs : Config.goxlrOutputs;
        const list = node.isSink ? sources : sinks;
        return Object.keys(map).find(k => findDevice(list, map[k]) === device) ?? "";
    }

    function move(node, route) {
        const map = node.isSink ? Config.goxlrInputs : Config.goxlrOutputs;
        const device = findDevice(node.isSink ? sources : sinks, map[route]);
        if (!device)
            return;
        // pipewire-pulse uses the PipeWire node id as the stream index
        Quickshell.execDetached(["pactl", node.isSink ? "move-source-output" : "move-sink-input", String(node.id), device.name]);
    }

    function setVolume(node, value) {
        if (node.audio)
            node.audio.volume = Math.max(0, Math.min(1, value));
    }

    function toggleMute(node) {
        if (node.audio)
            node.audio.muted = !node.audio.muted;
    }
}
