import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// Launcher UI: query line, result list, info pane and mode tabs.
// Modes by prefix: none = apps, "=" calculator, ">" run in Ghostty, ":" power.
Item {
    id: root

    signal closeRequested()

    property string query: ""
    property int current: 0
    // Power action waiting for its second Enter
    property string armed: ""

    readonly property string mode: ["=", ">", ":"].includes(query.charAt(0)) ? query.charAt(0) : ""
    readonly property string rest: query.slice(mode === "" ? 0 : 1).trim()
    readonly property var results: compute(mode, rest, Apps.entries, Apps.usage)
    readonly property var selected: results.length > 0 ? results[Math.min(current, results.length - 1)] : null
    readonly property int maxRows: 9

    readonly property var powerActions: [
        { name: "lock", desc: "Lock the screen", glyph: "L", tint: Theme.primary,
          // Short delay so the snapshot does not catch the closing launcher
          command: ["sh", "-c", "sleep 0.3; qs ipc call lock lock"] },
        { name: "logout", desc: "End the Hyprland session", glyph: "O", tint: Theme.frame, command: ["hyprctl", "dispatch", "exit"] },
        { name: "suspend", desc: "Sleep, locks first", glyph: "S", tint: Theme.violet, command: ["systemctl", "suspend"] },
        { name: "reboot", desc: "Restart the computer", glyph: "R", tint: Theme.warn, command: ["systemctl", "reboot"] },
        { name: "shutdown", desc: "Power off", glyph: "P", tint: Theme.danger, command: ["systemctl", "poweroff"] }
    ]

    function reset() {
        input.text = "";
        current = 0;
        armed = "";
        input.forceActiveFocus();
    }

    function escapeHtml(text) {
        return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    // Name with the matched letters highlighted (StyledText)
    function markup(text, idx) {
        let out = "";
        for (let i = 0; i < text.length; i++) {
            const c = escapeHtml(text[i]);
            out += idx.includes(i) ? `<font color="${Theme.secondary}"><b>${c}</b></font>` : c;
        }
        return out;
    }

    function calculate(expr) {
        const plain = expr.replace(/,/g, ".");
        if (plain === "" || !/^[\d\s+\-*\/().%^]+$/.test(plain))
            return null;
        try {
            const value = Function(`"use strict"; return (${plain.replace(/\^/g, "**")});`)();
            return typeof value === "number" && isFinite(value) ? Math.round(value * 1e10) / 1e10 : null;
        } catch (e) {
            return null;
        }
    }

    // Every result has: kind, title, markup, desc, category, glyph, tint, icon, rows
    function compute(mode, rest, entries, usage) {
        if (mode === "=") {
            const value = calculate(rest);
            return [{
                kind: "calc", value,
                title: rest === "" ? "type a calculation" : value === null ? "not a calculation" : `${rest} = ${value}`,
                category: "calc", glyph: "=", tint: Theme.primary, icon: "",
                rows: [["input", rest || "–"], ["enter", "copies the result"]]
            }];
        }
        if (mode === ">") {
            return [{
                kind: "run", command: rest,
                title: rest === "" ? "type a command" : rest,
                desc: "opens in Ghostty and stays open",
                category: "run", glyph: ">", tint: Theme.frame, icon: "",
                rows: [["command", rest || "–"], ["shell", "fish"]]
            }];
        }
        if (mode === ":") {
            return powerActions
                .map(p => ({ action: p, match: rest === "" ? { score: 0, idx: [] } : Apps.fuzzy(p.name, rest) }))
                .filter(x => x.match)
                .sort((a, b) => b.match.score - a.match.score)
                .map(({ action, match }) => ({
                    kind: "power", name: action.name, command: action.command,
                    title: action.name, markup: markup(action.name, match.idx),
                    desc: action.desc, category: "power", glyph: action.glyph, tint: action.tint, icon: "",
                    rows: [["runs", action.command.join(" ")], ["confirm", action.name === "lock" ? "no" : "press enter twice"]]
                }));
        }
        const tints = [Theme.primary, Theme.violet, Theme.secondary, Theme.shadow, Theme.green];
        return Apps.search(rest).map(({ entry, idx }) => ({
            kind: "app", entry,
            title: entry.name, markup: markup(entry.name, idx),
            desc: entry.comment || entry.genericName || "",
            category: Apps.categoryOf(entry),
            glyph: entry.name.charAt(0).toUpperCase(),
            tint: tints[entry.name.length % tints.length],
            icon: entry.icon,
            rows: [["category", Apps.categoryOf(entry)], ["runs", entry.execString], ["used", `${Apps.uses(entry)} times`]]
        }));
    }

    function move(step) {
        const count = Math.min(results.length, maxRows);
        if (count > 0)
            current = (current + step + count) % count;
        armed = "";
    }

    function cycleMode() {
        const order = ["", "=", ">", ":"];
        input.text = order[(order.indexOf(mode) + 1) % order.length] + query.slice(mode === "" ? 0 : 1);
    }

    function setMode(prefix) {
        input.text = prefix + query.slice(mode === "" ? 0 : 1);
        input.forceActiveFocus();
    }

    function activate() {
        const r = selected;
        if (!r)
            return;
        switch (r.kind) {
        case "app":
            Apps.launch(r.entry);
            closeRequested();
            break;
        case "calc":
            if (r.value !== null) {
                Quickshell.execDetached(["wl-copy", String(r.value)]);
                closeRequested();
            }
            break;
        case "run":
            if (r.command !== "") {
                Quickshell.execDetached(["ghostty", "-e", "fish", "-c", `${r.command}; exec fish`]);
                closeRequested();
            }
            break;
        case "power":
            if (r.name !== "lock" && armed !== r.name) {
                armed = r.name;
                return;
            }
            Quickshell.execDetached(r.command);
            closeRequested();
            break;
        }
    }

    // ── Building blocks ──────────────────────────────────────

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: Theme.size.normal
    }

    // App icon from the icon theme, or a letter tile when there is none
    component AppIcon: Item {
        property string icon
        property string glyph
        property color tint: Theme.primary
        property int size: 40
        implicitWidth: size
        implicitHeight: size

        Image {
            id: image
            anchors.fill: parent
            source: parent.icon !== "" ? Quickshell.iconPath(parent.icon, true) : ""
            sourceSize: Qt.size(parent.size * 2, parent.size * 2)
            fillMode: Image.PreserveAspectFit
            visible: status === Image.Ready
        }

        Rectangle {
            anchors.fill: parent
            visible: image.status !== Image.Ready
            color: parent.tint
            Text {
                anchors.centerIn: parent
                text: parent.parent.glyph
                color: Theme.bg
                font.family: Theme.font
                font.pixelSize: parent.parent.size * 0.45
                font.weight: Font.Medium
            }
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
        opacity: 0.94
    }

    Frame {
        anchors.fill: parent
        label: "run"
        borderColor: Theme.primary
        padding: 0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // Query line
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 84
                Layout.leftMargin: 30
                Layout.rightMargin: 30
                spacing: 18

                Text {
                    text: "❯"
                    color: Theme.primary
                    font.family: Theme.font
                    font.pixelSize: 26
                    font.weight: Font.Medium
                }

                TextInput {
                    id: input

                    Layout.fillWidth: true
                    focus: true
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 26
                    cursorDelegate: Rectangle { width: 3; color: Theme.secondary }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text === ""
                        text: "search apps · = calc · > run · : power"
                        color: Theme.frame
                        font.pixelSize: 26
                    }

                    onTextChanged: {
                        root.query = text;
                        root.current = 0;
                        root.armed = "";
                    }

                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Down:
                            root.move(1);
                            break;
                        case Qt.Key_Up:
                            root.move(-1);
                            break;
                        case Qt.Key_Tab:
                            root.cycleMode();
                            break;
                        case Qt.Key_Escape:
                            root.closeRequested();
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.activate();
                            break;
                        default:
                            return;
                        }
                        event.accepted = true;
                    }
                }

                Rectangle {
                    implicitWidth: modeLabel.implicitWidth + 24
                    implicitHeight: modeLabel.implicitHeight + 6
                    color: "transparent"
                    border.color: Theme.border
                    border.width: 1
                    Label {
                        id: modeLabel
                        anchors.centerIn: parent
                        text: ({ "": "apps", "=": "calc", ">": "run", ":": "power" })[root.mode]
                        color: Theme.secondary
                        font.pixelSize: Theme.size.small
                    }
                }
            }

            Divider { Layout.fillWidth: true }

            // Results and info pane
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Item {
                    Layout.preferredWidth: 640
                    Layout.fillHeight: true

                    Label {
                        anchors { left: parent.left; top: parent.top; margins: 24 }
                        visible: root.results.length === 0
                        text: "no matches · try = for calc or > to run a command"
                        color: Theme.muted
                    }

                    ListView {
                        anchors.fill: parent
                        anchors.topMargin: 14
                        interactive: false
                        model: root.results.slice(0, root.maxRows)

                        delegate: Item {
                            id: row

                            required property var modelData
                            required property int index
                            readonly property bool active: index === root.current

                            width: ListView.view.width
                            height: 52

                            Rectangle {
                                anchors.fill: parent
                                color: row.active ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16)
                                    : hover.containsMouse ? Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.06)
                                    : "transparent"
                            }

                            Rectangle {
                                width: 3
                                height: parent.height
                                color: Theme.primary
                                visible: row.active
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 18
                                anchors.rightMargin: 22
                                spacing: 16

                                Text {
                                    Layout.preferredWidth: 20
                                    text: "❯"
                                    color: Theme.primary
                                    font.family: Theme.font
                                    font.pixelSize: Theme.size.normal
                                    opacity: row.active ? 1 : 0
                                }

                                AppIcon {
                                    icon: row.modelData.icon
                                    glyph: row.modelData.glyph
                                    tint: row.modelData.tint
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: row.modelData.markup ?? root.escapeHtml(row.modelData.title)
                                    textFormat: Text.StyledText
                                    color: row.active ? Theme.text : Theme.textDim
                                    elide: Text.ElideRight
                                }

                                Label {
                                    text: row.modelData.category
                                    color: Theme.frame
                                    font.pixelSize: Theme.size.small
                                }
                            }

                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.current = row.index
                                onClicked: {
                                    root.current = row.index;
                                    root.activate();
                                }
                            }
                        }
                    }
                }

                Divider { Layout.fillHeight: true }

                // Info pane for the selected result
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 32
                    spacing: 6
                    visible: root.selected !== null

                    RowLayout {
                        visible: root.selected?.kind !== "calc"
                        Layout.bottomMargin: 18
                        spacing: 22

                        AppIcon {
                            size: 76
                            icon: root.selected?.icon ?? ""
                            glyph: root.selected?.glyph ?? ""
                            tint: root.selected?.tint ?? Theme.primary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label {
                                Layout.fillWidth: true
                                text: root.selected?.kind === "run" ? "run command" : root.selected?.title ?? ""
                                color: Theme.text
                                font.pixelSize: 28
                                font.weight: Font.Medium
                                wrapMode: Text.WordWrap
                            }
                            Label {
                                Layout.fillWidth: true
                                text: root.selected?.desc ?? ""
                                color: Theme.muted
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    Label {
                        visible: root.selected?.kind === "calc"
                        text: "── result"
                        color: Theme.muted
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 22
                        visible: root.selected?.kind === "calc"
                        text: root.selected?.value ?? "…"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 64
                        font.weight: Font.Light
                        wrapMode: Text.WrapAnywhere
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 16
                        rowSpacing: 6

                        Repeater {
                            model: (root.selected?.rows ?? []).reduce((all, row) => all.concat(row), [])

                            Label {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: index % 2 === 1
                                Layout.preferredWidth: index % 2 === 0 ? 110 : -1
                                text: modelData
                                color: index % 2 === 0 ? Theme.frame : Theme.secondary
                                wrapMode: Text.WrapAnywhere
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            Divider { Layout.fillWidth: true }

            // Mode tabs and key hints
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                Layout.leftMargin: 26
                Layout.rightMargin: 26
                spacing: 8

                Repeater {
                    model: [["", "apps"], ["=", "= calc"], [">", "> run"], [":", ": power"]]

                    Rectangle {
                        required property var modelData
                        readonly property bool on: root.mode === modelData[0]
                        implicitWidth: tabLabel.implicitWidth + 20
                        implicitHeight: tabLabel.implicitHeight + 4
                        color: "transparent"
                        border.width: 1
                        border.color: on ? Theme.border : "transparent"

                        Label {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: parent.modelData[1]
                            color: parent.on ? Theme.secondary : Theme.muted
                            font.pixelSize: Theme.size.small
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setMode(parent.modelData[0])
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: root.armed !== "" ? `press enter again to ${root.armed}` : "↑↓ select · enter launch · tab mode · esc close"
                    color: root.armed !== "" ? Theme.warn : Theme.frame
                    font.pixelSize: Theme.size.small
                }
            }
        }
    }
}
