import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.config

// Still wallpapers and the plain background, drawn by the shell on the background layer
// (swaybg did this before). frame-wallpaper still owns the state and runs the moving ones,
// mpvpaper and linux-wallpaperengine; a screen showing one of those gets no window from
// here, so the video is never covered.
//
// State: ~/.local/state/frameshell/wallpaper.json
//   { backend: "both" | "mpv" | "image", scaling: "fill" | "fit",
//     screens: { "<monitor>" | "*": { path, kind: "image" | "video" | "scene" | … } } }
Scope {
    id: root

    property var state: ({ backend: "both", scaling: "fill", screens: {} })

    // Workshop items are folders, files have an extension
    function isFolder(path) {
        return !/\.[A-Za-z0-9]{2,5}$/.test(path);
    }

    // What the backend runs itself (mirrors allowed() in frame-wallpaper)
    function moving(entry) {
        const backend = state.backend ?? "both";
        if (entry.kind === "image")
            return false;
        if (backend === "both")
            return entry.kind === "scene" || entry.kind === "video";
        if (backend === "mpv")
            return entry.kind === "video" && !isFolder(entry.path);
        return false;
    }

    // The picture for a screen ("" = just the background color), or null when a backend
    // draws that screen
    function shownOn(name) {
        const screens = state.screens ?? {};
        const entry = screens[name] ?? screens["*"] ?? null;
        if (!entry || !entry.path)
            return "";
        if (moving(entry))
            return null;
        return entry.kind === "image" ? entry.path : "";
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.local/state/frameshell/wallpaper.json`
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.state = Object.assign({ backend: "both", scaling: "fill", screens: {} }, JSON.parse(text()));
            } catch (e) {
                // Half written; the next change brings a whole file
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: backdrop

            required property ShellScreen modelData
            readonly property var picture: root.shownOn(modelData.name)

            visible: picture !== null
            screen: modelData
            color: Theme.bg
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "qs-wallpaper"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            Image {
                anchors.fill: parent
                source: (backdrop.picture ?? "") !== "" ? "file://" + backdrop.picture.split("/").map(encodeURIComponent).join("/") : ""
                fillMode: root.state.scaling === "fit" ? Image.PreserveAspectFit : Image.PreserveAspectCrop
                // Decoded at screen size: an 8K picture would otherwise sit in memory whole
                sourceSize.width: backdrop.width * (backdrop.modelData.devicePixelRatio || 1)
                sourceSize.height: backdrop.height * (backdrop.modelData.devicePixelRatio || 1)
                asynchronous: true
                cache: false
                smooth: true
                // A new picture fades in over the background color
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.anim.normal } }
            }
        }
    }
}
