import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.services

// Keyboard app on the focused screen: lighting, Fn keys and per-key colors of the AULA F75.
// `qs ipc call keyboard toggle` (Super+K), also `open` and `close`.
Scope {
    id: root

    property bool open: false
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
        Keyboard.refresh();
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
        WlrLayershell.namespace: "qs-keyboard"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // A click outside closes
        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            opacity: 0.3 * root.shown

            MouseArea {
                anchors.fill: parent
                onClicked: root.hide()
            }
        }

        KeyboardView {
            id: view

            width: Math.min(1180, parent.width - 80)
            height: Math.min(880, parent.height - 120)
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - height) / 2 + 10 - 14 * (1 - root.shown)
            opacity: root.shown
            scale: 0.99 + 0.01 * root.shown

            onCloseRequested: root.hide()
        }
    }

    IpcHandler {
        target: "keyboard"

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
