import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.services

// The recording editor as its own window: "edit" on a recording's notification, or
// `qs ipc call editor open <video>`. The view comes in through a Loader, so without Qt
// Multimedia (qt6-multimedia-ffmpeg) only the editor is missing and it says so.
Scope {
    id: root

    property bool open: false
    property string file: ""

    function openFile(path) {
        if (path === "")
            return;
        file = path;
        open = true;
        if (loader.item)
            loader.item.openFile(path);
    }

    function hide() {
        if (loader.item) {
            loader.item.pause();
            loader.item.project.writeNow();
        }
        open = false;
    }

    Connections {
        target: Recorder

        function onEditRequested(file) {
            root.openFile(file);
        }
    }

    FloatingWindow {
        id: window

        visible: root.open
        title: "frameshell · recording editor"
        implicitWidth: 1480
        implicitHeight: 940
        color: Theme.bg

        // Closed from Hyprland (Super+Q) instead of the close button
        onVisibleChanged: {
            if (!visible && root.open)
                root.hide();
        }

        Loader {
            id: loader

            anchors.fill: parent
            active: root.open
            source: "EditorView.qml"
            onLoaded: {
                item.closeRequested.connect(root.hide);
                item.openFile(root.file);
            }
            onStatusChanged: {
                if (status !== Loader.Error)
                    return;
                root.open = false;
                Notifications.push({
                    app: "recording",
                    glyph: "✗",
                    title: "editor needs Qt Multimedia",
                    body: "sudo pacman -S qt6-multimedia-ffmpeg, then try again"
                });
            }
        }
    }

    IpcHandler {
        target: "editor"

        function open(path: string): void {
            root.openFile(path);
        }

        function close(): void {
            root.hide();
        }
    }
}
