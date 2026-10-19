import QtQuick
import qs.config

// Square slider for a 0..1 value. Emits moved(); the owner decides what to store.
// Drag, click or scroll to change it.
Item {
    id: root

    property real value: 0
    property bool dimmed: false
    signal moved(real value)

    implicitHeight: 18
    opacity: dimmed ? 0.4 : 1

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        color: Theme.border

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            color: Theme.primary
        }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 14
        x: (root.width - width) * Math.max(0, Math.min(1, root.value))
        color: area.pressed || area.containsMouse ? Theme.text : Theme.secondary
    }

    MouseArea {
        id: area

        function emitAt(x) {
            root.moved(Math.max(0, Math.min(1, x / width)));
        }

        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => emitAt(mouse.x)
        onPositionChanged: mouse => {
            if (pressed)
                emitAt(mouse.x);
        }
        onWheel: wheel => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
