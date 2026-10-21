import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// One recording being edited: what stays of it (segments), what goes on top (pictures, blur
// boxes) and how loud each channel is. Kept next to the video as <name>.edit.json, so closing
// the editor loses nothing; the video itself is never changed, export writes <name>-edit.mp4.
//
// Times are seconds. Segments are pieces of the source video that stay, in order; the output
// timeline is those pieces back to back. Overlays live on the output timeline. x, y, w, h are
// fractions of the video frame. A track's offset is where the track is when the video is at 0
// (its recorder started that much earlier), so track time = source time + offset.
Scope {
    id: root

    property string video: ""
    readonly property string stem: video.replace(/\.[^./]+$/, "")
    readonly property string editFile: stem === "" ? "" : `${stem}.edit.json`
    readonly property string exportFile: stem === "" ? "" : `${stem}-edit.mp4`
    readonly property string name: video.slice(video.lastIndexOf("/") + 1)

    // From the player once it knows the file
    property real duration: 0
    property int videoWidth: 0
    property int videoHeight: 0
    property bool videoHasAudio: false

    property var segments: []
    property var overlays: []
    // [{ key, file, level, muted, offset }]; without separate tracks one entry for the
    // video's own sound (file "")
    property var tracks: []
    // key → [0..1] at peakRate values per second of the track's own time
    property var peaks: ({})
    readonly property int peakRate: 25

    readonly property real outLen: {
        let s = 0;
        for (const g of segments)
            s += g.b - g.a;
        return s;
    }
    readonly property bool separateTracks: tracks.some(t => t.file !== "")

    property var undoStack: []
    // Something was changed since the last write; opening alone writes no file
    property bool dirty: false

    // ── Time ─────────────────────────────────────────────────

    // Output time → { i: segment, src: source time }
    function locate(t) {
        let acc = 0;
        for (let i = 0; i < segments.length; i++) {
            const len = segments[i].b - segments[i].a;
            if (t < acc + len || i === segments.length - 1)
                return { i, src: segments[i].a + Math.max(0, Math.min(len, t - acc)) };
            acc += len;
        }
        return { i: 0, src: 0 };
    }

    function toSrc(t) {
        return locate(t).src;
    }

    // Where segment i starts on the output timeline
    function segStart(i) {
        let acc = 0;
        for (let k = 0; k < i && k < segments.length; k++)
            acc += segments[k].b - segments[k].a;
        return acc;
    }

    // ── Loading and saving ───────────────────────────────────

    function load(path) {
        if (path === video && segments.length > 0)
            return;
        save.stop();
        dirty = false;
        video = path;
        duration = 0;
        videoWidth = 0;
        videoHeight = 0;
        peaks = {};
        undoStack = [];
        segments = [];
        overlays = [];
        tracks = [];

        let saved = null;
        editView.path = editFile;
        try {
            const text = editView.text();
            if (text.trim() !== "")
                saved = JSON.parse(text);
        } catch (e) {
            saved = null;
        }
        if (saved && saved.version === 1) {
            segments = saved.segments ?? [];
            overlays = saved.overlays ?? [];
            tracks = saved.tracks ?? [];
        }
        if (tracks.length === 0)
            tracks = recordedTracks();
        loadPeaks();
    }

    // The separate channels the recorder wrote (Recorder.qml, frame-record-mix tracks), lined up
    // by the moment each recorder and the picture started
    function recordedTracks() {
        const dir = Recorder.tracksDir(video);
        let manifest = null;
        let videoStarted = 0;
        tracksView.path = `${dir}/tracks.json`;
        startedView.path = `${dir}/video-started`;
        try {
            const text = tracksView.text();
            if (text.trim() !== "")
                manifest = JSON.parse(text);
            videoStarted = Number(startedView.text().trim()) || 0;
        } catch (e) {
            manifest = null;
        }
        if (!manifest || !Array.isArray(manifest.tracks) || manifest.tracks.length === 0)
            return [{ key: "recording", file: "", level: 1, muted: false, offset: 0 }];
        return manifest.tracks.map(t => {
            const offset = videoStarted > 0 && t.started > 0 ? Math.max(0, (videoStarted - t.started) / 1000) : 0;
            // base: the measured offset, which the sync slider moves around
            return {
                key: t.key,
                file: `${dir}/${t.file}`,
                level: Math.max(0, Math.min(1, Number(t.level ?? 1))),
                muted: false,
                offset,
                base: offset
            };
        });
    }

    // The player knows the length; a fresh project keeps all of it
    function setDuration(seconds) {
        duration = seconds;
        if (seconds <= 0)
            return;
        if (segments.length === 0)
            segments = [{ a: 0, b: seconds }];
        else
            segments = segments.map(g => ({ a: Math.min(g.a, seconds), b: Math.min(g.b, seconds) })).filter(g => g.b - g.a > 0.05);
        if (segments.length === 0)
            segments = [{ a: 0, b: seconds }];
    }

    function changed() {
        dirty = true;
        save.restart();
    }

    function writeNow() {
        if (!dirty || editFile === "" || segments.length === 0)
            return;
        dirty = false;
        editView.setText(JSON.stringify({ version: 1, video, segments, overlays, tracks }, null, 1));
    }

    Timer {
        id: save
        interval: 800
        onTriggered: root.writeNow()
    }

    FileView {
        id: editView
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: tracksView
        blockLoading: true
        printErrors: false
    }

    FileView {
        id: startedView
        blockLoading: true
        printErrors: false
    }

    // ── Editing ──────────────────────────────────────────────

    function snapshot() {
        undoStack = undoStack.concat([JSON.stringify({ segments, overlays, tracks })]).slice(-60);
    }

    function undo() {
        if (undoStack.length === 0)
            return false;
        const last = JSON.parse(undoStack[undoStack.length - 1]);
        undoStack = undoStack.slice(0, -1);
        segments = last.segments;
        overlays = last.overlays;
        tracks = last.tracks;
        changed();
        return true;
    }

    // Splits the piece under the playhead; returns the index of the new right half, or -1
    function cut(t) {
        let acc = 0;
        for (let i = 0; i < segments.length; i++) {
            const g = segments[i];
            const len = g.b - g.a;
            if (t > acc + 0.1 && t < acc + len - 0.1) {
                snapshot();
                const at = g.a + (t - acc);
                const next = segments.slice();
                next.splice(i, 1, { a: g.a, b: at }, { a: at, b: g.b });
                segments = next;
                changed();
                return i + 1;
            }
            acc += len;
        }
        return -1;
    }

    // Removes a piece and closes the gap; overlays after it move along, ones inside it shrink
    function removeSegment(i) {
        if (segments.length < 2 || i < 0 || i >= segments.length)
            return;
        snapshot();
        const start = segStart(i);
        const len = segments[i].b - segments[i].a;
        const end = start + len;
        const shift = t => t <= start ? t : t >= end ? t - len : start;
        const next = segments.slice();
        next.splice(i, 1);
        segments = next;
        overlays = overlays.map(o => Object.assign({}, o, { start: shift(o.start), end: shift(o.end) })).filter(o => o.end - o.start > 0.1);
        changed();
    }

    function nextId() {
        let id = 1;
        for (const o of overlays)
            id = Math.max(id, o.id + 1);
        return id;
    }

    function addBlur(t) {
        snapshot();
        const id = nextId();
        overlays = overlays.concat([{
            id, type: "blur", name: `blur ${id}`, start: t, end: Math.min(outLen, t + 10),
            x: 0.4, y: 0.35, w: 0.2, h: 0.2, strength: 14, style: "blur"
        }]);
        changed();
        return id;
    }

    // h -1: set from the picture's own shape once it is loaded (EditorView)
    function addPicture(t, path, cx, cy) {
        snapshot();
        const id = nextId();
        const w = 0.18;
        overlays = overlays.concat([{
            id, type: "picture", name: path.slice(path.lastIndexOf("/") + 1), src: path,
            start: t, end: Math.min(outLen, t + 10),
            x: Math.max(0, Math.min(1 - w, cx - w / 2)), y: Math.max(0, Math.min(0.9, cy - 0.1)), w, h: -1, opacity: 1
        }]);
        changed();
        return id;
    }

    function overlay(id) {
        return overlays.find(o => o.id === id) ?? null;
    }

    // Changes while dragging pass undoable false and take one snapshot at the start
    function updateOverlay(id, changes, undoable) {
        if (undoable !== false)
            snapshot();
        overlays = overlays.map(o => o.id === id ? Object.assign({}, o, changes) : o);
        changed();
    }

    function removeOverlay(id) {
        snapshot();
        overlays = overlays.filter(o => o.id !== id);
        changed();
    }

    function updateTrack(i, changes, undoable) {
        if (undoable !== false)
            snapshot();
        tracks = tracks.map((t, k) => k === i ? Object.assign({}, t, changes) : t);
        changed();
    }

    // ── Waveforms ────────────────────────────────────────────
    // ffmpeg's peak level per window of 1/peakRate s, one line each (dBFS)

    property var peakQueue: []

    function loadPeaks() {
        peakQueue = tracks.map(t => ({ key: t.key, file: t.file !== "" ? t.file : video }));
        nextPeaks();
    }

    function nextPeaks() {
        if (peakProc.running || peakQueue.length === 0)
            return;
        const job = peakQueue[0];
        peakQueue = peakQueue.slice(1);
        peakProc.key = job.key;
        peakProc.values = [];
        peakProc.command = ["ffmpeg", "-nostdin", "-v", "error", "-i", job.file, "-vn", "-af",
            `aresample=8000,aformat=channel_layouts=mono,asetnsamples=n=${8000 / peakRate}:p=0,astats=metadata=1:reset=1,ametadata=mode=print:key=lavfi.astats.Overall.Peak_level:file=-`,
            "-f", "null", "-"];
        peakProc.running = true;
    }

    Process {
        id: peakProc

        property string key: ""
        property var values: []

        stdout: SplitParser {
            onRead: line => {
                const m = /Peak_level=(-?[0-9.]+|-inf)/.exec(line);
                if (!m)
                    return;
                const db = m[1] === "-inf" ? -120 : Number(m[1]);
                peakProc.values.push(Math.max(0, Math.min(1, Math.pow(10, db / 20))));
            }
        }
        onExited: {
            const next = Object.assign({}, root.peaks);
            next[key] = values;
            root.peaks = next;
            root.nextPeaks();
        }
    }

    // ── Export ───────────────────────────────────────────────

    property bool exporting: false
    // "export & delete raw": once the export worked, the original goes into the trash with
    // what belongs to it (frame-media trash), and the editor closes
    property bool deleteAfterExport: false
    signal originalDeleted()
    property real exportProgress: 0
    property string exportError: ""

    // ffmpeg's arguments for the whole project: the pieces back to back, blur boxes and
    // pictures on top, every audible track at its level, mixed
    function exportArgs() {
        const f = v => Number(v.toFixed(3));
        const W = videoWidth, H = videoHeight;
        const px = (v, d) => Math.max(0, Math.round(v * d));
        const audible = tracks.filter(t => !t.muted && t.level > 0 && (t.file !== "" || videoHasAudio));
        const own = audible.filter(t => t.file === "");
        const files = audible.filter(t => t.file !== "");
        const pictures = overlays.filter(o => o.type === "picture");
        const blurs = overlays.filter(o => o.type === "blur");

        const args = ["-y", "-nostdin", "-v", "error", "-progress", "pipe:1", "-i", video];
        for (const t of files)
            args.push("-i", t.file);
        // A still picture as an endless stream (pattern_type none: a % in the name is no
        // pattern); a GIF keeps playing its own loop
        for (const o of pictures) {
            if (/\.gif$/i.test(o.src))
                args.push("-ignore_loop", "0", "-i", o.src);
            else
                args.push("-f", "image2", "-pattern_type", "none", "-loop", "1", "-i", o.src);
        }

        const fc = [];
        const n = segments.length;
        segments.forEach((g, i) => fc.push(`[0:v]trim=start=${f(g.a)}:end=${f(g.b)},setpts=PTS-STARTPTS[v${i}]`));
        fc.push(`${segments.map((_, i) => `[v${i}]`).join("")}concat=n=${n}:v=1:a=0[vcut]`);
        let last = "vcut";
        let k = 0;

        for (const o of blurs) {
            const x = px(o.x, W), y = px(o.y, H);
            const w = Math.max(2, Math.min(W - x, px(o.w, W))), h = Math.max(2, Math.min(H - y, px(o.h, H)));
            let fx;
            if (o.style === "pixel") {
                const block = Math.max(4, o.strength * 1.4);
                fx = `scale=${Math.max(1, Math.round(w / block))}:${Math.max(1, Math.round(h / block))}:flags=area,scale=${w}:${h}:flags=neighbor`;
            } else {
                // boxblur's radius may not exceed half the box
                const r = Math.max(1, Math.min(Math.round(o.strength * 1.5), Math.floor(Math.min(w, h) / 2) - 1));
                fx = `boxblur=${r}:2`;
            }
            fc.push(`[${last}]split[base${k}][src${k}]`);
            fc.push(`[src${k}]format=rgba,crop=${w}:${h}:${x}:${y},${fx}[fx${k}]`);
            fc.push(`[base${k}][fx${k}]overlay=${x}:${y}:enable='between(t,${f(o.start)},${f(o.end)})'[o${k}]`);
            last = `o${k}`;
            k++;
        }

        pictures.forEach((o, i) => {
            const input = 1 + files.length + i;
            const ph = o.h > 0 ? o.h : o.w;
            fc.push(`[${input}:v]scale=${Math.max(2, px(o.w, W))}:${Math.max(2, px(ph, H))},format=rgba,colorchannelmixer=aa=${f(o.opacity)}[p${i}]`);
            fc.push(`[${last}][p${i}]overlay=${px(o.x, W)}:${px(o.y, H)}:shortest=1:enable='between(t,${f(o.start)},${f(o.end)})'[o${k}]`);
            last = `o${k}`;
            k++;
        });
        // x264 wants even sizes; a region recording can be odd
        fc.push(`[${last}]scale=trunc(iw/2)*2:trunc(ih/2)*2,format=yuv420p[vout]`);

        // Each track cut like the picture, shifted by its offset, at its level
        const labels = [];
        const trackInput = t => t.file === "" ? 0 : 1 + files.indexOf(t);
        [...own, ...files].forEach((t, j) => {
            const input = trackInput(t);
            segments.forEach((g, i) => {
                const a = g.a + t.offset, b = g.b + t.offset;
                const pad = a < 0 ? `,adelay=${Math.round(-a * 1000)}:all=1` : "";
                fc.push(`[${input}:a]atrim=start=${f(Math.max(0, a))}:end=${f(Math.max(0.01, b))},asetpts=PTS-STARTPTS${pad}[a${j}s${i}]`);
            });
            fc.push(`${segments.map((_, i) => `[a${j}s${i}]`).join("")}concat=n=${n}:v=0:a=1,volume=${f(t.level)}[a${j}]`);
            labels.push(`[a${j}]`);
        });
        if (labels.length > 1)
            fc.push(`${labels.join("")}amix=inputs=${labels.length}:duration=longest:normalize=0[aout]`);

        args.push("-filter_complex", fc.join(";"), "-map", "[vout]");
        if (labels.length > 1)
            args.push("-map", "[aout]");
        else if (labels.length === 1)
            args.push("-map", labels[0]);
        args.push("-t", String(f(outLen)), "-c:v", "libx264", "-crf", "20", "-preset", "medium");
        if (labels.length > 0)
            args.push("-c:a", "aac", "-b:a", "192k");
        args.push("-movflags", "+faststart", exportFile);
        return args;
    }

    function startExport(deleteOriginal) {
        if (exporting || videoWidth <= 0 || segments.length === 0)
            return;
        deleteAfterExport = deleteOriginal === true;
        writeNow();
        exportError = "";
        exportProgress = 0;
        exporting = true;
        exportProc.command = ["ffmpeg"].concat(exportArgs());
        exportProc.running = true;
    }

    function cancelExport() {
        if (!exportProc.running)
            return;
        exportProc.cancelled = true;
        exportProc.signal(15);
    }

    Process {
        id: exportProc

        property bool cancelled: false

        stdout: SplitParser {
            onRead: line => {
                const m = /^out_time_us=(\d+)/.exec(line);
                if (m && root.outLen > 0)
                    root.exportProgress = Math.min(1, Number(m[1]) / 1e6 / root.outLen);
            }
        }
        stderr: StdioCollector {
            id: exportErrors
        }
        onExited: code => {
            root.exporting = false;
            const file = root.exportFile;
            const name = file.slice(file.lastIndexOf("/") + 1);
            if (cancelled) {
                cancelled = false;
                root.exportProgress = 0;
                Quickshell.execDetached(["rm", "-f", "--", file]);
                return;
            }
            if (code !== 0) {
                root.exportError = exportErrors.text.trim().split("\n").pop() || `ffmpeg stopped (${code})`;
                Notifications.push({ app: "recording", glyph: "✗", title: "export failed", body: root.exportError });
                return;
            }
            root.exportProgress = 1;
            const removed = root.deleteAfterExport;
            if (removed) {
                root.deleteAfterExport = false;
                Quickshell.execDetached([`${Quickshell.env("HOME")}/.local/bin/frame-media`, "trash", root.video]);
                root.originalDeleted();
            }
            Notifications.push({
                app: "recording",
                glyph: "●",
                title: removed ? "edit exported · original in the trash" : "edit exported",
                body: name,
                actions: [
                    { id: "open", label: "open", style: "ok" },
                    { id: "folder", label: "folder", style: "" },
                    { id: "copy", label: "copy", style: "" }
                ],
                onAction: id => {
                    if (id === "open")
                        Quickshell.execDetached(["xdg-open", file]);
                    else if (id === "folder")
                        Quickshell.execDetached(["xdg-open", file.slice(0, file.lastIndexOf("/"))]);
                    else if (id === "copy")
                        Quickshell.execDetached(["sh", "-c", 'printf "file://%s\\n" "$1" | wl-copy --type text/uri-list', "frame-edit", file]);
                }
            });
        }
    }
}
