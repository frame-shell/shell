import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.components
import qs.config
import qs.services

// One lockscreen per monitor: the blurred desktop snapshot, clock and password
// in the center, weather on the right, media bottom left, keyboard status
// bottom right. Everything animates from one `progress` value (0 → 1 on lock,
// back to 0 on unlock), each part starting a little later than the one before.
Item {
    id: root

    required property LockContext context
    required property string snapshot
    // false on the other monitors: only the blurred snapshot, no clock or panels
    property bool showLogin: true

    property bool appeared: false
    property real progress: context.unlocking || !appeared ? 0 : 1
    Behavior on progress {
        NumberAnimation { duration: Theme.anim.slow; easing.type: Easing.OutCubic }
    }

    // Progress of one part that starts at `start` (0..1) of the whole animation
    function stage(start) {
        return Math.max(0, Math.min(1, (progress - start) / (1 - start)));
    }

    Component.onCompleted: {
        appeared = true;
        if (showLogin)
            input.forceActiveFocus();
        else
            hiddenInput.forceActiveFocus();
    }

    // Other monitors have no visible field, but typing there still fills the password
    TextInput {
        id: hiddenInput

        enabled: !root.showLogin && !root.context.unlockInProgress
        width: 1
        height: 1
        opacity: 0
        echoMode: TextInput.Password

        onTextChanged: root.context.currentText = text
        onAccepted: root.context.tryUnlock()
        Keys.onEscapePressed: root.context.currentText = ""

        Connections {
            target: root.context
            function onCurrentTextChanged() {
                if (hiddenInput.text !== root.context.currentText)
                    hiddenInput.text = root.context.currentText;
            }
        }
    }

    // ── Small building blocks ────────────────────────────────

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: Theme.size.normal
    }

    component Icon: Text {
        color: Theme.muted
        font.family: Theme.iconFont
        font.pixelSize: Theme.size.normal
    }

    // Icon and text side by side, e.g. the keyboard layout
    component IconLabel: Row {
        property string icon
        property string text
        property color color: Theme.muted
        spacing: 8
        Icon { text: parent.icon; color: parent.color }
        Label { text: parent.text; color: parent.color }
    }

    // "  humidity ........ 82%"
    component InfoRow: RowLayout {
        property string icon
        property string label
        property string value
        Layout.fillWidth: true
        IconLabel { icon: parent.icon; text: parent.label }
        Item { Layout.fillWidth: true }
        Label { text: parent.value }
    }

    component Section: Label {
        Layout.topMargin: 20
        Layout.bottomMargin: 4
        color: Theme.frame
    }

    component MediaButton: Icon {
        property var action
        font.pixelSize: 22
        color: area.containsMouse ? Theme.text : Theme.secondary
        MouseArea {
            id: area
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.action()
        }
    }

    // ── Background: blurred, darkened, slightly zoomed snapshot ──

    Image {
        id: shot
        anchors.fill: parent
        source: root.snapshot !== "" ? `file://${root.snapshot}` : ""
        cache: false
        fillMode: Image.PreserveAspectCrop
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: shot
        visible: shot.status === Image.Ready
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: 64
        blur: Config.lockBlur * root.progress
        brightness: -root.dim * root.progress
        Behavior on brightness { NumberAnimation { duration: Theme.anim.normal } }
        saturation: 0.15 * root.progress
        scale: 1 + 0.02 * root.progress
    }

    // ── Readability: a bright or busy picture is dimmed more ──

    // The snapshot is read at low resolution once it is there. The blur normally darkens
    // it by 0.45; the brighter the picture (mean luminance) and the busier (contrast),
    // the more it is darkened, up to 0.8, so the text stays readable without boxes.
    property real dim: dimBase
    readonly property real dimBase: 0.45
    readonly property real dimMax: 0.8

    Canvas {
        id: probe

        width: 128
        height: 72
        visible: false
        property string loadedUrl: ""

        function analyse() {
            if (root.snapshot === "")
                return;
            const url = `file://${root.snapshot}`;
            if (loadedUrl !== url) {
                loadedUrl = url;
                loadImage(url);
                return;
            }
            requestPaint();
        }

        onImageLoaded: requestPaint()

        onPaint: {
            if (loadedUrl === "" || !isImageLoaded(loadedUrl))
                return;
            const ctx = getContext("2d");
            ctx.drawImage(loadedUrl, 0, 0, width, height);
            const data = ctx.getImageData(0, 0, width, height).data;
            let sum = 0, sumSq = 0, n = 0;
            for (let i = 0; i < data.length; i += 4) {
                const l = (0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]) / 255;
                sum += l;
                sumSq += l * l;
                n++;
            }
            if (n === 0)
                return;
            const mean = sum / n;
            const dev = Math.sqrt(Math.max(0, sumSq / n - mean * mean));
            // A dark, calm picture (mean 0.2, dev 0.1) keeps the base; brightness above
            // 0.25 and contrast above 0.12 add to it
            const extra = Math.max(0, mean - 0.25) * 1.2 + Math.max(0, dev - 0.12) * 0.8;
            root.dim = Math.min(root.dimMax, root.dimBase + extra);
        }
    }

    Connections {
        target: shot
        function onStatusChanged() {
            if (shot.status === Image.Ready)
                probe.analyse();
        }
    }

    // ── Top right: user@host ─────────────────────────────────

    FileView {
        id: hostname
        path: "/etc/hostname"
        blockLoading: true
    }

    Label {
        id: hostLabel
        visible: root.showLogin
        anchors { top: parent.top; right: parent.right; topMargin: 56; rightMargin: 80 }
        text: `${Quickshell.env("USER")}@${hostname.text().trim()}`
        color: Theme.muted
        font.pixelSize: 18
        opacity: root.stage(0.45)
    }

    // ── Center: clock, date, password ────────────────────────

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    ColumnLayout {
        id: centerColumn
        visible: root.showLogin
        anchors.centerIn: parent
        spacing: 0

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatTime(clock.date, "hh:mm")
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: Theme.size.clock
            font.weight: Font.Light
            font.letterSpacing: -4
            opacity: root.stage(0.15)
            transform: Translate { y: 26 * (1 - root.stage(0.15)) }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 14
            Layout.bottomMargin: 64
            text: clock.date.toLocaleDateString(Qt.locale("en_GB"), "dddd · d MMMM").toLowerCase()
            color: Theme.muted
            font.pixelSize: Theme.size.large
            opacity: root.stage(0.15)
            transform: Translate { y: 26 * (1 - root.stage(0.15)) }
        }

        Frame {
            id: field

            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 560
            Layout.preferredHeight: 78
            label: "unlock"
            padding: 0
            borderColor: root.context.showFailure ? Theme.danger : Theme.primary
            labelColor: borderColor
            opacity: root.stage(0.25)
            transform: [
                Translate { y: 26 * (1 - root.stage(0.25)) },
                Translate { id: shake }
            ]

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 26
                anchors.rightMargin: 26
                spacing: 16

                Text {
                    text: "❯"
                    color: Theme.primary
                    font.family: Theme.font
                    font.pixelSize: 24
                    font.weight: Font.Medium
                }

                TextInput {
                    id: input

                    Layout.fillWidth: true
                    focus: true
                    enabled: !root.context.unlockInProgress
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    color: Theme.secondary
                    font.family: Theme.font
                    font.pixelSize: 24
                    font.letterSpacing: 8
                    cursorDelegate: Rectangle { width: 12; color: Theme.secondary }

                    onTextChanged: root.context.currentText = text
                    onAccepted: root.context.tryUnlock()
                    Keys.onEscapePressed: root.context.currentText = ""

                    // Keeps every monitor's field in sync
                    Connections {
                        target: root.context
                        function onCurrentTextChanged() {
                            if (input.text !== root.context.currentText)
                                input.text = root.context.currentText;
                        }
                    }
                }
            }

            SequentialAnimation {
                id: shakeAnimation
                NumberAnimation { target: shake; property: "x"; to: -12; duration: 50 }
                NumberAnimation { target: shake; property: "x"; to: 12; duration: 70 }
                NumberAnimation { target: shake; property: "x"; to: -8; duration: 70 }
                NumberAnimation { target: shake; property: "x"; to: 6; duration: 60 }
                NumberAnimation { target: shake; property: "x"; to: 0; duration: 50 }
            }

            Connections {
                target: root.context
                function onFailed() { shakeAnimation.restart(); }
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 16
            text: root.context.unlockInProgress ? "checking…"
                : root.context.showFailure ? "wrong password"
                : root.capsLock ? "caps lock is on"
                : "enter to unlock · esc to clear"
            color: root.context.showFailure ? Theme.danger : root.capsLock ? Theme.warn : Theme.muted
            font.pixelSize: 16
            opacity: root.stage(0.25)
        }
    }

    // ── Right: weather ───────────────────────────────────────

    Frame {
        id: weatherFrame
        anchors { right: parent.right; rightMargin: 80; verticalCenter: parent.verticalCenter }
        width: 380
        height: weatherColumn.implicitHeight + padding * 2
        visible: Weather.ready && root.showLogin
        label: "weather"
        padding: 30
        opacity: root.stage(0.35)
        transform: Translate { x: 44 * (1 - root.stage(0.35)) }

        ColumnLayout {
            id: weatherColumn

            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 4

            IconLabel { icon: ""; text: Weather.location }

            RowLayout {
                Layout.topMargin: 18
                spacing: 22

                Icon {
                    text: Weather.icon
                    color: Theme.secondary
                    font.pixelSize: 86
                }

                ColumnLayout {
                    spacing: 0
                    Text {
                        text: `${Weather.temp}°`
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 72
                        font.weight: Font.Light
                    }
                    Label { text: Weather.description }
                }
            }

            Label {
                Layout.bottomMargin: 18
                text: `feels like ${Weather.feelsLike}° · ${Weather.high}° / ${Weather.low}°`
                color: Theme.muted
                font.pixelSize: 16
            }

            InfoRow { icon: ""; label: "humidity"; value: `${Weather.humidity}%` }
            InfoRow { icon: ""; label: "wind"; value: `${Weather.wind} km/h ${Weather.windDir}` }
            InfoRow { icon: ""; label: "sunrise"; value: Weather.sunrise }
            InfoRow { icon: ""; label: "sunset"; value: Weather.sunset }

            Section { text: "── next hours" }
            Repeater {
                model: Weather.hours
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label { text: modelData.time; color: Theme.muted }
                    Item { Layout.fillWidth: true }
                    Icon { text: modelData.icon; color: Theme.secondary }
                    Item { Layout.fillWidth: true }
                    Label { text: `${modelData.temp}°` }
                }
            }

            Section { text: "── next days" }
            Repeater {
                model: Weather.days
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Label { text: modelData.day; color: Theme.muted }
                    Item { Layout.fillWidth: true }
                    Icon { text: modelData.icon; color: Theme.secondary }
                    Item { Layout.fillWidth: true }
                    Label { text: `${modelData.high}°` }
                    Label { text: `${modelData.low}°`; color: Theme.muted }
                }
            }
        }
    }

    // ── Bottom left: now playing ─────────────────────────────

    // Prefer whatever is playing, then Spotify, then any player
    readonly property MprisPlayer player: {
        const list = Mpris.players.values;
        return list.find(p => p.isPlaying) ?? list.find(p => p.identity === "Spotify") ?? list[0] ?? null;
    }
    readonly property real trackProgress: player && player.length > 0 ? Math.min(1, player.position / player.length) : 0

    // MPRIS does not push the position, so ask for it once a second
    Timer {
        running: root.player?.isPlaying ?? false
        interval: 1000
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    Frame {
        id: mediaFrame
        anchors { left: parent.left; bottom: parent.bottom; leftMargin: 80; bottomMargin: 70 }
        width: 440
        height: 110
        visible: root.player !== null && root.showLogin
        label: "now playing"
        padding: 22
        opacity: root.stage(0.45)

        RowLayout {
            anchors.fill: parent
            spacing: 20

            Image {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                source: root.player?.trackArtUrl ?? ""
                sourceSize: Qt.size(128, 128)
                fillMode: Image.PreserveAspectCrop
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    Layout.fillWidth: true
                    text: root.player?.trackTitle ?? ""
                    color: Theme.text
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: root.player?.trackArtist ?? ""
                    color: Theme.muted
                    font.pixelSize: Theme.size.small
                    elide: Text.ElideRight
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    implicitHeight: 3
                    color: Theme.border
                    Rectangle {
                        width: parent.width * root.trackProgress
                        height: parent.height
                        color: Theme.primary
                    }
                }
            }

            Row {
                spacing: 16
                MediaButton { text: ""; action: () => root.player?.previous() }
                MediaButton { text: root.player?.isPlaying ? "" : ""; action: () => root.player?.togglePlaying() }
                MediaButton { text: ""; action: () => root.player?.next() }
            }
        }
    }

    // ── Bottom right: keyboard layout and caps lock ──────────

    property string keymap: ""
    property bool capsLock: false

    function parseDevices(text) {
        try {
            const keyboards = JSON.parse(text).keyboards ?? [];
            const kb = keyboards.find(k => k.main) ?? keyboards[0];
            if (kb) {
                keymap = (kb.active_keymap ?? "").toLowerCase();
                capsLock = !!kb.capsLock;
            }
        } catch (e) {
            console.warn(`lock: hyprctl devices: ${e}`);
        }
    }

    Process {
        id: devices
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: root.parseDevices(this.text)
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: devices.running = true
    }

    Row {
        id: keyRow
        visible: root.showLogin
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 80; bottomMargin: 80 }
        spacing: 28
        opacity: root.stage(0.45)

        IconLabel { icon: ""; text: root.keymap; visible: root.keymap !== "" }
        IconLabel { icon: ""; text: "caps"; color: Theme.warn; visible: root.capsLock }
    }
}
