pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io

// State behind the control center toggles.
Singleton {
    id: root

    property bool wifi: true
    readonly property bool bluetoothAvailable: Bluetooth.defaultAdapter !== null
    readonly property bool bluetooth: Bluetooth.defaultAdapter?.enabled ?? false
    // Read by the notification module (planned): hide popups while true
    property bool silent: false
    // Blocks idle lock and screen-off; the IdleInhibitor lives in the bar
    property bool stayAwake: false
    property bool gameMode: false

    function setWifi(on) {
        wifi = on;
        Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]);
    }

    function setBluetooth(on) {
        if (Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.enabled = on;
    }

    // Animations and blur off, performance power profile; reload brings the config back
    function setGameMode(on) {
        gameMode = on;
        if (on)
            Quickshell.execDetached(["sh", "-c", "hyprctl --batch 'keyword animations:enabled 0 ; keyword decoration:blur:enabled 0'; powerprofilesctl set performance"]);
        else
            Quickshell.execDetached(["sh", "-c", "hyprctl reload; powerprofilesctl set balanced"]);
    }

    Process {
        running: true
        command: ["nmcli", "radio", "wifi"]
        stdout: StdioCollector {
            onStreamFinished: root.wifi = this.text.trim() === "enabled"
        }
    }
}
