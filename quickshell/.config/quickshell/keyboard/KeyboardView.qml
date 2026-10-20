import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// Keyboard app UI: the F75 as a map on top, below it three tabs (lighting, fn keys, colors),
// at the bottom what the last command sent (or, in a dry run, would have sent).
// Keys carry their physical id (US names) and a QWERTZ label.
Item {
    id: root

    signal closeRequested()

    property string tab: "lighting"

    // lighting
    property string effectName: ""
    property int brightness: 4
    property int speed: 2
    // "" = leave as it is, "0".."6" = factory slot, "multi", or "#rrggbb"
    property string effectColor: ""

    // fn keys
    property string selected: ""
    property string action: ""

    // colors: pending changes { id: "#rrggbb" } on top of what the keyboard has
    property var painted: ({})
    property string paintColor: Theme.primary.toString()
    property int keyBrightness: 4

    readonly property int unit: 48
    readonly property int gap: 4

    // [label, physical key id, width in keys]; an empty id is a gap
    readonly property var keyRows: [
        [["esc", "esc", 1], ["", "", 0.5], ["F1", "f1", 1], ["F2", "f2", 1], ["F3", "f3", 1], ["F4", "f4", 1], ["", "", 0.5],
         ["F5", "f5", 1], ["F6", "f6", 1], ["F7", "f7", 1], ["F8", "f8", 1], ["", "", 0.5],
         ["F9", "f9", 1], ["F10", "f10", 1], ["F11", "f11", 1], ["F12", "f12", 1], ["", "", 0.5], ["◉", "knob", 1]],
        [["^", "grave", 1], ["1", "1", 1], ["2", "2", 1], ["3", "3", 1], ["4", "4", 1], ["5", "5", 1], ["6", "6", 1],
         ["7", "7", 1], ["8", "8", 1], ["9", "9", 1], ["0", "0", 1], ["ß", "minus", 1], ["´", "equal", 1],
         ["⌫", "backspace", 2], ["del", "delete", 1]],
        [["tab", "tab", 1.5], ["Q", "q", 1], ["W", "w", 1], ["E", "e", 1], ["R", "r", 1], ["T", "t", 1], ["Z", "y", 1],
         ["U", "u", 1], ["I", "i", 1], ["O", "o", 1], ["P", "p", 1], ["Ü", "bracketleft", 1], ["+", "bracketright", 1],
         ["#", "backslash", 1.5], ["pgup", "prior", 1]],
        [["caps", "caps_lock", 1.75], ["A", "a", 1], ["S", "s", 1], ["D", "d", 1], ["F", "f", 1], ["G", "g", 1], ["H", "h", 1],
         ["J", "j", 1], ["K", "k", 1], ["L", "l", 1], ["Ö", "semicolon", 1], ["Ä", "apostrophe", 1], ["⏎", "return", 2.25],
         ["pgdn", "next", 1]],
        [["shift", "shift_l", 2.25], ["Y", "z", 1], ["X", "x", 1], ["C", "c", 1], ["V", "v", 1], ["B", "b", 1], ["N", "n", 1],
         ["M", "m", 1], [",", "comma", 1], [".", "period", 1], ["-", "slash", 1], ["shift", "shift_r", 1.75], ["↑", "up", 1],
         ["end", "end", 1]],
        [["ctrl", "control_l", 1.25], ["super", "super_l", 1.25], ["alt", "alt_l", 1.25], ["space", "space", 6.25],
         ["fn", "fn", 1.25], ["ctrl", "control_r", 1.25], ["", "", 0.5], ["←", "left", 1], ["↓", "down", 1], ["→", "right", 1]]
    ]
    readonly property var labels: {
        const out = {};
        for (const row of keyRows)
            for (const k of row)
                if (k[1] !== "")
                    out[k[1]] = k[0];
        return out;
    }

    // Factory colors of the color table slots 0–6 (as on the L65)
    readonly property var slotColors: ["#ff0000", "#00ff00", "#0000ff", "#ffff00", "#ff00ff", "#00ffff", "#ffffff"]
    readonly property var roles: ["primary", "secondary", "accent", "text", "danger", "warn", "ok"]
    readonly property var named: ({ red: "#ff0000", green: "#00ff00", blue: "#0000ff", white: "#ffffff", off: "#000000" })

    readonly property var effectSpec: Keyboard.effects.find(e => e.name === effectName) ?? null
    readonly property var keyInfo: selected === "" ? null : Keyboard.info?.keys?.[selected] ?? null

    function reset() {
        selected = "";
        action = "";
        painted = {};
        loadEffect(Keyboard.info?.effect ?? "");
        focusScope.forceActiveFocus();
    }

    function loadEffect(name) {
        effectName = name;
        effectColor = "";
        const saved = Keyboard.info?.effects?.[name];
        if (saved) {
            brightness = saved.brightness;
            speed = saved.speed;
        }
    }

    function roleColor(role) {
        return Theme[role].toString();
    }

    function keyColor(id) {
        return painted[id] ?? Keyboard.info?.colors?.[id] ?? "#000000";
    }

    function clickKey(id) {
        if (tab === "keys") {
            selected = id;
            action = "";
        } else if (tab === "colors") {
            painted = Object.assign({}, painted, { [id]: paintColor });
        }
    }

    function applyLighting() {
        if (effectName === "")
            return;
        Keyboard.effect(effectName, brightness, effectSpec?.speed ? speed : -1, effectSpec?.color ? effectColor : "");
    }

    function applyAction() {
        if (selected === "" || selected === "fn" || action.trim() === "")
            return;
        if (action === "factory")
            Keyboard.resetKeys([selected]);
        else
            Keyboard.assign([`${selected}=${action.trim()}`]);
        action = "";
    }

    function fillAll() {
        const out = {};
        for (const id in labels)
            out[id] = paintColor;
        painted = out;
    }

    // The lighting tab follows the keyboard until an effect is picked
    Connections {
        target: Keyboard

        function onInfoChanged() {
            if (root.effectName === "")
                root.loadEffect(Keyboard.info?.effect ?? "");
        }
    }

    // ── Building blocks ──────────────────────────────────────

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: 14
    }

    component Chip: TuiButton {
        id: chip

        property string text: ""
        property color swatch: "transparent"

        implicitWidth: chipRow.implicitWidth + 20
        implicitHeight: 26

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6

            Rectangle {
                visible: chip.swatch.a > 0
                anchors.verticalCenter: parent.verticalCenter
                width: 10
                height: 10
                color: chip.swatch
                border.width: 1
                border.color: Theme.border
            }

            Text {
                text: chip.text
                color: chip.active ? Theme.text : chip.hovered ? Theme.textDim : Theme.muted
                font.family: Theme.font
                font.pixelSize: 13
            }
        }
    }

    component Action: TuiButton {
        id: act

        property string text: ""

        implicitWidth: actText.implicitWidth + 28
        implicitHeight: 30
        accent: Theme.secondary

        Text {
            id: actText
            anchors.centerIn: parent
            text: act.text
            color: act.available ? Theme.secondary : Theme.muted
            font.family: Theme.font
            font.pixelSize: 14
        }
    }

    // Slider over whole steps 0..max with the value next to it
    component Steps: RowLayout {
        id: steps

        property string title: ""
        property int max: 9
        property int value: 0
        signal picked(int value)

        spacing: 12

        Label {
            text: steps.title
            Layout.preferredWidth: 96
        }

        TuiSlider {
            Layout.fillWidth: true
            value: steps.value / steps.max
            onMoved: v => steps.picked(Math.round(v * steps.max))
        }

        Label {
            text: `${steps.value}/${steps.max}`
            color: Theme.text
            Layout.preferredWidth: 40
            horizontalAlignment: Text.AlignRight
        }
    }

    component HexInput: Rectangle {
        id: hex

        signal picked(string color)

        implicitWidth: 104
        implicitHeight: 26
        color: "transparent"
        border.width: 1
        border.color: hexInput.activeFocus ? Theme.secondary : Theme.border

        TextInput {
            id: hexInput
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 13
            maximumLength: 7
            onAccepted: {
                const t = text.trim().replace(/^#?/, "#");
                if (/^#[0-9a-fA-F]{6}$/.test(t)) {
                    hex.picked(t.toLowerCase());
                    text = "";
                }
            }
            Keys.onEscapePressed: root.closeRequested()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: hexInput.text === ""
                text: "#rrggbb ⏎"
                color: Theme.frame
                font: hexInput.font
            }
        }
    }

    // One key of the map
    component Key: Rectangle {
        id: key

        property var spec: ["", "", 1]
        readonly property string keyId: spec[1]
        readonly property bool isFn: keyId === "fn"
        readonly property bool hasAction: root.tab === "keys" && Keyboard.layer !== "base" && !!Keyboard.info?.keys?.[keyId]
        readonly property bool isSelected: root.tab === "keys" && root.selected === keyId
        readonly property bool isPainted: root.tab === "colors" && root.painted[keyId] !== undefined
        readonly property color paint: root.keyColor(keyId)

        anchors.fill: parent
        visible: keyId !== ""
        color: root.tab === "colors" ? paint : hasAction ? Theme.primary : "transparent"
        border.width: isSelected || isPainted ? 2 : 1
        border.color: isSelected ? Theme.text : isPainted ? Theme.secondary
            : keyHover.hovered ? Theme.secondary : isFn && root.tab === "keys" ? Theme.accent
            : hasAction ? Theme.primary : Theme.border

        Label {
            anchors.centerIn: parent
            text: key.spec[0]
            // Readable on any paint: dark text on light keys
            color: root.tab === "colors" ? (key.paint.hslLightness > 0.55 ? "#000000" : "#ffffff")
                : key.hasAction ? Theme.bg : key.isFn && root.tab === "keys" ? Theme.accent : Theme.muted
            font.pixelSize: key.spec[0].length > 2 ? 11 : 15
            font.weight: key.hasAction ? Font.Medium : Font.Normal
        }

        HoverHandler {
            id: keyHover
            cursorShape: root.tab === "lighting" ? Qt.ArrowCursor : Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: root.clickKey(key.keyId)
        }
    }

    component Divider: Rectangle {
        color: Theme.border
        implicitWidth: 1
        implicitHeight: 1
    }

    // ── Layout ───────────────────────────────────────────────

    // Swallows clicks so they do not reach the dimmed background behind
    MouseArea {
        anchors.fill: parent
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: 0.97
    }

    FocusScope {
        id: focusScope

        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.closeRequested()

        Frame {
            anchors.fill: parent
            label: "keyboard"
            borderColor: Theme.primary
            padding: 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 1
                spacing: 0

                // Device, tabs, dry run or live
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 62
                    Layout.leftMargin: 22
                    Layout.rightMargin: 22
                    spacing: 14

                    Text {
                        text: "❯"
                        color: Theme.primary
                        font.family: Theme.font
                        font.pixelSize: 22
                    }

                    Label {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: Keyboard.connected ? Theme.text : Theme.muted
                        text: !Keyboard.available ? "frame-keyboard is not in ~/.local/bin (docs/keyboard.md)"
                            : Keyboard.connected ? `AULA F75 · usb cable${Keyboard.info?.node ? " · " + Keyboard.info.node : ""}`
                            : Keyboard.dongleOnly ? "only the 2.4 GHz dongle is there · plug the cable in"
                            : "no AULA F75 on the USB cable"
                    }

                    Row {
                        spacing: 6
                        Repeater {
                            model: [["lighting", "lighting"], ["keys", "fn keys"], ["colors", "colors"]]
                            Chip {
                                required property var modelData
                                text: modelData[1]
                                active: root.tab === modelData[0]
                                onClicked: {
                                    root.tab = modelData[0];
                                    root.selected = "";
                                }
                            }
                        }
                    }

                    // Off: frame-keyboard only prints what it would send
                    Chip {
                        text: Keyboard.live ? "live · sends to the keyboard" : "dry run"
                        active: Keyboard.live
                        accent: Keyboard.live ? Theme.danger : Theme.primary
                        onClicked: Keyboard.setLive(!Keyboard.live)
                    }
                }

                // Why nothing happens on the board
                Label {
                    Layout.leftMargin: 22
                    Layout.rightMargin: 22
                    Layout.fillWidth: true
                    visible: text !== ""
                    wrapMode: Text.Wrap
                    font.pixelSize: 13
                    color: Keyboard.error !== "" ? Theme.danger : Theme.warn
                    text: Keyboard.error !== "" ? Keyboard.error
                        : Keyboard.info?.dry ? "dry run: placeholder data, nothing is sent · the log at the bottom shows the packets"
                        : ""
                }

                Divider { Layout.fillWidth: true; Layout.topMargin: 8 }

                // The board
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: board.implicitHeight + 32

                    Column {
                        id: board
                        anchors.centerIn: parent
                        spacing: root.gap

                        Repeater {
                            model: root.keyRows
                            Row {
                                id: keyRow
                                required property var modelData
                                spacing: root.gap
                                Repeater {
                                    model: keyRow.modelData
                                    // Gaps stay in the row as empty space; Row skips invisible items
                                    Item {
                                        id: slot
                                        required property var modelData
                                        width: modelData[2] * root.unit - root.gap
                                        height: root.unit - root.gap
                                        Key {
                                            spec: slot.modelData
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Divider { Layout.fillWidth: true }

                // Tab content
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 22

                    // ── lighting ──
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.tab === "lighting"
                        spacing: 14

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: Keyboard.effects
                                Chip {
                                    required property var modelData
                                    text: modelData.name
                                    active: root.effectName === modelData.name
                                    onClicked: root.loadEffect(modelData.name)
                                }
                            }
                        }

                        Steps {
                            Layout.fillWidth: true
                            title: "brightness"
                            max: 9
                            value: root.brightness
                            onPicked: v => root.brightness = v
                        }

                        Steps {
                            Layout.fillWidth: true
                            visible: root.effectSpec?.speed ?? false
                            title: "speed"
                            max: 4
                            value: root.speed
                            onPicked: v => root.speed = v
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.effectSpec?.color ?? false
                            spacing: 12

                            Label {
                                text: "color"
                                Layout.preferredWidth: 96
                                Layout.alignment: Qt.AlignTop
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: root.slotColors
                                    Chip {
                                        required property string modelData
                                        required property int index
                                        text: String(index)
                                        swatch: modelData
                                        active: root.effectColor === String(index)
                                        onClicked: root.effectColor = String(index)
                                    }
                                }

                                Chip {
                                    text: "multi"
                                    active: root.effectColor === "multi"
                                    onClicked: root.effectColor = "multi"
                                }

                                Repeater {
                                    model: ["primary", "secondary", "accent"]
                                    Chip {
                                        required property string modelData
                                        text: modelData
                                        swatch: root.roleColor(modelData)
                                        active: root.effectColor === root.roleColor(modelData)
                                        onClicked: root.effectColor = root.roleColor(modelData)
                                    }
                                }

                                HexInput {
                                    onPicked: c => root.effectColor = c
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                Layout.fillWidth: true
                                font.pixelSize: 13
                                color: Theme.muted
                                text: root.effectColor.startsWith("#")
                                    ? `own color ${root.effectColor} goes into slot 0 of ${root.effectName}`
                                    : `on the keyboard now: ${Keyboard.info?.effect ?? "?"}`
                            }

                            Action {
                                text: "apply ›"
                                available: root.effectName !== "" && !Keyboard.busy
                                onClicked: root.applyLighting()
                            }
                        }
                    }

                    // ── fn keys ──
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.tab === "keys"
                        spacing: 14

                        RowLayout {
                            spacing: 6

                            Label {
                                text: "layer"
                                Layout.preferredWidth: 96
                            }

                            Repeater {
                                model: [["fn1", "with fn"], ["fn2", "fn 2"], ["base", "without fn"]]
                                Chip {
                                    required property var modelData
                                    text: modelData[1]
                                    active: Keyboard.layer === modelData[0]
                                    onClicked: {
                                        root.selected = "";
                                        Keyboard.setLayer(modelData[0]);
                                    }
                                }
                            }
                        }

                        Label {
                            Layout.fillWidth: true
                            color: Theme.text
                            text: root.selected === "" ? "click a key on the map"
                                : root.selected === "fn" ? "fn stays fn (otherwise there is no way back to this layer)"
                                : `${root.labels[root.selected]}: ${root.keyInfo ? root.keyInfo.text + "  ·  " + root.keyInfo.bytes : "nothing"}`
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.selected !== "" && root.selected !== "fn"
                            spacing: 10

                            Label {
                                text: "does"
                                Layout.preferredWidth: 96
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 30
                                color: "transparent"
                                border.width: 1
                                border.color: actionInput.activeFocus ? Theme.secondary : Theme.border

                                TextInput {
                                    id: actionInput
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    text: root.action
                                    onTextEdited: root.action = text
                                    onAccepted: root.applyAction()
                                    Keys.onEscapePressed: root.closeRequested()

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: actionInput.text === ""
                                        text: "a key or combo: f5, ctrl+alt+t, super+z … or pick one below"
                                        color: Theme.frame
                                        font: actionInput.font
                                    }
                                }
                            }

                            Action {
                                text: "assign ›"
                                available: root.action.trim() !== "" && !Keyboard.busy
                                onClicked: root.applyAction()
                            }
                        }

                        Flow {
                            Layout.fillWidth: true
                            visible: root.selected !== "" && root.selected !== "fn"
                            spacing: 6

                            Repeater {
                                model: Keyboard.actions.media.concat(Keyboard.actions.lighting).concat(
                                    Keyboard.layer === "fn1" ? ["none", "factory"] : ["none"])
                                Chip {
                                    required property string modelData
                                    text: modelData
                                    active: root.action === modelData
                                    onClicked: root.action = modelData
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font.pixelSize: 13
                            color: Theme.muted
                            text: Keyboard.layer === "base"
                                ? "without fn: this changes what the key does normally"
                                : "lit keys do something together with fn · factory puts the AULA default back"
                        }
                    }

                    // ── colors ──
                    ColumnLayout {
                        anchors.fill: parent
                        visible: root.tab === "colors"
                        spacing: 14

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Label {
                                text: "paint"
                                Layout.preferredWidth: 96
                                Layout.alignment: Qt.AlignTop
                            }

                            Flow {
                                Layout.fillWidth: true
                                spacing: 6

                                Repeater {
                                    model: root.roles
                                    Chip {
                                        required property string modelData
                                        text: modelData
                                        swatch: root.roleColor(modelData)
                                        active: root.paintColor === root.roleColor(modelData)
                                        onClicked: root.paintColor = root.roleColor(modelData)
                                    }
                                }

                                Repeater {
                                    model: Object.keys(root.named)
                                    Chip {
                                        required property string modelData
                                        text: modelData
                                        swatch: root.named[modelData]
                                        active: root.paintColor === root.named[modelData]
                                        onClicked: root.paintColor = root.named[modelData]
                                    }
                                }

                                HexInput {
                                    onPicked: c => root.paintColor = c
                                }
                            }
                        }

                        RowLayout {
                            spacing: 6

                            Label {
                                text: "keys"
                                Layout.preferredWidth: 96
                            }

                            Chip {
                                text: "fill all"
                                swatch: root.paintColor
                                onClicked: root.fillAll()
                            }

                            Chip {
                                text: "undo changes"
                                onClicked: root.painted = {}
                            }

                            Label {
                                text: "   from the theme"
                                color: Theme.muted
                            }

                            Repeater {
                                model: ["solid", "split", "rows"]
                                Chip {
                                    required property string modelData
                                    text: modelData
                                    onClicked: {
                                        root.painted = {};
                                        Keyboard.style(modelData, root.keyBrightness);
                                    }
                                }
                            }
                        }

                        Steps {
                            Layout.fillWidth: true
                            title: "brightness"
                            max: 9
                            value: root.keyBrightness
                            onPicked: v => root.keyBrightness = v
                        }

                        Item { Layout.fillHeight: true }

                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.Wrap
                                font.pixelSize: 13
                                color: Theme.muted
                                text: `click keys to paint them · ${Object.keys(root.painted).length} changed · `
                                    + "the colors are saved on the keyboard, so write them when you are done"
                            }

                            Action {
                                text: "write colors ›"
                                available: Object.keys(root.painted).length > 0 && !Keyboard.busy
                                onClicked: {
                                    Keyboard.paint(root.painted, root.keyBrightness);
                                    root.painted = {};
                                }
                            }
                        }
                    }
                }

                Divider { Layout.fillWidth: true }

                // What the last command sent (dry run: would have sent)
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 130

                    Label {
                        id: logTitle
                        anchors { left: parent.left; top: parent.top; leftMargin: 22; topMargin: 10 }
                        text: Keyboard.busy ? "working …" : Keyboard.live ? "last command" : "last command · dry run"
                        font.pixelSize: 12
                        color: Theme.muted
                    }

                    Flickable {
                        id: logView
                        anchors { left: parent.left; right: parent.right; top: logTitle.bottom; bottom: parent.bottom
                                  leftMargin: 22; rightMargin: 22; topMargin: 6; bottomMargin: 10 }
                        clip: true
                        contentHeight: logText.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        Text {
                            id: logText
                            width: logView.width
                            text: Keyboard.log === "" ? "nothing yet" : Keyboard.log
                            color: Theme.textDim
                            font.family: Theme.font
                            font.pixelSize: 11
                            wrapMode: Text.WrapAnywhere
                        }
                    }
                }
            }
        }
    }
}
