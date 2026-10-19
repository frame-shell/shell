import QtQuick
import qs.config

// Square TUI button: 1px frame that lights up on hover or while `active`.
// Put any content inside; it is centered unless you anchor it yourself.
Rectangle {
    id: root

    property bool active: false
    // false: shown dimmed and ignores clicks (e.g. no Bluetooth adapter)
    property bool available: true
    property color accent: Theme.primary
    readonly property bool hovered: area.containsMouse
    default property alias content: inner.data
    signal clicked()

    color: active ? Qt.rgba(accent.r, accent.g, accent.b, 0.14) : "transparent"
    border.width: 1
    border.color: !available ? Theme.border : active || hovered ? accent : Theme.border
    opacity: available ? 1 : 0.45
    Behavior on border.color { ColorAnimation { duration: Theme.anim.fast } }

    Item {
        id: inner
        anchors.fill: parent
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.available)
                root.clicked();
        }
    }
}
