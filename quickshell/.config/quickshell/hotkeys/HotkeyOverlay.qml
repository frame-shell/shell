import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.services

// Hotkey overlay on the focused screen. Hyprland opens it after Super was held for
// 1.5 seconds and closes it on release (hypr/frame/hotkeys.lua); also
// `qs ipc call hotkeys toggle`. It takes no keyboard focus, so Super stays with Hyprland.
Scope {
    id: root

    property bool hidden: false
    property bool open: false

    property real shown: open && !hidden ? 1 : 0
    Behavior on shown {
        NumberAnimation { duration: root.open ? Theme.anim.normal : Theme.anim.fast; easing.type: Easing.OutCubic }
    }

    function show() {
        if (hidden || open)
            return;
        window.screen = focusedScreen();
        // Read the binds every time: the config may have changed since the last look
        Binds.refresh();
        open = true;
    }

    function hide() {
        open = false;
    }

    function focusedScreen() {
        const name = Hyprland.focusedMonitor?.name;
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
    }

    onHiddenChanged: if (hidden) open = false

    // Keys that do something together with Super (the lit keys of the map), as Hyprland
    // names them; Super+1 … Super+0 come as one row
    readonly property var superKeys: {
        const out = [];
        for (const r of Binds.rows) {
            if (!r.mods.includes("super") || r.mods.includes("ctrl") || r.mods.includes("alt"))
                continue;
            const keys = r.key === "1…0" ? ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] : [r.key];
            for (const k of keys)
                if (!out.includes(k))
                    out.push(k);
        }
        return out;
    }

    // The same keys light up on an AULA F75 while the overlay is open: a live frame, nothing
    // is saved on the keyboard. Only when the keyboard app is live (Config.keyboardLive);
    // stopping the process sends the stop packet and the board's own effect comes back.
    Process {
        running: root.open && !root.hidden && Keyboard.live && Keyboard.available && root.superKeys.length > 0
        command: [Keyboard.tool, "highlight", "--live", "--hold", "--layout", "de", "--skip-unknown",
            "super_l=secondary"].concat(root.superKeys)
    }

    PanelWindow {
        id: window

        visible: root.shown > 0.01
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-hotkeys"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            opacity: 0.55 * root.shown

            // Opened with toggle (no Super held): a click closes it
            MouseArea {
                anchors.fill: parent
                onClicked: root.hide()
            }
        }

        HotkeyView {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 14 * (1 - root.shown)
            opacity: root.shown
            scale: 0.985 + 0.015 * root.shown
        }
    }

    IpcHandler {
        target: "hotkeys"

        function open(): void {
            root.show();
        }

        function close(): void {
            root.hide();
        }

        function toggle(): void {
            if (root.open)
                root.hide();
            else
                root.show();
        }
    }
}
