import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import qs.components
import qs.config

// The recording editor's window content: preview with the pictures and blur boxes on top,
// the inspector for what is selected, the transport and the timeline (EditorTimeline.qml).
// Loaded only when a video opens (EditorWindow.qml), so a missing Qt Multimedia
// (qt6-multimedia-ffmpeg) costs the editor, never the shell.
//
// Playback: the video plays in its own player and every separate track in one of its own,
// kept in step with the video; at the end of a piece the players jump to the next one.
FocusScope {
    id: root

    signal closeRequested()

    readonly property alias project: project
    // Output seconds
    property real playhead: 0
    property bool playing: false
    property int curSeg: 0
    // { kind: "overlay", id } | { kind: "seg", i } | { kind: "track", i } | null
    property var selected: null
    // Timeline pixels per second
    property real pps: 12
    // "export & delete raw" waits for a yes
    property bool confirmRaw: false

    readonly property var selOverlay: selected?.kind === "overlay" ? project.overlay(selected.id) : null

    EditorProject {
        id: project

        // The recording is gone after "export & delete raw"; nothing is written back for it
        onOriginalDeleted: {
            root.pause();
            dirty = false;
            root.closeRequested();
        }
    }

    function fileUrl(path) {
        return "file://" + path.split("/").map(encodeURIComponent).join("/");
    }

    function fmt(s) {
        s = Math.max(0, s);
        const m = Math.floor(s / 60);
        const r = s - m * 60;
        return `${m}:${r.toFixed(1).padStart(4, "0")}`;
    }

    function openFile(path) {
        pause();
        selected = null;
        playhead = 0;
        curSeg = 0;
        project.load(path);
        player.source = fileUrl(path);
        forceActiveFocus();
    }

    // ── Playback ─────────────────────────────────────────────

    function trackPlayer(i) {
        return trackPlayers.objectAt(i);
    }

    function syncTracks(src, force) {
        for (let i = 0; i < project.tracks.length; i++) {
            const t = project.tracks[i];
            const p = trackPlayer(i);
            if (!p || t.file === "")
                continue;
            const want = Math.max(0, (src + t.offset) * 1000);
            if (force || Math.abs(p.position - want) > 120)
                p.setPosition(want);
        }
    }

    function seek(t) {
        playhead = Math.max(0, Math.min(project.outLen, t));
        const loc = project.locate(playhead);
        curSeg = loc.i;
        // A stopped player shows no picture; paused, it shows the frame at the position
        if (!playing && player.playbackState === MediaPlayer.StoppedState)
            player.pause();
        player.setPosition(loc.src * 1000);
        syncTracks(loc.src, true);
    }

    function play() {
        if (project.segments.length === 0)
            return;
        if (playhead >= project.outLen - 0.05)
            playhead = 0;
        seek(playhead);
        player.play();
        for (let i = 0; i < project.tracks.length; i++)
            if (project.tracks[i].file !== "")
                trackPlayer(i)?.play();
        playing = true;
    }

    function pause() {
        player.pause();
        for (let i = 0; i < trackPlayers.count; i++)
            trackPlayer(i)?.pause();
        playing = false;
    }

    function toggle() {
        if (playing)
            pause();
        else
            play();
    }

    function select(s) {
        selected = s;
    }

    // ── Editing ──────────────────────────────────────────────

    function cut() {
        const i = project.cut(playhead);
        if (i >= 0)
            select({ kind: "seg", i });
    }

    function removeSelected() {
        if (!selected)
            return;
        if (selected.kind === "overlay")
            project.removeOverlay(selected.id);
        else if (selected.kind === "seg")
            project.removeSegment(selected.i);
        else
            return;
        select(null);
        seek(Math.min(playhead, project.outLen));
    }

    function addBlur() {
        select({ kind: "overlay", id: project.addBlur(playhead) });
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const step = event.modifiers & Qt.ShiftModifier ? 5 : 1;
        if (event.key === Qt.Key_Space)
            toggle();
        else if (event.key === Qt.Key_C && !ctrl)
            cut();
        else if (event.key === Qt.Key_B)
            addBlur();
        else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)
            removeSelected();
        else if (event.key === Qt.Key_Z && ctrl) {
            if (project.undo()) {
                select(null);
                seek(Math.min(playhead, project.outLen));
            }
        } else if (event.key === Qt.Key_Left)
            seek(playhead - step);
        else if (event.key === Qt.Key_Right)
            seek(playhead + step);
        else if (event.key === Qt.Key_Home)
            seek(0);
        else if (event.key === Qt.Key_End)
            seek(project.outLen);
        else if (event.key === Qt.Key_Escape)
            select(null);
        else
            return;
        event.accepted = true;
    }

    MediaPlayer {
        id: player

        videoOutput: video
        audioOutput: AudioOutput {
            // The video's own (mixed) sound plays only when there are no separate tracks
            volume: {
                if (project.separateTracks)
                    return 0;
                const t = project.tracks[0];
                return !t || t.muted ? 0 : t.level;
            }
        }
        onDurationChanged: {
            if (duration > 0) {
                project.setDuration(duration / 1000);
                root.seek(root.playhead);
            }
        }
        onHasAudioChanged: project.videoHasAudio = hasAudio
        // The file ran out before the last piece's end was seen
        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.StoppedState && root.playing) {
                root.pause();
                root.playhead = project.outLen;
            }
        }
    }

    // One player per separate track; the model is a count, so changing a level keeps them
    Instantiator {
        id: trackPlayers

        model: project.tracks.length
        delegate: MediaPlayer {
            required property int index
            readonly property var track: project.tracks[index] ?? null

            source: track && track.file !== "" ? root.fileUrl(track.file) : ""
            audioOutput: AudioOutput {
                volume: !track || track.muted ? 0 : track.level
            }
        }
    }

    // Follows the video through the pieces: at the end of one, on to the next
    Timer {
        running: root.playing
        interval: 30
        repeat: true
        onTriggered: {
            const g = project.segments[root.curSeg];
            if (!g)
                return;
            const pos = player.position / 1000;
            if (pos >= g.b - 0.02) {
                if (root.curSeg + 1 < project.segments.length) {
                    root.curSeg += 1;
                    const next = project.segments[root.curSeg];
                    player.setPosition(next.a * 1000);
                    root.syncTracks(next.a, true);
                    root.playhead = project.segStart(root.curSeg);
                } else {
                    root.pause();
                    root.playhead = project.outLen;
                }
            } else if (pos >= g.a - 0.25) {
                root.playhead = project.segStart(root.curSeg) + Math.max(0, pos - g.a);
            }
        }
    }

    // Tracks drift a little against the video; pulled back when it gets audible
    Timer {
        running: root.playing
        interval: 500
        repeat: true
        onTriggered: root.syncTracks(player.position / 1000, false)
    }

    // ── Building blocks ──────────────────────────────────────

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: 13
        elide: Text.ElideRight
    }

    component Action: TuiButton {
        id: act

        property string text: ""
        property color tint: Theme.secondary

        implicitWidth: actText.implicitWidth + 24
        implicitHeight: 28
        accent: tint

        Text {
            id: actText
            anchors.centerIn: parent
            text: act.text
            color: !act.available ? Theme.muted : act.active ? Theme.text : act.tint
            font.family: Theme.font
            font.pixelSize: 13
        }
    }

    // ── Layout ───────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        anchors.topMargin: 26
        spacing: 26

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 3
            spacing: 22

            Frame {
                Layout.fillWidth: true
                Layout.fillHeight: true
                label: project.videoWidth > 0 ? `preview · ${project.name} · ${project.videoWidth}×${project.videoHeight}` : `preview · ${project.name}`
                padding: 14

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    Item {
                        id: stage

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        Rectangle {
                            anchors.fill: parent
                            color: "black"
                        }

                        VideoOutput {
                            id: video
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectFit
                            onSourceRectChanged: {
                                if (sourceRect.width > 0) {
                                    project.videoWidth = Math.round(sourceRect.width);
                                    project.videoHeight = Math.round(sourceRect.height);
                                }
                            }
                        }

                        // The video's own rectangle inside the stage; overlays are fractions of it
                        Item {
                            id: frameArea

                            x: video.contentRect.x
                            y: video.contentRect.y
                            width: video.contentRect.width
                            height: video.contentRect.height

                            MouseArea {
                                anchors.fill: parent
                                onPressed: root.select(null)
                            }

                            Repeater {
                                model: project.overlays.length
                                delegate: OverlayBox {
                                    required property int index

                                    o: project.overlays[index] ?? null
                                    store: project
                                    frame: frameArea
                                    capture: video
                                    nativeWidth: project.videoWidth
                                    shown: o !== null && root.playhead >= o.start && root.playhead < o.end
                                    selected: o !== null && root.selOverlay !== null && root.selOverlay.id === o.id
                                    onPicked: {
                                        root.select({ kind: "overlay", id: o.id });
                                        root.forceActiveFocus();
                                    }
                                }
                            }
                        }

                        // Pictures dragged in from Dolphin land where they are dropped
                        DropArea {
                            anchors.fill: parent
                            onEntered: drag => drag.accepted = drag.hasUrls
                            onDropped: drop => {
                                const p = frameArea.mapFromItem(stage, drop.x, drop.y);
                                for (const url of drop.urls) {
                                    const path = decodeURIComponent(url.toString().replace(/^file:\/\//, ""));
                                    if (!/\.(png|jpe?g|webp|gif|bmp)$/i.test(path))
                                        continue;
                                    const id = project.addPicture(root.playhead, path,
                                        Math.max(0, Math.min(1, p.x / frameArea.width)), Math.max(0, Math.min(1, p.y / frameArea.height)));
                                    root.select({ kind: "overlay", id });
                                }
                                drop.accept();
                            }
                        }

                        Label {
                            anchors.centerIn: parent
                            visible: player.error !== MediaPlayer.NoError
                            text: player.errorString || "cannot play this file"
                            color: Theme.danger
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        color: Theme.muted
                        font.pixelSize: 12
                        text: "space play · c cut · del remove · b blur box · ctrl+z undo · ←/→ 1 s (shift 5 s) · drop a picture on the preview"
                    }
                }
            }

            Frame {
                Layout.preferredWidth: 340
                Layout.fillHeight: true
                label: "inspector"
                padding: 18

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 14

                    // Nothing selected: the project
                    ColumnLayout {
                        visible: root.selected === null
                        Layout.fillWidth: true
                        spacing: 8

                        Label { text: project.name; color: Theme.text; Layout.fillWidth: true }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Theme.muted
                            text: `${root.fmt(project.duration)} recorded, ${root.fmt(project.outLen)} after cuts · ${project.segments.length} piece${project.segments.length === 1 ? "" : "s"} · `
                                + `${project.overlays.filter(o => o.type === "picture").length} pictures · ${project.overlays.filter(o => o.type === "blur").length} blur boxes`
                        }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Theme.muted
                            text: project.separateTracks
                                ? `${project.tracks.length} channels on their own tracks`
                                : "the recording's own sound (no separate tracks: none were chosen while recording)"
                        }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WrapAnywhere
                            color: Theme.muted
                            text: `export: ${project.exportFile.slice(project.exportFile.lastIndexOf("/") + 1)}`
                        }
                        Label {
                            visible: project.exportError !== ""
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Theme.danger
                            text: project.exportError
                        }
                    }

                    // A picture or a blur box
                    ColumnLayout {
                        visible: root.selOverlay !== null
                        Layout.fillWidth: true
                        spacing: 10

                        readonly property var o: root.selOverlay

                        Label { text: parent.o?.name ?? ""; color: Theme.text; Layout.fillWidth: true }
                        Label {
                            Layout.fillWidth: true
                            color: Theme.muted
                            text: parent.o ? `${parent.o.type === "blur" ? "hides what is under it" : "shown"} from ${root.fmt(parent.o.start)} to ${root.fmt(parent.o.end)}` : ""
                        }

                        RowLayout {
                            visible: parent.o?.type === "blur"
                            spacing: 0

                            Action {
                                text: "blur"
                                active: root.selOverlay?.style !== "pixel"
                                onClicked: project.updateOverlay(root.selOverlay.id, { style: "blur" })
                            }
                            Action {
                                text: "pixelate"
                                active: root.selOverlay?.style === "pixel"
                                onClicked: project.updateOverlay(root.selOverlay.id, { style: "pixel" })
                            }
                        }

                        RowLayout {
                            visible: parent.o?.type === "blur"
                            Layout.fillWidth: true
                            spacing: 10

                            Label { text: "strength"; color: Theme.muted; Layout.preferredWidth: 70 }
                            TuiSlider {
                                Layout.fillWidth: true
                                value: ((root.selOverlay?.strength ?? 14) - 4) / 26
                                onMoved: v => project.updateOverlay(root.selOverlay.id, { strength: Math.round(4 + v * 26) }, false)
                            }
                            Label { text: String(root.selOverlay?.strength ?? ""); Layout.preferredWidth: 30 }
                        }

                        RowLayout {
                            visible: parent.o?.type === "picture"
                            Layout.fillWidth: true
                            spacing: 10

                            Label { text: "opacity"; color: Theme.muted; Layout.preferredWidth: 70 }
                            TuiSlider {
                                Layout.fillWidth: true
                                value: root.selOverlay?.opacity ?? 1
                                onMoved: v => project.updateOverlay(root.selOverlay.id, { opacity: Math.max(0.05, v) }, false)
                            }
                            Label { text: `${Math.round((root.selOverlay?.opacity ?? 1) * 100)}%`; Layout.preferredWidth: 40 }
                        }

                        Label {
                            Layout.fillWidth: true
                            color: Theme.muted
                            text: parent.o && project.videoWidth > 0
                                ? `x ${Math.round(parent.o.x * project.videoWidth)} · y ${Math.round(parent.o.y * project.videoHeight)} · ${Math.round(parent.o.w * project.videoWidth)}×${Math.round((parent.o.h > 0 ? parent.o.h : parent.o.w) * project.videoHeight)} px`
                                : ""
                        }

                        RowLayout {
                            spacing: 8

                            Action {
                                text: "go to start"
                                onClicked: root.seek(root.selOverlay.start)
                            }
                            Action {
                                text: "remove"
                                tint: Theme.danger
                                onClicked: root.removeSelected()
                            }
                        }
                    }

                    // A piece of the video
                    ColumnLayout {
                        visible: root.selected?.kind === "seg"
                        Layout.fillWidth: true
                        spacing: 10

                        readonly property var g: root.selected?.kind === "seg" ? project.segments[root.selected.i] ?? null : null

                        Label { text: root.selected?.kind === "seg" ? `piece ${root.selected.i + 1} of ${project.segments.length}` : ""; color: Theme.text }
                        Label {
                            Layout.fillWidth: true
                            color: Theme.muted
                            text: parent.g ? `source ${root.fmt(parent.g.a)} to ${root.fmt(parent.g.b)}, ${(parent.g.b - parent.g.a).toFixed(1)} s` : ""
                        }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Theme.muted
                            text: "Removing it closes the gap; pictures and blur boxes after it move along."
                        }
                        Action {
                            text: "remove piece"
                            tint: Theme.danger
                            available: project.segments.length > 1
                            onClicked: root.removeSelected()
                        }
                    }

                    // A channel
                    ColumnLayout {
                        visible: root.selected?.kind === "track"
                        Layout.fillWidth: true
                        spacing: 10

                        readonly property int i: root.selected?.kind === "track" ? root.selected.i : -1
                        readonly property var t: i >= 0 ? project.tracks[i] ?? null : null

                        Label { text: parent.t?.key ?? ""; color: Theme.text }
                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.WrapAnywhere
                            color: Theme.muted
                            text: parent.t ? (parent.t.file !== "" ? parent.t.file.slice(parent.t.file.lastIndexOf("/") + 1) + ", its own track" : "the sound inside the video") : ""
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Label { text: "level"; color: Theme.muted; Layout.preferredWidth: 70 }
                            TuiSlider {
                                Layout.fillWidth: true
                                value: parent.parent.t?.level ?? 1
                                onMoved: v => project.updateTrack(parent.parent.i, { level: v }, false)
                            }
                            Label { text: `${Math.round((parent.parent.t?.level ?? 1) * 100)}%`; Layout.preferredWidth: 40 }
                        }

                        // ± half a second around the measured start, for when a channel sounds late or early
                        RowLayout {
                            visible: parent.t?.file !== ""
                            Layout.fillWidth: true
                            spacing: 10

                            Label { text: "sync"; color: Theme.muted; Layout.preferredWidth: 70 }
                            TuiSlider {
                                Layout.fillWidth: true
                                readonly property var t: parent.parent.t
                                value: t ? 0.5 + (t.offset - (t.base ?? t.offset)) : 0.5
                                onMoved: v => {
                                    const base = t.base ?? t.offset;
                                    project.updateTrack(parent.parent.i, { offset: Math.max(0, base + (v - 0.5)), base }, false);
                                    root.syncTracks(project.toSrc(root.playhead), true);
                                }
                            }
                            Label {
                                readonly property var t: parent.parent.t
                                text: t ? `${Math.round((t.offset - (t.base ?? t.offset)) * 1000)} ms` : ""
                                Layout.preferredWidth: 60
                            }
                        }

                        Action {
                            text: parent.t?.muted ? "unmute" : "mute"
                            onClicked: project.updateTrack(parent.i, { muted: !parent.t.muted })
                        }
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    Action {
                        Layout.alignment: Qt.AlignRight
                        text: "close"
                        onClicked: {
                            root.pause();
                            project.writeNow();
                            root.closeRequested();
                        }
                    }
                }
            }
        }

        Frame {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 2
            Layout.minimumHeight: 300
            label: "timeline"
            padding: 16

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Action {
                        text: root.playing ? "❚❚ pause" : "▶ play"
                        tint: Theme.primary
                        onClicked: root.toggle()
                    }

                    Label {
                        Layout.preferredWidth: 150
                        text: `${root.fmt(root.playhead)} / ${root.fmt(project.outLen)}`
                        color: Theme.text
                    }

                    Action {
                        text: "✂ cut"
                        onClicked: root.cut()
                    }

                    Action {
                        text: "▦ blur"
                        onClicked: root.addBlur()
                    }

                    Action {
                        text: "▣ pictures…"
                        onClicked: Quickshell.execDetached(["xdg-open", `${Quickshell.env("HOME")}/Pictures`])
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    Label {
                        text: "zoom"
                        color: Theme.muted
                    }

                    TuiSlider {
                        Layout.preferredWidth: 120
                        value: (root.pps - 4) / 56
                        onMoved: v => root.pps = 4 + v * 56
                    }

                    Label {
                        visible: project.exporting
                        text: `exporting ${Math.round(project.exportProgress * 100)}%`
                        color: Theme.secondary
                    }

                    Action {
                        visible: !root.confirmRaw
                        text: project.exporting ? "cancel" : "export"
                        tint: project.exporting ? Theme.warn : Theme.primary
                        available: project.exporting || (project.videoWidth > 0 && project.segments.length > 0)
                        onClicked: project.exporting ? project.cancelExport() : project.startExport(false)
                    }

                    Action {
                        visible: !project.exporting && !root.confirmRaw
                        text: "export & delete raw"
                        tint: Theme.danger
                        available: project.videoWidth > 0 && project.segments.length > 0
                        onClicked: root.confirmRaw = true
                    }

                    // Asked in place: no dialog
                    Label {
                        visible: root.confirmRaw
                        text: "then the recording, its tracks and this edit go into the trash?"
                        color: Theme.warn
                    }

                    Action {
                        visible: root.confirmRaw
                        text: "yes"
                        tint: Theme.danger
                        onClicked: {
                            root.confirmRaw = false;
                            project.startExport(true);
                        }
                    }

                    Action {
                        visible: root.confirmRaw
                        text: "no"
                        onClicked: root.confirmRaw = false
                    }
                }

                // Export progress under the transport
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 2
                    color: project.exporting ? Theme.border : "transparent"

                    Rectangle {
                        width: parent.width * project.exportProgress
                        height: parent.height
                        color: Theme.primary
                        visible: project.exporting
                    }
                }

                EditorTimeline {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    editor: root
                }
            }
        }
    }
}
