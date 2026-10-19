import QtQuick
import qs.ui

// TUI panel: a 1px border with the label sitting in the top line, like ┌─ label ───┐.
// The top line leaves a gap for the label, so the frame works on any background.
Item {
    id: root

    property string label: ""
    property color borderColor: Theme.border
    property color labelColor: Theme.primary
    property int padding: 24
    default property alias content: body.data

    // Animated copy so all five lines change color together
    property color lineColor: borderColor
    Behavior on lineColor { ColorAnimation { duration: Theme.anim.fast } }

    readonly property real gapStart: label === "" ? width : 14
    readonly property real gapEnd: label === "" ? width : 14 + labelText.implicitWidth + 16

    Rectangle { x: 0; y: 0; width: root.gapStart; height: 1; color: root.lineColor }
    Rectangle { x: root.gapEnd; y: 0; width: Math.max(0, root.width - root.gapEnd); height: 1; color: root.lineColor }
    Rectangle { x: 0; y: 0; width: 1; height: root.height; color: root.lineColor }
    Rectangle { x: root.width - 1; y: 0; width: 1; height: root.height; color: root.lineColor }
    Rectangle { x: 0; y: root.height - 1; width: root.width; height: 1; color: root.lineColor }

    Text {
        id: labelText
        visible: root.label !== ""
        x: 22
        y: -height / 2
        text: root.label
        color: root.labelColor
        font.family: Theme.font
        font.pixelSize: Theme.size.small
        Behavior on color { ColorAnimation { duration: Theme.anim.fast } }
    }

    Item {
        id: body
        anchors.fill: parent
        anchors.margins: root.padding
    }
}
