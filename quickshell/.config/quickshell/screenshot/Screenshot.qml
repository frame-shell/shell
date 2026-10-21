import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

// Screenshots in the shell's own frame: Print freezes every screen (the shot is cut out of
// that frozen picture, so it shows the moment the key was pressed), you drag a region or
// click a window (it lights up under the cursor), Enter takes the whole screen, Esc
// cancels. Shift+Print takes the focused screen right away. The picture goes to
// ~/Pictures/screenshots (your XDG pictures folder), lands in the clipboard, and a
// notification shows it with "open", "folder" and "delete". grim does the capture,
// wl-copy the clipboard.
//
// `qs ipc call screenshot region|screen|record|close` (record: Super+Shift+R, see services/Recorder.qml)
Scope {
    id: root

    property bool hidden: false
    property bool open: false

    property real shown: open && !hidden ? 1 : 0
    Behavior on shown {
        NumberAnimation { duration: Theme.anim.fast; easing.type: Easing.OutCubic }
    }

    // Pictures folder from XDG (xdg-user-dir), ~/Pictures until that answered
    property string picturesDir: `${Quickshell.env("HOME")}/Pictures`
    readonly property string folder: `${picturesDir}/screenshots`

    // Monitors and the windows on their visible workspaces, from hyprctl, taken when the
    // tool opens: [{ name, x, y, w, h, scale }], [{ address, class, title, x, y, w, h, monitor }]
    // in layout coordinates, windows most recently focused first
    property var monitors: []
    property var windows: []

    property string pendingFile: ""
    property var pendingArgs: []
    // The same picker for a screen recording (services/Recorder.qml) instead of a picture
    property bool recordMode: false

    // Freeze first: Print grabs every screen right away (grim -o, one PNG each), the picker
    // shows exactly those pictures and the shot is cut out of them (ffmpeg crop). Menus,
    // tooltips and video frames are taken as they were when the key was pressed. Without
    // ffmpeg, or for a recording, the picker works on the live screen as before.
    readonly property string frozenDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/frame-shot`
    property bool frozen: false
    property bool hasFfmpeg: false

    function frozenFile(name) {
        return `${frozenDir}/${name}.png`;
    }

    function show() {
        if (hidden || open || freezeProc.running || grimProc.running)
            return;
        monitorsProc.running = true;
        clientsProc.running = true;
        frozen = false;
        if (recordMode || !hasFfmpeg) {
            open = true;
            return;
        }
        // The picker opens once the screens are taken, so it is not in them
        freezeProc.command = ["bash", "-c", 'd=$1; shift; mkdir -p "$d" && rm -f "$d"/*.png; for n in "$@"; do grim -o "$n" "$d/$n.png" & done; wait; for n in "$@"; do [ -s "$d/$n.png" ] || exit 1; done', "frame-freeze", frozenDir]
            .concat(Quickshell.screens.map(s => s.name));
        freezeProc.running = true;
    }

    function close() {
        open = false;
        recordMode = false;
        dropFrozen();
    }

    // The frozen screens sit in RAM (XDG_RUNTIME_DIR); gone once the shot is taken or cancelled
    function dropFrozen() {
        Quickshell.execDetached(["sh", "-c", 'rm -f "$1"/*.png', "frame-freeze", frozenDir]);
    }

    Process {
        id: freezeProc
        onExited: code => {
            root.frozen = code === 0;
            if (!root.hidden)
                root.open = true;
        }
    }

    Process {
        command: ["sh", "-c", "command -v ffmpeg"]
        running: true
        onExited: code => root.hasFfmpeg = code === 0
    }

    function monitorNamed(name) {
        return monitors.find(m => m.name === name) ?? null;
    }

    // Windows on that monitor, topmost first
    function windowsOn(name) {
        return windows.filter(w => w.monitor === name);
    }

    function windowAt(name, x, y) {
        return windowsOn(name).find(w => x >= w.x && x < w.x + w.w && y >= w.y && y < w.y + w.h) ?? null;
    }

    function stamp() {
        const d = new Date();
        const p = n => String(n).padStart(2, "0");
        // Milliseconds too: two shots in the same second must not share a file
        return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}-${String(d.getMilliseconds()).padStart(3, "0")}`;
    }

    // A rectangle in layout coordinates on monitor `name`: cut out of the frozen screen, or
    // taken live once the overlays have left (they must not be in the picture)
    function captureRect(x, y, w, h, name) {
        if (w < 2 || h < 2)
            return;
        const mon = monitorNamed(name);
        if (open && frozen && !recordMode && mon) {
            cropFrozen(mon, x, y, w, h);
            return;
        }
        start(["-g", `${Math.round(x)},${Math.round(y)} ${Math.round(w)}x${Math.round(h)}`]);
    }

    function captureOutput(name) {
        // Only the open picker uses the frozen screens; Shift+Print takes the live one
        if (open && frozen && !recordMode) {
            takeFrozen(name, ["cp", "--", frozenFile(name)]);
            return;
        }
        start(["-o", name]);
    }

    // Layout coordinates → the frozen PNG's pixels (it has the monitor's real resolution),
    // clipped to the monitor: a window can reach past its edge
    function cropFrozen(mon, x, y, w, h) {
        const sx = mon.pw / mon.w, sy = mon.ph / mon.h;
        const x0 = Math.max(0, Math.round((x - mon.x) * sx)), y0 = Math.max(0, Math.round((y - mon.y) * sy));
        const x1 = Math.min(mon.pw, Math.round((x - mon.x + w) * sx)), y1 = Math.min(mon.ph, Math.round((y - mon.y + h) * sy));
        if (x1 - x0 < 2 || y1 - y0 < 2)
            return;
        takeFrozen(mon.name, ["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", frozenFile(mon.name),
            "-vf", `crop=${x1 - x0}:${y1 - y0}:${x0}:${y0}`, "-frames:v", "1", "-update", "1"]);
    }

    // cmd gets the new file's path as its last argument; no delay, the overlays are not in it
    function takeFrozen(name, cmd) {
        if (grimProc.running)
            return;
        pendingFile = `${folder}/screenshot-${stamp()}.png`;
        open = false;
        grimProc.command = ["sh", "-c", 'f=$1; shift; mkdir -p "$(dirname "$f")" && "$@" "$f" && wl-copy --type image/png < "$f"', "frame-shot", pendingFile].concat(cmd);
        grimProc.running = true;
    }

    function start(args) {
        // One shot at a time: a second one would change the file name under the first
        if (captureDelay.running || grimProc.running || (recordMode && Recorder.recording))
            return;
        pendingFile = recordMode ? "" : `${folder}/screenshot-${stamp()}.png`;
        pendingArgs = args;
        open = false;
        captureDelay.restart();
    }

    Timer {
        id: captureDelay
        interval: 220
        onTriggered: {
            if (root.recordMode) {
                root.recordMode = false;
                Recorder.start(root.pendingArgs);
                return;
            }
            grimProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && grim "$2" "$3" "$1" && wl-copy --type image/png < "$1"', "frame-shot", root.pendingFile].concat(root.pendingArgs);
            grimProc.running = true;
        }
    }

    Process {
        id: grimProc
        stderr: StdioCollector {
            onStreamFinished: if (this.text.trim() !== "") console.warn(`screenshot: ${this.text.trim()}`)
        }
        onExited: code => {
            root.dropFrozen();
            const file = root.pendingFile;
            const name = file.slice(file.lastIndexOf("/") + 1);
            if (code !== 0) {
                Notifications.push({ app: "screenshot", title: "screenshot failed", body: "grim could not capture (is it installed?)", glyph: "✗" });
                return;
            }
            Notifications.push({
                app: "screenshot",
                title: "screenshot saved",
                body: `${name} · in the clipboard`,
                image: file,
                actions: [
                    { id: "open", label: "open", style: "ok" },
                    { id: "edit", label: "edit", style: "" },
                    { id: "folder", label: "folder", style: "" },
                    { id: "delete", label: "delete", style: "" }
                ],
                onAction: id => {
                    if (id === "open")
                        Quickshell.execDetached(["xdg-open", file]);
                    else if (id === "edit")
                        // Blur a name, put a picture on it, crop (editor/ImageEditorView.qml)
                        Editor.open(file);
                    else if (id === "folder")
                        Quickshell.execDetached(["xdg-open", root.folder]);
                    else if (id === "delete")
                        // With the edit the picture editor kept for it
                        Quickshell.execDetached(["rm", "-f", "--", file, file.replace(/\.[^./]+$/, "") + ".edit.json"]);
                }
            });
        }
    }

    Process {
        id: picturesProc
        command: ["xdg-user-dir", "PICTURES"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const dir = this.text.trim();
                if (dir !== "")
                    root.picturesDir = dir;
            }
        }
    }

    Process {
        id: monitorsProc
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(this.text).map(m => ({
                        name: m.name, x: m.x, y: m.y, w: m.width / (m.scale || 1), h: m.height / (m.scale || 1),
                        // Real pixels, for cutting the frozen picture
                        pw: m.width, ph: m.height,
                        workspaces: [m.activeWorkspace?.id, m.specialWorkspace?.id].filter(id => id !== undefined && id !== 0)
                    }));
                } catch (e) {
                    console.warn(`screenshot: monitors: ${e}`);
                }
            }
        }
    }

    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const list = JSON.parse(this.text)
                        .filter(c => c.mapped && !c.hidden)
                        .sort((a, b) => (a.focusHistoryID ?? 999) - (b.focusHistoryID ?? 999));
                    root.windows = list.map(c => {
                        const mon = root.monitors.find(m => m.workspaces.includes(c.workspace?.id)) ?? null;
                        return { address: c.address, class: c.class, title: c.title, x: c.at[0], y: c.at[1], w: c.size[0], h: c.size[1], monitor: mon?.name ?? "" };
                    }).filter(w => w.monitor !== "");
                } catch (e) {
                    console.warn(`screenshot: clients: ${e}`);
                }
            }
        }
    }

    // Windows are matched to monitors through the monitors list, so read them after it
    Connections {
        target: monitorsProc
        function onExited() {
            clientsProc.running = true;
        }
    }

    onHiddenChanged: if (hidden) open = false

    Variants {
        model: root.open || root.shown > 0.01 ? Quickshell.screens : []

        PanelWindow {
            id: overlay

            required property ShellScreen modelData
            readonly property var mon: root.monitorNamed(modelData.name)
            readonly property real offX: mon?.x ?? 0
            readonly property real offY: mon?.y ?? 0

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-screenshot"
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // The screen as it was when Print was pressed: the frozen picture the shot is cut
            // from, or (recording, no ffmpeg) a still of the screen
            Image {
                anchors.fill: parent
                visible: root.frozen
                source: root.frozen ? "file://" + root.frozenFile(overlay.modelData.name) : ""
                cache: false
                smooth: true
                fillMode: Image.Stretch
            }

            ScreencopyView {
                anchors.fill: parent
                visible: !root.frozen
                captureSource: root.frozen ? null : overlay.modelData
                live: false
                paintCursor: false
            }

            // Selection in this screen's coordinates
            property bool dragging: false
            property real selX: 0
            property real selY: 0
            property real selW: 0
            property real selH: 0
            readonly property var hoverWindow: root.open && !dragging ? root.windowAt(modelData.name, area.mouseX + offX, area.mouseY + offY) : null
            // What a click or Enter would take: the dragged region, else the window under the cursor
            readonly property rect target: dragging && selW > 2 && selH > 2 ? Qt.rect(selX, selY, selW, selH)
                : hoverWindow ? Qt.rect(hoverWindow.x - offX, hoverWindow.y - offY, hoverWindow.w, hoverWindow.h)
                : Qt.rect(0, 0, 0, 0)
            readonly property bool hasTarget: target.width > 0

            // Darken everything but the target (four rectangles around it)
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    color: Theme.bg
                    opacity: 0.55 * root.shown
                    // 0 top (full width), 1 right, 2 bottom (full width), 3 left
                    x: index === 1 ? overlay.target.x + overlay.target.width : 0
                    y: index === 0 ? 0 : index === 2 ? overlay.target.y + overlay.target.height : overlay.target.y
                    width: index === 0 || index === 2 ? overlay.width : index === 1 ? overlay.width - (overlay.target.x + overlay.target.width) : overlay.target.x
                    height: index === 0 ? (overlay.hasTarget ? overlay.target.y : overlay.height) : index === 2 ? overlay.height - (overlay.target.y + overlay.target.height) : overlay.target.height
                    visible: overlay.hasTarget || index === 0
                }
            }

            // The frame around the target
            Rectangle {
                visible: overlay.hasTarget
                x: overlay.target.x
                y: overlay.target.y
                width: overlay.target.width
                height: overlay.target.height
                color: "transparent"
                border.width: 1
                border.color: root.recordMode ? Theme.danger : Theme.primary
                opacity: root.shown

                Rectangle {
                    anchors { left: parent.left; bottom: parent.top; bottomMargin: 6 }
                    width: targetLabel.implicitWidth + 16
                    height: 24
                    color: Theme.bg
                    border.width: 1
                    border.color: root.recordMode ? Theme.danger : Theme.primary
                    Text {
                        id: targetLabel
                        anchors.centerIn: parent
                        text: overlay.dragging ? `${Math.round(overlay.target.width)} × ${Math.round(overlay.target.height)}`
                            : `${overlay.hoverWindow?.class ?? ""} · ${Math.round(overlay.target.width)} × ${Math.round(overlay.target.height)}`
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                }
            }

            // Crosshair lines through the cursor while nothing is selected
            Rectangle {
                visible: root.open && !overlay.dragging
                x: area.mouseX
                y: 0
                width: 1
                height: parent.height
                color: Theme.frame
                opacity: 0.6 * root.shown
            }
            Rectangle {
                visible: root.open && !overlay.dragging
                x: 0
                y: area.mouseY
                width: parent.width
                height: 1
                color: Theme.frame
                opacity: 0.6 * root.shown
            }

            Text {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 28 }
                text: root.recordMode ? "record:  drag · region    click · window    enter · whole screen    esc · cancel"
                    : "drag · region    click · window    enter · whole screen    esc · cancel"
                color: Theme.textDim
                font.family: Theme.font
                font.pixelSize: Theme.size.small
                opacity: root.shown
            }

            MouseArea {
                id: area

                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.CrossCursor

                property real pressX: 0
                property real pressY: 0

                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        root.close();
                        return;
                    }
                    pressX = mouse.x;
                    pressY = mouse.y;
                    overlay.dragging = false;
                }
                onPositionChanged: mouse => {
                    if (!pressed || !(mouse.buttons & Qt.LeftButton))
                        return;
                    if (!overlay.dragging && Math.hypot(mouse.x - pressX, mouse.y - pressY) > 4)
                        overlay.dragging = true;
                    if (overlay.dragging) {
                        overlay.selX = Math.min(pressX, mouse.x);
                        overlay.selY = Math.min(pressY, mouse.y);
                        overlay.selW = Math.abs(mouse.x - pressX);
                        overlay.selH = Math.abs(mouse.y - pressY);
                    }
                }
                onReleased: mouse => {
                    if (mouse.button !== Qt.LeftButton)
                        return;
                    if (overlay.dragging) {
                        overlay.dragging = false;
                        root.captureRect(overlay.selX + overlay.offX, overlay.selY + overlay.offY, overlay.selW, overlay.selH, overlay.modelData.name);
                    } else if (overlay.hoverWindow) {
                        const w = overlay.hoverWindow;
                        root.captureRect(w.x, w.y, w.w, w.h, w.monitor);
                    } else {
                        root.captureOutput(overlay.modelData.name);
                    }
                }
            }

            FocusScope {
                anchors.fill: parent
                focus: root.open
                Keys.onEscapePressed: root.close()
                Keys.onReturnPressed: root.captureOutput(overlay.modelData.name)
                Keys.onEnterPressed: root.captureOutput(overlay.modelData.name)
                Keys.onSpacePressed: {
                    if (overlay.hoverWindow)
                        root.captureRect(overlay.hoverWindow.x, overlay.hoverWindow.y, overlay.hoverWindow.w, overlay.hoverWindow.h, overlay.hoverWindow.monitor);
                    else
                        root.captureOutput(overlay.modelData.name);
                }
            }

            // ── Recording: which sound goes in, at what level ──
            // Only in record mode, bottom left; the choice is kept (services/Recorder.qml)
            Frame {
                visible: root.recordMode && Recorder.channels.length > 0
                anchors { left: parent.left; bottom: parent.bottom; leftMargin: 80; bottomMargin: 80 }
                width: 380
                height: audioColumn.implicitHeight + padding * 2
                label: Recorder.chosen.length > 0 ? `audio · ${Recorder.chosen.map(c => c.label).join(", ")}` : "audio · none"
                labelColor: root.recordMode ? Theme.danger : Theme.primary
                padding: 18
                opacity: root.shown

                ColumnLayout {
                    id: audioColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: 8

                    Repeater {
                        model: Recorder.channels
                        delegate: RowLayout {
                            id: channelRow
                            required property var modelData
                            readonly property var state: Recorder.channelState(modelData.key)
                            Layout.fillWidth: true
                            spacing: 12

                            TuiButton {
                                Layout.preferredWidth: 110
                                Layout.preferredHeight: 28
                                active: channelRow.state.on
                                accent: Theme.danger
                                onClicked: Recorder.setChannel(channelRow.modelData.key, !channelRow.state.on, channelRow.state.level)
                                Text {
                                    anchors.centerIn: parent
                                    text: channelRow.modelData.label
                                    color: channelRow.state.on ? Theme.text : Theme.muted
                                    font.family: Theme.font
                                    font.pixelSize: Theme.size.small
                                }
                            }
                            TuiSlider {
                                Layout.fillWidth: true
                                value: channelRow.state.level
                                dimmed: !channelRow.state.on
                                onMoved: v => Recorder.setChannel(channelRow.modelData.key, channelRow.state.on || v > 0, v)
                            }
                            Text {
                                Layout.preferredWidth: 40
                                horizontalAlignment: Text.AlignRight
                                text: `${Math.round(channelRow.state.level * 100)}%`
                                color: channelRow.state.on ? Theme.textDim : Theme.muted
                                font.family: Theme.font
                                font.pixelSize: Theme.size.small
                            }
                        }
                    }

                    Text {
                        Layout.topMargin: 4
                        text: "click a channel to record it · drag for its level"
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "screenshot"

        function region(): void {
            root.recordMode = false;
            root.show();
        }

        // Pick what to record; while a recording runs, the same call stops it
        function record(): void {
            if (Recorder.recording) {
                Recorder.stop();
                return;
            }
            root.recordMode = true;
            root.show();
        }

        function toggle(): void {
            if (root.open)
                root.close();
            else
                root.show();
        }

        // The focused screen, no questions asked
        function screen(): void {
            const name = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
            if (name !== "")
                root.captureOutput(name);
        }

        function close(): void {
            root.close();
        }
    }
}
