import QtQuick
import qs.config
import qs.services

// Minimap of the infinite canvas for the bar, in place of the workspaces: this screen's
// canvas with every window as a small block (the focused one lit) and the screen as an
// outline. Click to look there, scroll to move the view (Shift: sideways). Next to it the
// screen's position.
Row {
    id: root

    // Name of the monitor the bar is on; empty means the focused one
    property string monitor: ""

    spacing: 8

    readonly property int mapWidth: 120
    readonly property int mapHeight: 18
    readonly property var mon: CanvasLayout.monitor(monitor)
    readonly property var view: CanvasLayout.viewOf(mon)
    readonly property var windows: mon ? CanvasLayout.windows.filter(w => w.monitor === mon.name) : []
    // The screen and its windows
    readonly property var b: {
        let x1 = view.x, y1 = view.y, x2 = view.x + view.w, y2 = view.y + view.h;
        for (const w of windows) {
            x1 = Math.min(x1, w.x);
            y1 = Math.min(y1, w.y);
            x2 = Math.max(x2, w.x + w.w);
            y2 = Math.max(y2, w.y + w.h);
        }
        return { x: x1, y: y1, w: x2 - x1, h: y2 - y1 };
    }
    // One scale for both axes, so the shapes stay true
    readonly property real k: Math.min(mapWidth / Math.max(1, b.w), mapHeight / Math.max(1, b.h))
    readonly property real offX: (mapWidth - b.w * k) / 2
    readonly property real offY: (mapHeight - b.h * k) / 2

    Item {
        width: root.mapWidth
        height: root.mapHeight
        anchors.verticalCenter: parent.verticalCenter
        clip: true

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: 1
            border.color: Theme.border
        }

        Repeater {
            model: root.windows

            Rectangle {
                required property var modelData
                x: root.offX + (modelData.x - root.b.x) * root.k
                y: root.offY + (modelData.y - root.b.y) * root.k
                width: Math.max(2, modelData.w * root.k)
                height: Math.max(2, modelData.h * root.k)
                color: modelData.active ? Theme.primary : Theme.muted
                opacity: modelData.active ? 1 : 0.55
            }
        }

        // The screen
        Rectangle {
            x: root.offX + (root.view.x - root.b.x) * root.k
            y: root.offY + (root.view.y - root.b.y) * root.k
            width: root.view.w * root.k
            height: root.view.h * root.k
            color: "transparent"
            border.width: 1
            border.color: Theme.secondary

            Behavior on x { NumberAnimation { duration: Theme.anim.fast } }
            Behavior on y { NumberAnimation { duration: Theme.anim.fast } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => CanvasLayout.lookAt(root.b.x + (mouse.x - root.offX) / root.k, root.b.y + (mouse.y - root.offY) / root.k)
            onWheel: wheel => {
                const step = wheel.angleDelta.y > 0 ? -160 : 160;
                const name = root.mon?.name ?? "";
                if (wheel.modifiers & Qt.ShiftModifier)
                    CanvasLayout.pan(step, 0, name);
                else
                    CanvasLayout.pan(0, step, name);
            }
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: `${CanvasLayout.short(root.mon?.camera.x ?? 0)}, ${CanvasLayout.short(root.mon?.camera.y ?? 0)} · ${root.windows.length}`
        color: Theme.muted
        font.family: Theme.font
        font.pixelSize: Theme.size.small
    }
}
