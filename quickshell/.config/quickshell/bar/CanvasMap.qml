import QtQuick
import qs.config
import qs.services

// Minimap of the infinite canvas for the bar, in place of the workspaces: every window
// as a small block (the focused one lit), the screen as an outline. Click to look there,
// scroll to move the view (Shift: sideways). Next to it the screen's position.
Row {
    id: root

    spacing: 8

    readonly property int mapWidth: 120
    readonly property int mapHeight: 18
    readonly property var b: Canvas.bounds
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
            model: Canvas.windows

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
            x: root.offX + (Canvas.camera.x - root.b.x) * root.k
            y: root.offY + (Canvas.camera.y - root.b.y) * root.k
            width: Canvas.view.w * root.k
            height: Canvas.view.h * root.k
            color: "transparent"
            border.width: 1
            border.color: Theme.secondary

            Behavior on x { NumberAnimation { duration: Theme.anim.fast } }
            Behavior on y { NumberAnimation { duration: Theme.anim.fast } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => Canvas.lookAt(root.b.x + (mouse.x - root.offX) / root.k, root.b.y + (mouse.y - root.offY) / root.k)
            onWheel: wheel => {
                const step = wheel.angleDelta.y > 0 ? -160 : 160;
                if (wheel.modifiers & Qt.ShiftModifier)
                    Canvas.pan(step, 0);
                else
                    Canvas.pan(0, step);
            }
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: `${Canvas.short(Canvas.camera.x)}, ${Canvas.short(Canvas.camera.y)} · ${Canvas.windows.length}`
        color: Theme.muted
        font.family: Theme.font
        font.pixelSize: Theme.size.small
    }
}
