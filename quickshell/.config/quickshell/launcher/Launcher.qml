import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.config

// App launcher overlay on the focused screen.
// `qs ipc call launcher toggle` (Super+Space), also `open` and `close`.
Scope {
    id: root

    property bool open: false
    // 0 → 1 while opening, back to 0 while closing; the window stays until it is 0
    property real shown: open ? 1 : 0
    Behavior on shown {
        NumberAnimation {
            duration: root.open ? Theme.anim.normal : Theme.anim.fast
            easing.type: Easing.OutCubic
        }
    }

    function show() {
        if (open)
            return;
        window.screen = focusedScreen();
        open = true;
        view.reset();
    }

    function hide() {
        open = false;
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name;
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
    }

    PanelWindow {
        id: window

        visible: root.open || root.shown > 0.01
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-launcher"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // Dims the desktop; a click next to the launcher closes it
        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            opacity: 0.45 * root.shown

            MouseArea {
                anchors.fill: parent
                onClicked: root.hide()
            }
        }

        LauncherView {
            id: view

            width: 1100
            height: 640
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.176 - 18 * (1 - root.shown)
            opacity: root.shown
            scale: 0.985 + 0.015 * root.shown

            onCloseRequested: root.hide()
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            if (root.open)
                root.hide();
            else
                root.show();
        }

        function open(): void {
            root.show();
        }

        function close(): void {
            root.hide();
        }
    }
}
