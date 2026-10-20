import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.config
import qs.services

// Screenshots in the shell's own frame: Print freezes every screen, you drag a region or
// click a window (it lights up under the cursor), Enter takes the whole screen, Esc
// cancels. Shift+Print takes the focused screen right away. The picture goes to
// ~/Pictures/screenshots (your XDG pictures folder), lands in the clipboard, and a
// notification shows it with "open", "folder" and "delete". grim does the capture,
// wl-copy the clipboard.
//
// `qs ipc call screenshot region|screen|close`
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

    function show() {
        if (hidden || open)
            return;
        monitorsProc.running = true;
        clientsProc.running = true;
        open = true;
    }

    function close() {
        open = false;
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

    // A rectangle in layout coordinates; the overlays leave first so they are not in the picture
    function captureRect(x, y, w, h) {
        if (w < 2 || h < 2)
            return;
        start(["-g", `${Math.round(x)},${Math.round(y)} ${Math.round(w)}x${Math.round(h)}`]);
    }

    function captureOutput(name) {
        start(["-o", name]);
    }

    function start(args) {
        // One shot at a time: a second one would change the file name under the first
        if (captureDelay.running || grimProc.running)
            return;
        pendingFile = `${folder}/screenshot-${stamp()}.png`;
        pendingArgs = args;
        open = false;
        captureDelay.restart();
    }

    Timer {
        id: captureDelay
        interval: 220
        onTriggered: {
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
                    { id: "folder", label: "folder", style: "" },
                    { id: "delete", label: "delete", style: "" }
                ],
                onAction: id => {
                    if (id === "open")
                        Quickshell.execDetached(["xdg-open", file]);
                    else if (id === "folder")
                        Quickshell.execDetached(["xdg-open", root.folder]);
                    else if (id === "delete")
                        Quickshell.execDetached(["rm", "-f", file]);
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

            // The screen as it was when Print was pressed
            ScreencopyView {
                anchors.fill: parent
                captureSource: overlay.modelData
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
                    x: index === 1 ? overlay.target.x + overlay.target.width : index === 3 ? overlay.target.x : 0
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
                border.color: Theme.primary
                opacity: root.shown

                Rectangle {
                    anchors { left: parent.left; bottom: parent.top; bottomMargin: 6 }
                    width: targetLabel.implicitWidth + 16
                    height: 24
                    color: Theme.bg
                    border.width: 1
                    border.color: Theme.primary
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
                text: "drag · region    click · window    enter · whole screen    esc · cancel"
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
                        root.captureRect(overlay.selX + overlay.offX, overlay.selY + overlay.offY, overlay.selW, overlay.selH);
                    } else if (overlay.hoverWindow) {
                        const w = overlay.hoverWindow;
                        root.captureRect(w.x, w.y, w.w, w.h);
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
                        root.captureRect(overlay.hoverWindow.x, overlay.hoverWindow.y, overlay.hoverWindow.w, overlay.hoverWindow.h);
                    else
                        root.captureOutput(overlay.modelData.name);
                }
            }
        }
    }

    IpcHandler {
        target: "screenshot"

        function region(): void {
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
