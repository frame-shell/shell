import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

// Short notice at the bottom center when something changed outside the shell:
//   a GoXLR fader moved or got muted, the GoXLR mic button was pressed,
//   the default output's volume changed (media keys, pactl, an app), the keyboard layout switched.
// Display only: nothing in here changes a volume. Hidden while the lockscreen is up.
Scope {
    id: root

    property bool hidden: false
    property bool open: false

    // What the OSD shows right now
    property string label: ""
    property string icon: ""
    property real level: 0      // 0..1, below 0 = no meter
    property string valueText: ""
    property bool muted: false

    // Values right after start are not news
    property bool armed: false
    property var lastFaders: ({})
    property bool lastMicButton: false
    property string lastSinkKey: ""

    function glyph(code) {
        return String.fromCodePoint(code);
    }

    readonly property var faderIcons: ({
        mic: 0xF036C,     // nf-md-microphone
        chat: 0xF0B79,    // nf-md-chat
        music: 0xF075A,   // nf-md-music
        game: 0xF0297     // nf-md-gamepad_variant
    })

    function show(label, icon, level, valueText, muted) {
        if (!armed || hidden)
            return;
        root.label = label;
        root.icon = icon;
        root.level = level;
        root.valueText = valueText;
        root.muted = muted;
        open = true;
        hideTimer.restart();
    }

    Timer {
        interval: 2500
        running: true
        onTriggered: root.armed = true
    }

    Timer {
        id: hideTimer
        interval: 1600
        onTriggered: root.open = false
    }

    onHiddenChanged: if (hidden) open = false

    // ── GoXLR faders and the mic button ──────────────────────

    function checkFaders() {
        const seen = Object.keys(lastFaders).length > 0;
        const now = {};
        let changed = null;
        for (const f of GoXLR.faders.map(s => GoXLR.fader(s.key))) {
            if (!f)
                continue;
            now[f.key] = f;
            const before = lastFaders[f.key];
            if (!changed && seen && before && (before.level !== f.level || before.muted !== f.muted))
                changed = f;
        }
        lastFaders = now;
        if (changed)
            show(`goxlr · ${changed.label}`,
                glyph(changed.muted ? 0xF0581 : (faderIcons[changed.key] ?? 0xF057E)),
                changed.level / 100, changed.muted ? "muted" : `${changed.level}%`, changed.muted);
    }

    // The System channel has no fader on a Mini; the bar and the control center set it
    property int lastSystem: -1
    function checkSystem() {
        const level = GoXLR.volumes.system;
        if (level === undefined)
            return;
        if (lastSystem >= 0 && level !== lastSystem && !GoXLR.systemOnFader)
            show("goxlr · system", glyph(0xF057E), level / 100, `${level}%`, false);
        lastSystem = level;
    }

    Connections {
        target: GoXLR

        function onVolumesChanged() {
            root.checkSystem();
        }

        // The fader list only changes with the channel assignment; levels and mutes live in GoXLR.live
        function onFadersChanged() {
            root.checkFaders();
        }
        function onLiveChanged() {
            root.checkFaders();
        }

        function onMicButtonMutedChanged() {
            if (GoXLR.micButtonMuted === root.lastMicButton)
                return;
            root.lastMicButton = GoXLR.micButtonMuted;
            root.show("mic", root.glyph(GoXLR.micButtonMuted ? 0xF036D : 0xF036C), -1,
                GoXLR.micButtonMuted ? "muted" : "live", GoXLR.micButtonMuted);
        }
    }

    // ── Default output in PipeWire ───────────────────────────

    readonly property PwNode sink: Pipewire.defaultAudioSink

    PwObjectTracker {
        objects: root.sink ? [root.sink] : []
    }

    // Switching to another output is not a volume change, so remember which one we watch
    onSinkChanged: lastSinkKey = sink ? `${sink.id}` : ""

    function checkSink() {
        const audio = sink?.audio;
        if (!audio || `${sink.id}` !== lastSinkKey)
            return;
        show(`volume · ${(sink.description || sink.name || "output").toLowerCase()}`,
            glyph(audio.muted ? 0xF0581 : 0xF057E), Math.min(1, audio.volume),
            audio.muted ? "muted" : `${Math.round(audio.volume * 100)}%`, audio.muted);
    }

    Connections {
        target: root.sink?.audio ?? null

        function onVolumesChanged() {
            root.checkSink();
        }

        function onMutedChanged() {
            root.checkSink();
        }
    }

    // ── Keyboard layout ──────────────────────────────────────

    Connections {
        target: Hyprland

        // "activelayout>>keyboard-name,German"
        function onRawEvent(event) {
            if (event.name !== "activelayout")
                return;
            const name = event.data.split(",").pop().trim();
            if (name === "" || name === "error")
                return;
            root.show("keyboard layout", root.glyph(0xF030C), -1, name.toLowerCase(), false);
        }
    }

    // ── Window ───────────────────────────────────────────────

    property real shown: open ? 1 : 0
    Behavior on shown {
        NumberAnimation { duration: root.open ? Theme.anim.fast : Theme.anim.normal; easing.type: Easing.OutCubic }
    }

    PanelWindow {
        screen: {
            const name = Hyprland.focusedMonitor?.name;
            return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
        }
        visible: !root.hidden && (root.open || root.shown > 0.01)
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-osd"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Clicks go through to whatever is below
        mask: Region {}
        anchors.bottom: true
        margins.bottom: 64
        implicitWidth: 460
        implicitHeight: 96

        Item {
            width: 440
            height: 66
            anchors.horizontalCenter: parent.horizontalCenter
            y: 16 + 16 * (1 - root.shown)
            opacity: root.shown

            Rectangle {
                anchors.fill: parent
                color: Theme.bg
                opacity: 0.96
            }

            Frame {
                anchors.fill: parent
                label: root.label
                borderColor: root.muted ? Theme.danger : Theme.primary
                labelColor: root.muted ? Theme.danger : Theme.primary
                padding: 0
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 22; rightMargin: 22; topMargin: 6 }
                spacing: 16

                Text {
                    Layout.preferredWidth: 26
                    text: root.icon
                    color: root.muted ? Theme.danger : Theme.secondary
                    font.family: Theme.iconFont
                    font.pixelSize: 22
                }

                Meter {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    visible: root.level >= 0
                    value: Math.max(0, root.level)
                    fill: root.muted ? Theme.frame : Theme.secondary
                }

                // Keeps the value on the right when there is no meter
                Item {
                    Layout.fillWidth: true
                    visible: root.level < 0
                }

                Text {
                    text: root.valueText
                    color: root.muted ? Theme.danger : Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                }
            }
        }
    }
}
