pragma Singleton

import Quickshell

// Personal settings. Quickshell reloads by itself when this file is saved.
Singleton {
    // City for the weather panel, e.g. "Berlin". Empty: wttr.in guesses from your IP.
    readonly property string weatherLocation: ""
    // Minutes between weather updates
    readonly property int weatherInterval: 15
    // Blur strength of the desktop snapshot behind the lockscreen, 0 to 1
    readonly property real lockBlur: 1.0

    // goxlr-utility HTTP API (fader levels and mutes)
    readonly property string goxlrApi: "http://localhost:14564"
    // App mixer routes → PipeWire device description, as shown by `wpctl status`.
    // Rename the right side if your GoXLR devices are called differently.
    readonly property var goxlrOutputs: ({
        system: "GoXLR System",
        game: "GoXLR Game",
        chat: "GoXLR Chat",
        music: "GoXLR Music"
    })
    readonly property var goxlrInputs: ({
        "chat mic": "GoXLR Chat Mic",
        sampler: "GoXLR Sampler"
    })
}
