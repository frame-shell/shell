import QtQuick
import qs.config

// Thin horizontal bar for a 0..1 value; turns warn/danger near the top.
Rectangle {
    id: root

    property real value: 0
    property color fill: value > 0.92 ? Theme.danger : value > 0.8 ? Theme.warn : Theme.primary

    implicitHeight: 8
    color: Theme.border

    Rectangle {
        width: parent.width * Math.max(0, Math.min(1, root.value))
        height: parent.height
        color: root.fill
        Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
    }
}
