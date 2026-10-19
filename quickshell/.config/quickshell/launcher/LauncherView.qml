import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// Launcher UI: query line, result list, info pane and mode tabs.
// The modes themselves (prefixes, rows, what Enter does) live in Modes.qml.
Item {
    id: root

    signal closeRequested()

    // Keeps clicks on the panel itself (the picture preview, empty space) from reaching
    // the click-outside area behind it, which would close the launcher
    MouseArea {
        anchors.fill: parent
        onClicked: input.forceActiveFocus()
    }

    property string query: ""
    property int current: 0
    // Power action waiting for its second Enter
    property string armed: ""

    readonly property var parsed: modes.parse(query)
    readonly property string mode: parsed.mode
    readonly property string rest: parsed.rest
    readonly property var results: modes.compute(mode, rest)
    readonly property var selected: results.length > 0 ? results[Math.min(current, results.length - 1)] : null
    readonly property int maxRows: 9
    // Long lists (emoji, files, clipboard) scroll in windows of maxRows
    readonly property int first: Math.max(0, Math.min(current - maxRows + 1, results.length - maxRows))

    // Tab keeps the text, so a new mode also searches what is already typed
    onModeChanged: {
        modes.modeEntered(mode);
        modes.queryChanged(mode, rest);
    }
    onRestChanged: modes.queryChanged(mode, rest)

    Modes {
        id: modes
    }

    // Opens in a mode, e.g. "; " for the clipboard history (Super+V)
    function preset(text) {
        input.text = text;
        input.cursorPosition = text.length;
    }

    function reset() {
        input.text = "";
        current = 0;
        armed = "";
        input.forceActiveFocus();
    }

    function move(step) {
        const count = results.length;
        if (count > 0)
            current = (current + step + count) % count;
        armed = "";
    }

    function cycleMode(step) {
        const order = modes.order;
        const next = order[(order.indexOf(mode) + step + order.length) % order.length];
        input.text = modes.prefix(next) + rest;
    }

    function setMode(next) {
        input.text = modes.prefix(next) + rest;
        input.forceActiveFocus();
    }

    function activate(shift) {
        if (!selected)
            return;
        const next = modes.activate(selected, shift, armed);
        armed = next.arm ?? "";
        if (next.query !== undefined)
            input.text = next.query;
        if (next.close)
            closeRequested();
    }

    // ── Building blocks ──────────────────────────────────────

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: Theme.size.normal
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
                        text: "search apps · s spotify · d discord · / files · tab for more"
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
                            root.cycleMode(1);
                            break;
                        case Qt.Key_Backtab:
                            root.cycleMode(-1);
                            break;
                        case Qt.Key_Escape:
                            root.closeRequested();
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            root.activate((event.modifiers & Qt.ShiftModifier) !== 0);
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
                        text: modes.names[root.mode] ?? "apps"
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
                        text: "no matches · tab switches the mode"
                        color: Theme.muted
                    }

                    ListView {
                        anchors.fill: parent
                        anchors.topMargin: 14
                        interactive: false
                        model: root.results.slice(root.first, root.first + root.maxRows)

                        delegate: Item {
                            id: row

                            required property var modelData
                            required property int index
                            readonly property int position: root.first + index
                            readonly property bool active: position === root.current
                            readonly property bool passive: modelData.kind === "info"

                            width: ListView.view.width
                            height: 52

                            Rectangle {
                                anchors.fill: parent
                                color: row.active && !row.passive ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16)
                                    : hover.containsMouse && !row.passive ? Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.06)
                                    : "transparent"
                            }

                            Rectangle {
                                width: 3
                                height: parent.height
                                color: Theme.primary
                                visible: row.active && !row.passive
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
                                    opacity: row.active && !row.passive ? 1 : 0
                                }

                                AppIcon {
                                    visible: !row.passive
                                    icon: row.modelData.icon
                                    glyph: row.modelData.glyph
                                    tint: row.modelData.tint
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    Label {
                                        Layout.fillWidth: true
                                        text: row.modelData.markup ?? modes.escapeHtml(row.modelData.title)
                                        textFormat: Text.StyledText
                                        color: row.passive ? Theme.muted : row.active ? Theme.text : Theme.textDim
                                        elide: Text.ElideRight
                                    }

                                    // Info rows say what to type; other rows keep their detail for the info pane
                                    Label {
                                        Layout.fillWidth: true
                                        visible: row.passive && (row.modelData.desc ?? "") !== ""
                                        text: row.modelData.desc ?? ""
                                        color: Theme.frame
                                        font.pixelSize: Theme.size.small
                                        elide: Text.ElideRight
                                    }
                                }

                                Label {
                                    text: row.modelData.category ?? ""
                                    color: Theme.frame
                                    font.pixelSize: Theme.size.small
                                }
                            }

                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: row.passive ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onEntered: root.current = row.position
                                onClicked: mouse => {
                                    root.current = row.position;
                                    root.activate((mouse.modifiers & Qt.ShiftModifier) !== 0);
                                }
                            }
                        }
                    }

                    Label {
                        anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
                        visible: root.results.length > root.maxRows
                        text: `${root.current + 1} / ${root.results.length}`
                        color: Theme.frame
                        font.pixelSize: Theme.size.small
                    }
                }

                Divider { Layout.fillHeight: true }

                // Info pane for the selected result
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 32
                    spacing: 6
                    visible: root.selected !== null && root.selected.kind !== "info"

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
                                maximumLineCount: 3
                                elide: Text.ElideRight
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

                    // Longer text: Claude's answer, a clipboard entry
                    // The first lines of a text file (file search), read when it is selected
                    Process {
                        id: textPeek
                        property string path: root.selected?.textPreview ?? ""
                        property string snippet: ""
                        onPathChanged: {
                            snippet = "";
                            if (path !== "") {
                                command = ["head", "-c", "3000", path];
                                running = true;
                            }
                        }
                        stdout: StdioCollector {
                            onStreamFinished: textPeek.snippet = this.text.split("\n").slice(0, 28).join("\n")
                        }
                    }

                    Rectangle {
                        visible: (root.selected?.textPreview ?? "") !== "" && textPeek.snippet !== ""
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(360, snippetLabel.implicitHeight + 24)
                        Layout.bottomMargin: 18
                        color: Theme.surface
                        border.width: 1
                        border.color: Theme.border
                        clip: true

                        Text {
                            id: snippetLabel
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            text: textPeek.snippet
                            color: Theme.textDim
                            font.family: Theme.font
                            font.pixelSize: 13
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                    }

                    // A thumbnail for a video or PDF (file search), made when it is selected and
                    // kept in $XDG_RUNTIME_DIR/qs-thumbs
                    Process {
                        id: thumbPeek
                        property string source: (root.selected?.thumbSource || root.selected?.pdfSource) ?? ""
                        property bool isPdf: (root.selected?.pdfSource ?? "") !== ""
                        property string file: ""
                        property string ready: ""
                        onSourceChanged: {
                            ready = "";
                            if (source === "")
                                return;
                            file = `${Quickshell.env("XDG_RUNTIME_DIR")}/qs-thumbs/${Qt.md5(source)}.png`;
                            command = ["sh", "-c", isPdf
                                ? 'mkdir -p "$(dirname "$2")" && { [ -s "$2" ] || { pdftoppm -png -r 40 -f 1 -l 1 -singlefile "$1" "${2%.png}"; }; }'
                                : 'mkdir -p "$(dirname "$2")" && { [ -s "$2" ] || ffmpegthumbnailer -i "$1" -o "$2" -s 640 -q 8; }',
                                "thumb", source, file];
                            running = true;
                        }
                        onExited: code => {
                            if (code === 0 && source !== "")
                                ready = file;
                        }
                    }

                    // A picture (clipboard history or a file, or the thumbnail of a video or PDF):
                    // shown large
                    Rectangle {
                        readonly property string shown: (root.selected?.preview ?? "") !== "" ? root.selected.preview : thumbPeek.ready
                        visible: shown !== ""
                        Layout.fillWidth: true
                        // A fixed height, so the pane does not jump while a picture loads
                        Layout.preferredHeight: 300
                        Layout.bottomMargin: 18
                        color: Theme.surface
                        border.width: 1
                        border.color: Theme.border
                        clip: true

                        Image {
                            id: previewImage
                            anchors.fill: parent
                            anchors.margins: 1
                            source: parent.shown !== "" ? `file://${parent.shown}` : ""
                            // Big screenshots are scaled down once on load, not on every paint
                            sourceSize.width: 1200
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 18
                        visible: (root.selected?.body ?? "") !== ""
                        text: root.selected?.body ?? ""
                        color: Theme.text
                        wrapMode: Text.Wrap
                        maximumLineCount: 9
                        elide: Text.ElideRight
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
                spacing: 4

                Repeater {
                    model: modes.order

                    Rectangle {
                        required property string modelData
                        readonly property bool on: root.mode === modelData
                        implicitWidth: tabLabel.implicitWidth + 14
                        implicitHeight: tabLabel.implicitHeight + 4
                        color: "transparent"
                        border.width: 1
                        border.color: on ? Theme.border : "transparent"

                        Label {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: parent.modelData === "" ? "apps" : parent.on ? `${parent.modelData} ${modes.names[parent.modelData]}` : parent.modelData
                            color: parent.on ? Theme.secondary : Theme.muted
                            font.pixelSize: Theme.size.small
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setMode(parent.modelData)
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Label {
                    text: root.armed !== "" ? `press enter again to ${root.armed}`
                        : root.selected?.keys ?? "↑↓ select · enter launch · tab mode · esc close"
                    color: root.armed !== "" ? Theme.warn : Theme.frame
                    font.pixelSize: Theme.size.small
                    elide: Text.ElideLeft
                    Layout.maximumWidth: 420
                }
            }
        }
    }
}
