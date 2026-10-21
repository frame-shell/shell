import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// The settings app as its own window: Super+, or "settings" in the control center,
// `qs ipc call settings toggle`, `qs ipc call settings section sound`.
Scope {
    id: root

    property bool open: false

    signal wallpapersRequested()
    signal keyboardRequested()

    function show(section) {
        if (section)
            view.section = section;
        open = true;
        view.refresh();
        view.forceActiveFocus();
    }

    function hide() {
        open = false;
    }

    FloatingWindow {
        id: window

        visible: root.open
        title: "frameshell · settings"
        implicitWidth: 1160
        implicitHeight: 800
        color: Theme.bg

        // Closed from Hyprland (Super+Q) instead of the close button
        onVisibleChanged: {
            if (!visible && root.open)
                root.hide();
        }

        SettingsView {
            id: view

            anchors.fill: parent
            onCloseRequested: root.hide()
            onWallpapersRequested: root.wallpapersRequested()
            onKeyboardRequested: root.keyboardRequested()
        }
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            if (root.open)
                root.hide();
            else
                root.show("");
        }

        function open(): void {
            root.show("");
        }

        function section(name: string): void {
            root.show(name);
        }

        function close(): void {
            root.hide();
        }
    }
}
