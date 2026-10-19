import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.services

// Control center under the bar on the right, the app mixer opens beside it.
// `qs ipc call controlcenter toggle` (Super+C) or the button in the bar.
Scope {
    id: root

    signal lockRequested()

    property bool open: false
    property bool mixerOpen: false

    property real shown: open ? 1 : 0
    Behavior on shown {
        NumberAnimation { duration: root.open ? Theme.anim.normal : Theme.anim.fast; easing.type: Easing.OutCubic }
    }
    property real mixerShown: open && mixerOpen ? 1 : 0
    Behavior on mixerShown {
        NumberAnimation { duration: root.mixerOpen ? Theme.anim.normal : Theme.anim.fast; easing.type: Easing.OutCubic }
    }

    function show(screen) {
        if (open)
            return;
        window.screen = screen ?? focusedScreen();
        open = true;
        GoXLR.fast = true;
    }

    function hide() {
        open = false;
        mixerOpen = false;
        GoXLR.fast = false;
    }

    function toggle(screen) {
        if (open)
            hide();
        else
            show(screen);
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name;
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
    }

    // Lock once the panel has faded, so the lockscreen snapshot does not show it
    Timer {
        id: lockLater
        interval: Theme.anim.fast + 80
        onTriggered: root.lockRequested()
    }

    PanelWindow {
        id: window

        visible: root.open || root.shown > 0.01
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-controlcenter"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // A click next to the panels closes them
        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        FocusScope {
            anchors.fill: parent
            focus: root.open
            Keys.onEscapePressed: {
                if (root.mixerOpen)
                    root.mixerOpen = false;
                else
                    root.hide();
            }

            Panel {
                id: panel

                anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: 78 }
                width: 600
                height: implicitHeight
                progress: root.shown
                mixerOpen: root.mixerOpen
                opacity: root.shown
                transform: Translate { y: -14 * (1 - root.shown) }

                onMixerToggled: root.mixerOpen = !root.mixerOpen
                onCloseRequested: root.hide()
                onLockRequested: {
                    root.hide();
                    lockLater.restart();
                }
            }

            Mixer {
                anchors { right: panel.left; top: panel.top; rightMargin: 12 }
                width: 680
                height: implicitHeight
                visible: root.mixerShown > 0.01
                opacity: root.mixerShown
                transform: Translate { x: 18 * (1 - root.mixerShown) }
            }
        }
    }

    IpcHandler {
        target: "controlcenter"

        function toggle(): void {
            root.toggle(null);
        }

        function open(): void {
            root.show(null);
        }

        function close(): void {
            root.hide();
        }
    }
}
