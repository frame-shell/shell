import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// One picture being edited: blur boxes and pictures on top, and a crop. Kept next to the
// picture as <name>.edit.json; the picture itself is never changed, export writes
// <name>-edit.png. x, y, w, h (overlays and the crop) are fractions of the picture.
Scope {
    id: root

    property string image: ""
    readonly property string stem: image.replace(/\.[^./]+$/, "")
    readonly property string editFile: stem === "" ? "" : `${stem}.edit.json`
    readonly property string exportFile: stem === "" ? "" : `${stem}-edit.png`
    readonly property string name: image.slice(image.lastIndexOf("/") + 1)

    // From the shown picture once it is loaded
    property int imageWidth: 0
    property int imageHeight: 0

    property var overlays: []
    property var crop: ({ x: 0, y: 0, w: 1, h: 1 })
    readonly property bool cropped: crop.x > 0.001 || crop.y > 0.001 || crop.w < 0.999 || crop.h < 0.999

    property var undoStack: []

    function load(path) {
        if (path === image)
            return;
        save.stop();
        image = path;
        imageWidth = 0;
        imageHeight = 0;
        undoStack = [];
        overlays = [];
        crop = { x: 0, y: 0, w: 1, h: 1 };
        editView.path = editFile;
        try {
            const text = editView.text();
            const saved = text.trim() !== "" ? JSON.parse(text) : null;
            if (saved && saved.version === 1) {
                overlays = saved.overlays ?? [];
                crop = saved.crop ?? crop;
            }
        } catch (e) {
            // A broken file starts fresh; it is written again on the first change
        }
    }

    function changed() {
        save.restart();
    }

    function writeNow() {
        if (editFile === "")
            return;
        // Nothing done yet: no file next to the picture
        if (overlays.length === 0 && !cropped && editView.text().trim() === "")
            return;
        editView.setText(JSON.stringify({ version: 1, image, overlays, crop }, null, 1));
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

    // ── Editing ──────────────────────────────────────────────

    function snapshot() {
        undoStack = undoStack.concat([JSON.stringify({ overlays, crop })]).slice(-60);
    }

    function undo() {
        if (undoStack.length === 0)
            return false;
        const last = JSON.parse(undoStack[undoStack.length - 1]);
        undoStack = undoStack.slice(0, -1);
        overlays = last.overlays;
        crop = last.crop;
        changed();
        return true;
    }

    function nextId() {
        let id = 1;
        for (const o of overlays)
            id = Math.max(id, o.id + 1);
        return id;
    }

    function overlay(id) {
        return overlays.find(o => o.id === id) ?? null;
    }

    function addBlur(cx, cy) {
        snapshot();
        const id = nextId();
        const w = 0.2, h = 0.12;
        overlays = overlays.concat([{
            id, type: "blur", name: `blur ${id}`,
            x: Math.max(0, Math.min(1 - w, cx - w / 2)), y: Math.max(0, Math.min(1 - h, cy - h / 2)), w, h,
            strength: 14, style: "blur"
        }]);
        changed();
        return id;
    }

    // h -1: set from the picture's own shape once it is loaded (OverlayBox)
    function addPicture(path, cx, cy) {
        snapshot();
        const id = nextId();
        const w = 0.2;
        overlays = overlays.concat([{
            id, type: "picture", name: path.slice(path.lastIndexOf("/") + 1), src: path,
            x: Math.max(0, Math.min(1 - w, cx - w / 2)), y: Math.max(0, Math.min(0.9, cy - 0.1)), w, h: -1, opacity: 1
        }]);
        changed();
        return id;
    }

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

    function setCrop(next, undoable) {
        if (undoable !== false)
            snapshot();
        const x = Math.max(0, Math.min(0.98, next.x)), y = Math.max(0, Math.min(0.98, next.y));
        crop = { x, y, w: Math.max(0.02, Math.min(1 - x, next.w)), h: Math.max(0.02, Math.min(1 - y, next.h)) };
        changed();
    }

    // ── Export ───────────────────────────────────────────────

    property bool exporting: false
    property string exportError: ""

    // ffmpeg's arguments: blur boxes and pictures on the full picture, the crop last
    function exportArgs() {
        const W = imageWidth, H = imageHeight;
        const px = (v, d) => Math.max(0, Math.round(v * d));
        const pictures = overlays.filter(o => o.type === "picture");
        const blurs = overlays.filter(o => o.type === "blur");
        const args = ["-y", "-nostdin", "-v", "error", "-i", image];
        for (const o of pictures)
            args.push("-i", o.src);

        const fc = ["[0:v]format=rgba[base]"];
        let last = "base";
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
                fx = `boxblur=${Math.max(1, Math.min(Math.round(o.strength * 1.5), Math.floor(Math.min(w, h) / 2) - 1))}:2`;
            }
            fc.push(`[${last}]split[b${k}][s${k}]`);
            fc.push(`[s${k}]crop=${w}:${h}:${x}:${y},${fx}[f${k}]`);
            fc.push(`[b${k}][f${k}]overlay=${x}:${y}[o${k}]`);
            last = `o${k}`;
            k++;
        }
        pictures.forEach((o, i) => {
            const ph = o.h > 0 ? o.h : o.w;
            fc.push(`[${1 + i}:v]scale=${Math.max(2, px(o.w, W))}:${Math.max(2, px(ph, H))},format=rgba,colorchannelmixer=aa=${Number(o.opacity.toFixed(3))}[p${i}]`);
            fc.push(`[${last}][p${i}]overlay=${px(o.x, W)}:${px(o.y, H)}[o${k}]`);
            last = `o${k}`;
            k++;
        });
        const cx = px(crop.x, W), cy = px(crop.y, H);
        fc.push(`[${last}]crop=${Math.max(1, Math.min(W - cx, px(crop.w, W)))}:${Math.max(1, Math.min(H - cy, px(crop.h, H)))}:${cx}:${cy}[out]`);
        args.push("-filter_complex", fc.join(";"), "-map", "[out]", "-frames:v", "1", "-update", "1", exportFile);
        return args;
    }

    function startExport() {
        if (exporting || imageWidth <= 0)
            return;
        writeNow();
        exportError = "";
        exporting = true;
        exportProc.command = ["ffmpeg"].concat(exportArgs());
        exportProc.running = true;
    }

    Process {
        id: exportProc

        stderr: StdioCollector {
            id: exportErrors
        }
        onExited: code => {
            root.exporting = false;
            const file = root.exportFile;
            const name = file.slice(file.lastIndexOf("/") + 1);
            if (code !== 0) {
                root.exportError = exportErrors.text.trim().split("\n").pop() || `ffmpeg stopped (${code})`;
                Notifications.push({ app: "editor", glyph: "✗", title: "export failed", body: root.exportError });
                return;
            }
            Notifications.push({
                app: "editor",
                title: "picture exported",
                body: name,
                image: file,
                actions: [
                    { id: "open", label: "open", style: "ok" },
                    { id: "copy", label: "copy", style: "" },
                    { id: "folder", label: "folder", style: "" }
                ],
                onAction: id => {
                    if (id === "open")
                        Quickshell.execDetached(["xdg-open", file]);
                    else if (id === "copy")
                        // As the picture itself, for pasting into chats
                        Quickshell.execDetached(["sh", "-c", 'wl-copy --type image/png < "$1"', "frame-edit", file]);
                    else if (id === "folder")
                        Quickshell.execDetached(["xdg-open", file.slice(0, file.lastIndexOf("/"))]);
                }
            });
        }
    }
}
