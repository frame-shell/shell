pragma Singleton

import QtQuick
import Quickshell

// Opens a video or a picture in the editor window (editor/EditorWindow.qml): "edit" on a
// recording's or screenshot's notification, the media app (Super+G) and
// `qs ipc call editor open <file>` all come through here.
Singleton {
    id: root

    signal openRequested(string file)

    function isVideo(path) {
        return /\.(mp4|mkv|webm|mov)$/i.test(path);
    }

    function isImage(path) {
        return /\.(png|jpe?g|webp|gif|bmp)$/i.test(path);
    }

    function open(file) {
        if (isVideo(file) || isImage(file))
            openRequested(file);
    }
}
