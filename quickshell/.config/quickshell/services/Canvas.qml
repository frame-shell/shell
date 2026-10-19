pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The infinite-canvas layout (hypr/frame/canvas.lua) as the bar sees it.
// enabled: ~/.local/state/frameshell/layout says "canvas" (`frame layout canvas`).
// The rest comes from $XDG_RUNTIME_DIR/frame-canvas.json, which canvas.lua rewrites on
// every change: { workspace, camera: { x, y }, view: { w, h },
//   windows: [{ x, y, w, h, active, class, title }] } in canvas coordinates.
Singleton {
    id: root

    property bool enabled: false
    property var camera: ({ x: 0, y: 0 })
    property var view: ({ w: 1920, h: 1080 })
    property var windows: []

    // Everything worth showing on the minimap: all windows and the screen
    readonly property var bounds: {
        let x1 = camera.x, y1 = camera.y, x2 = camera.x + view.w, y2 = camera.y + view.h;
        for (const w of windows) {
            x1 = Math.min(x1, w.x);
            y1 = Math.min(y1, w.y);
            x2 = Math.max(x2, w.x + w.w);
            y2 = Math.max(y2, w.y + w.h);
        }
        return { x: x1, y: y1, w: x2 - x1, h: y2 - y1 };
    }

    // Puts canvas point x, y in the middle of the screen
    function lookAt(x, y) {
        Quickshell.execDetached(["hyprctl", "eval", `frame_canvas.look_at(${Math.round(x)}, ${Math.round(y)})`]);
    }

    function pan(dx, dy) {
        Quickshell.execDetached(["hyprctl", "eval", `frame_canvas.pan(${Math.round(dx)}, ${Math.round(dy)})`]);
    }

    // "1.2k" for the position next to the minimap
    function short(n) {
        const a = Math.abs(n);
        return a >= 10000 ? `${Math.round(n / 1000)}k` : a >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${Math.round(n)}`;
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.local/state/frameshell/layout`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.enabled = text().trim() === "canvas"
        onLoadFailed: root.enabled = false
    }

    FileView {
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/frame-canvas.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.camera = data.camera ?? { x: 0, y: 0 };
                root.view = data.view ?? root.view;
                root.windows = data.windows ?? [];
            } catch (e) {
                // Half written; the next change brings a whole one
            }
        }
    }
}
