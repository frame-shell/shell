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
}
