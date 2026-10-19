pragma Singleton

import QtQuick
import Quickshell

// Periwinkle palette, fonts, sizes and timings for every module.
// Values from themes/roxy.json; sizes are pixels at 1080p.
Singleton {
    readonly property color bg: "#0b0c1f"
    readonly property color surface: "#13153a"
    readonly property color surface2: "#1e2256"
    readonly property color shadow: "#3f4bb8"
    readonly property color primary: "#5d6fe8"
    readonly property color secondary: "#93a4f7"
    readonly property color violet: "#a48cf2"
    readonly property color text: "#e1e4ff"
    readonly property color textDim: "#bcc1ea"
    readonly property color muted: "#8086b8"
    readonly property color frame: "#545b96"
    readonly property color border: "#1e2256"
    readonly property color danger: "#ff6b9a"
    readonly property color warn: "#f2c97d"
    readonly property color green: "#6ee0b6"

    readonly property string font: "JetBrains Mono"
    // Nerd Font build of the same face, for icons (weather, media, keyboard)
    readonly property string iconFont: "JetBrainsMono Nerd Font"

    readonly property QtObject size: QtObject {
        readonly property int small: 15
        readonly property int normal: 17
        readonly property int large: 26
        readonly property int clock: 190
    }

    readonly property QtObject anim: QtObject {
        readonly property int fast: 200
        readonly property int normal: 450
        readonly property int slow: 900
    }
}
