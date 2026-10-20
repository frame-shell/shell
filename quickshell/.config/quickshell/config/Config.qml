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

    // How long a notification stays when the app does not say (ms), and how many show at once
    readonly property int notificationTimeout: 5000
    readonly property int notificationsMax: 3

    // goxlr-utility HTTP API (fader levels and mutes)
    readonly property string goxlrApi: "http://localhost:14564"
    // App mixer routes → PipeWire device description, as shown by `wpctl status`.
    // "GoXLR Music" also matches the Mini's "GoXLRMini Music"; rename the right side
    // if your devices are called differently.
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

    // ── Launcher ─────────────────────────────────────────────

    // Port the Spicetify extension connects to (s mode). Change it here and as PORT in
    // spicetify/.config/spicetify/Extensions/frameshell.js, then run `frame update spicetify`.
    readonly property int spotifyPort: 48931

    // Web search (?): engine without a shortcut, and the shortcuts. %s is the search text.
    readonly property string searchDefault: "ddg"
    readonly property var searchEngines: ({
        g: ["Google", "https://www.google.com/search?q=%s"],
        ddg: ["DuckDuckGo", "https://duckduckgo.com/?q=%s"],
        yt: ["YouTube", "https://www.youtube.com/results?search_query=%s"],
        gh: ["GitHub", "https://github.com/search?q=%s"],
        aw: ["Arch Wiki", "https://wiki.archlinux.org/index.php?search=%s"],
        aur: ["AUR", "https://aur.archlinux.org/packages?K=%s"],
        w: ["Wikipedia", "https://en.wikipedia.org/w/index.php?search=%s"],
        r: ["Reddit", "https://www.reddit.com/search/?q=%s"]
    })

    // Claude (c): there when the claude CLI is installed; false hides it. The model is
    // passed as --model (haiku answers fastest); empty uses your CLI default.
    readonly property bool claudeEnabled: true
    readonly property string claudeModel: "haiku"

    // File search (/): folder to search in; empty is your home folder
    readonly property string fileSearchRoot: ""

    // Timers and alarms (t, a): how long snooze waits, in minutes
    readonly property int snoozeMinutes: 10

    // ── Keyboard (AULA F75, Super+K) ─────────────────────────

    // false: the keyboard app only shows what it would send (frame-keyboard dry run).
    // Set it to true once frame-keyboard works on your board (docs/keyboard.md); the switch
    // in the app changes it until the shell restarts.
    readonly property bool keyboardLive: false
}
