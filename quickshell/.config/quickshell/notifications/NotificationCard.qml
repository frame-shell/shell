import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// One notification popup in the TUI frame. A bar along the bottom counts down the
// timeout and pauses while hovered; calls pulse green and stay until answered.
Item {
    id: root

    required property var entry

    readonly property bool isCall: entry.kind === "call"
    readonly property bool mini: entry.kind === "mini"
    readonly property color accent: entry.critical ? Theme.danger
        : isCall ? Theme.ok
        : entry.kind === "voice" ? Theme.accent
        : Theme.border
    readonly property color labelColor: entry.critical ? Theme.danger
        : isCall ? Theme.ok
        : entry.kind === "voice" ? Theme.accent
        : Theme.muted

    // 1 → 0 over the timeout
    property real remaining: 1
    property bool leaving: false
    property real appear: 0

    implicitWidth: 460
    implicitHeight: content.implicitHeight + (mini ? 32 : 40)
    opacity: leaving ? 0 : appear
    transform: Translate { x: root.leaving ? 30 : 30 * (1 - root.appear) }

    Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }

    Component.onCompleted: appear = 1
    Behavior on appear { NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutCubic } }

    function close(expired) {
        if (leaving)
            return;
        leaving = true;
        closeLater.expired = expired;
        closeLater.start();
    }

    Timer {
        id: closeLater
        property bool expired: false
        interval: Theme.anim.fast + 40
        onTriggered: Notifications.dismiss(root.entry.uid, expired)
    }

    NumberAnimation on remaining {
        from: 1
        to: 0
        duration: Math.max(1, root.entry.timeout)
        running: root.entry.timeout > 0
        paused: hover.hovered
        onFinished: root.close(true)
    }

    HoverHandler {
        id: hover
    }

    // Calls pulse until accepted or declined
    property color lineColor: accent
    SequentialAnimation on lineColor {
        running: root.isCall
        loops: Animation.Infinite
        ColorAnimation { to: Theme.border; duration: 600; easing.type: Easing.InOutSine }
        ColorAnimation { to: Theme.ok; duration: 600; easing.type: Easing.InOutSine }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: 0.96
    }

    Frame {
        anchors.fill: parent
        label: `${root.entry.app} · ${Notifications.ago(root.entry.time)}`
        borderColor: root.isCall ? root.lineColor : root.accent
        labelColor: root.labelColor
        padding: 0
    }

    RowLayout {
        id: content

        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 14; topMargin: root.mini ? 18 : 22 }
        spacing: 14

        AppIcon {
            Layout.alignment: Qt.AlignTop
            size: root.mini ? 30 : 44
            icon: root.entry.image
            glyph: root.entry.glyph
            tint: root.entry.kind === "voice" ? Theme.accent : root.isCall ? Theme.ok : Theme.primary
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                Layout.rightMargin: root.isCall ? 0 : 30
                text: root.entry.title
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: root.mini ? 15 : 16
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.entry.body
                color: Theme.textDim
                font.family: Theme.font
                font.pixelSize: root.mini ? 13 : 15
                wrapMode: Text.WordWrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Row {
                Layout.topMargin: 10
                visible: root.entry.actions.length > 0
                spacing: 8

                Repeater {
                    model: root.entry.actions

                    TuiButton {
                        required property var modelData
                        readonly property color tone: modelData.style === "ok" ? Theme.ok
                            : modelData.style === "no" ? Theme.danger
                            : Theme.secondary

                        implicitWidth: actionLabel.implicitWidth + 24
                        implicitHeight: 26
                        accent: tone
                        border.color: modelData.style !== "" ? tone : hovered ? Theme.primary : Theme.border
                        onClicked: Notifications.invoke(root.entry.uid, modelData.id)

                        Text {
                            id: actionLabel
                            anchors.centerIn: parent
                            text: parent.modelData.label
                            color: parent.tone
                            font.family: Theme.font
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }

    // Close button; calls have to be answered instead
    TuiButton {
        visible: !root.isCall
        anchors { right: parent.right; top: parent.top; rightMargin: 10; topMargin: 12 }
        implicitWidth: 26
        implicitHeight: 24
        border.color: hovered ? Theme.border : "transparent"
        onClicked: root.close(false)

        Text {
            anchors.centerIn: parent
            text: "×"
            color: parent.hovered ? Theme.text : Theme.muted
            font.family: Theme.font
            font.pixelSize: 15
        }
    }

    // Time left
    Rectangle {
        visible: root.entry.timeout > 0
        anchors { left: parent.left; bottom: parent.bottom }
        width: parent.width * root.remaining
        height: 2
        color: root.entry.critical ? Theme.danger : Theme.primary
    }
}
