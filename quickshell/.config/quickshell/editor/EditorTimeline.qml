import QtQuick
import qs.components
import qs.config

// The editor's timeline: a ruler with the cut marks, the pieces of the video, a row for blur
// boxes and one for pictures, then one row per channel with its waveform. Names on the left,
// the lanes scroll; wheel scrolls through time, Ctrl+wheel zooms.
//
// The rows are built from counts (segments.length, overlays.length …), so dragging a bar,
// which replaces the arrays, keeps the item under the mouse.
Item {
    id: root

    required property var editor
    readonly property var project: editor.project
    readonly property real pps: editor.pps

    readonly property int labelW: 190
    readonly property int rulerH: 26
    readonly property int rowH: 40
    readonly property int audioH: 50
    readonly property real laneW: Math.max(flick.width, project.outLen * pps + 80)
    readonly property real contentH: rulerH + rowH * 3 + audioH * project.tracks.length

    clip: true

    function rowY(row) {
        // 0 video, 1 blur, 2 pictures, 3… tracks
        return row < 3 ? rulerH + row * rowH : rulerH + rowH * 3 + (row - 3) * audioH;
    }

    function timeAt(x) {
        return Math.max(0, Math.min(project.outLen, x / pps));
    }

    // Keeps the playhead in view while it plays
    Connections {
        target: root.editor

        function onPlayheadChanged() {
            if (!root.editor.playing)
                return;
            const x = root.editor.playhead * root.pps;
            if (x > flick.contentX + flick.width - 40 || x < flick.contentX)
                flick.contentX = Math.max(0, Math.min(root.laneW - flick.width, x - 40));
        }
    }

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: 12
        elide: Text.ElideRight
    }

    // ── Names on the left ────────────────────────────────────

    Item {
        id: names

        width: root.labelW
        height: parent.height
        clip: true
        z: 2

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
        }

        Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: Theme.frame
        }

        Item {
            y: -flick.contentY
            width: parent.width
            height: root.contentH

            Label {
                x: 8
                y: (root.rulerH - height) / 2
                text: `output ${root.editor.fmt(root.project.outLen)}`
                color: Theme.muted
            }

            Repeater {
                model: ["▣ video", "▦ blur", "▣ pictures"]
                delegate: Label {
                    required property string modelData
                    required property int index
                    x: 8
                    y: root.rowY(index) + (root.rowH - height) / 2
                    width: root.labelW - 16
                    text: modelData
                }
            }

            Repeater {
                model: root.project.tracks.length
                delegate: Item {
                    id: trackName

                    required property int index
                    readonly property var track: root.project.tracks[index] ?? null
                    readonly property bool isSelected: root.editor.selected?.kind === "track" && root.editor.selected.i === index

                    y: root.rowY(3 + index)
                    width: root.labelW - 1
                    height: root.audioH

                    Rectangle {
                        anchors.fill: parent
                        color: trackName.isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : "transparent"
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.editor.select({ kind: "track", i: trackName.index })
                    }

                    TuiButton {
                        id: muteButton
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 20
                        active: trackName.track?.muted ?? false
                        accent: Theme.danger
                        onClicked: root.project.updateTrack(trackName.index, { muted: !trackName.track.muted })

                        Text {
                            anchors.centerIn: parent
                            text: "m"
                            color: muteButton.active ? Theme.danger : Theme.muted
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                    }

                    Label {
                        x: 38
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 38 - 70
                        text: trackName.track?.key ?? ""
                        color: trackName.track?.muted ? Theme.muted : Theme.textDim
                    }

                    TuiSlider {
                        x: parent.width - 64
                        anchors.verticalCenter: parent.verticalCenter
                        width: 54
                        value: trackName.track?.level ?? 1
                        dimmed: trackName.track?.muted ?? false
                        onMoved: v => root.project.updateTrack(trackName.index, { level: v }, false)
                    }
                }
            }
        }
    }

    // ── Lanes ────────────────────────────────────────────────

    Flickable {
        id: flick

        x: root.labelW
        width: parent.width - root.labelW
        height: parent.height
        contentWidth: root.laneW
        contentHeight: root.contentH
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: false

        // Empty lanes: click or drag to move the playhead; wheel through time, Ctrl+wheel zoom
        MouseArea {
            width: root.laneW
            height: Math.max(root.contentH, flick.height)
            onPressed: mouse => {
                root.editor.forceActiveFocus();
                root.editor.seek(root.timeAt(mouse.x));
            }
            onPositionChanged: mouse => {
                if (pressed)
                    root.editor.seek(root.timeAt(mouse.x));
            }
            onWheel: wheel => {
                if (wheel.modifiers & Qt.ControlModifier) {
                    const t = root.timeAt(wheel.x);
                    const next = Math.max(4, Math.min(60, root.editor.pps * (wheel.angleDelta.y > 0 ? 1.2 : 1 / 1.2)));
                    root.editor.pps = next;
                    flick.contentX = Math.max(0, t * next - (wheel.x - flick.contentX));
                } else if (wheel.modifiers & Qt.ShiftModifier) {
                    flick.contentY = Math.max(0, Math.min(root.contentH - flick.height, flick.contentY - wheel.angleDelta.y / 2));
                } else {
                    const d = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : wheel.angleDelta.y;
                    flick.contentX = Math.max(0, Math.min(root.laneW - flick.width, flick.contentX - d));
                }
            }
        }

        // Ruler and cut marks, drawn for the visible part only
        Canvas {
            id: ruler

            x: flick.contentX
            width: flick.width
            height: root.rulerH

            property real from: flick.contentX
            property real zoom: root.pps
            property var segs: root.project.segments
            property color tick: Theme.frame
            property color label: Theme.muted
            property color mark: Theme.warn
            onFromChanged: requestPaint()
            onZoomChanged: requestPaint()
            onSegsChanged: requestPaint()
            onWidthChanged: requestPaint()

            onPaint: {
                const g = getContext("2d");
                g.reset();
                g.font = `11px "${Theme.font}"`;
                const step = zoom >= 30 ? 1 : zoom >= 12 ? 2 : zoom >= 6 ? 5 : 10;
                const first = Math.floor(from / zoom / step) * step;
                const last = (from + width) / zoom;
                for (let s = first; s <= last && s <= root.project.outLen; s += step) {
                    const x = Math.round(s * zoom - from) + 0.5;
                    const major = Math.round(s / step) % 5 === 0;
                    g.fillStyle = tick;
                    g.fillRect(x, major ? 12 : 18, 1, height);
                    if (major) {
                        g.fillStyle = label;
                        g.fillText(root.editor.fmt(s).replace(/\.0$/, ""), x + 3, 11);
                    }
                }
                let acc = 0;
                g.fillStyle = mark;
                for (let i = 0; i < segs.length - 1; i++) {
                    acc += segs[i].b - segs[i].a;
                    g.fillRect(Math.round(acc * zoom - from), 0, 2, height);
                }
            }
        }

        // The pieces of the video
        Repeater {
            model: root.project.segments.length
            delegate: Rectangle {
                id: piece

                required property int index
                readonly property var g: root.project.segments[index] ?? null
                readonly property bool isSelected: root.editor.selected?.kind === "seg" && root.editor.selected.i === index

                x: root.project.segStart(index) * root.pps
                y: root.rowY(0) + 6
                width: Math.max(2, (g ? g.b - g.a : 0) * root.pps - 2)
                height: root.rowH - 12
                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, isSelected ? 0.42 : 0.2)
                border.width: 1
                border.color: isSelected ? Theme.secondary : Theme.primary

                Text {
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 12
                    text: piece.g ? `${root.editor.fmt(piece.g.a)}–${root.editor.fmt(piece.g.b)}` : ""
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: mouse => {
                        root.editor.forceActiveFocus();
                        root.editor.select({ kind: "seg", i: piece.index });
                        root.editor.seek(root.timeAt(piece.x + mouse.x));
                    }
                }
            }
        }

        // Blur boxes and pictures: drag to move, drag an edge to change from or to
        Repeater {
            model: root.project.overlays.length
            delegate: Rectangle {
                id: bar

                required property int index
                readonly property var o: root.project.overlays[index] ?? null
                readonly property bool isBlur: o?.type === "blur"
                readonly property bool isSelected: o !== null && root.editor.selOverlay !== null && root.editor.selOverlay.id === o.id
                readonly property color tint: isBlur ? Theme.warn : Theme.accent

                visible: o !== null
                x: (o?.start ?? 0) * root.pps
                y: root.rowY(isBlur ? 1 : 2) + 8
                width: Math.max(10, ((o?.end ?? 0) - (o?.start ?? 0)) * root.pps)
                height: root.rowH - 16
                color: Qt.rgba(tint.r, tint.g, tint.b, isSelected ? 0.4 : 0.18)
                border.width: 1
                border.color: isSelected ? Theme.text : tint

                Text {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 16
                    text: bar.o?.name ?? ""
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                MouseArea {
                    property string mode: "move"
                    property real x0: 0
                    property real s0: 0
                    property real e0: 0

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: mouseX < 7 || mouseX > width - 7 ? Qt.SizeHorCursor : Qt.OpenHandCursor
                    onPressed: mouse => {
                        root.editor.forceActiveFocus();
                        root.editor.select({ kind: "overlay", id: bar.o.id });
                        root.project.snapshot();
                        mode = mouse.x < 7 ? "start" : mouse.x > width - 7 ? "end" : "move";
                        x0 = mapToItem(flick.contentItem, mouse.x, 0).x;
                        s0 = bar.o.start;
                        e0 = bar.o.end;
                    }
                    onPositionChanged: mouse => {
                        if (!pressed)
                            return;
                        const d = (mapToItem(flick.contentItem, mouse.x, 0).x - x0) / root.pps;
                        const L = root.project.outLen;
                        let start = s0, end = e0;
                        if (mode === "move") {
                            start = Math.max(0, Math.min(L - (e0 - s0), s0 + d));
                            end = start + (e0 - s0);
                        } else if (mode === "start") {
                            start = Math.max(0, Math.min(e0 - 0.3, s0 + d));
                        } else {
                            end = Math.max(s0 + 0.3, Math.min(L, e0 + d));
                        }
                        root.project.updateOverlay(bar.o.id, { start, end }, false);
                    }
                }
            }
        }

        // One waveform per channel, drawn for the visible part only
        Repeater {
            model: root.project.tracks.length
            delegate: Item {
                id: lane

                required property int index
                readonly property var track: root.project.tracks[index] ?? null

                y: root.rowY(3 + index)
                width: root.laneW
                height: root.audioH

                Rectangle {
                    y: parent.height - 1
                    width: parent.width
                    height: 1
                    color: Theme.border
                }

                Canvas {
                    id: wave

                    x: flick.contentX
                    width: flick.width
                    height: parent.height

                    property real from: flick.contentX
                    property real zoom: root.pps
                    property var values: root.project.peaks[lane.track?.key ?? ""] ?? []
                    property var segs: root.project.segments
                    property real level: lane.track?.level ?? 1
                    property bool muted: lane.track?.muted ?? false
                    property real offset: lane.track && lane.track.file !== "" ? lane.track.offset : 0
                    property color fill: muted ? Theme.frame : Theme.secondary
                    onFromChanged: requestPaint()
                    onZoomChanged: requestPaint()
                    onValuesChanged: requestPaint()
                    onSegsChanged: requestPaint()
                    onLevelChanged: requestPaint()
                    onMutedChanged: requestPaint()
                    onOffsetChanged: requestPaint()
                    onWidthChanged: requestPaint()

                    onPaint: {
                        const g = getContext("2d");
                        g.reset();
                        const mid = height / 2;
                        g.fillStyle = fill;
                        if (values.length === 0) {
                            g.fillRect(0, mid, Math.min(width, root.project.outLen * zoom - from), 1);
                            return;
                        }
                        const gain = muted ? 0.4 : Math.max(0.05, level);
                        const rate = root.project.peakRate;
                        for (let x = 0; x < width; x += 2) {
                            const t = (from + x) / zoom;
                            if (t > root.project.outLen)
                                break;
                            const v = values[Math.floor((root.project.toSrc(t) + offset) * rate)] ?? 0;
                            const a = Math.max(0.5, v * gain * (mid - 4));
                            g.fillRect(x, mid - a, 1, a * 2);
                        }
                    }
                }
            }
        }

        // Playhead
        Rectangle {
            x: root.editor.playhead * root.pps
            width: 1
            height: Math.max(root.contentH, flick.height)
            color: Theme.danger
            z: 5

            Rectangle {
                x: -4
                width: 9
                height: 6
                color: Theme.danger
            }
        }
    }
}
