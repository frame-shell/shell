import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// Task manager beside the control center: every running app with CPU and memory, a close
// button that asks the app to quit and a kill button for the ones that hang (second click
// kills the whole process tree). Numbers come from services/Tasks.qml every two seconds.
Item {
    id: root

    // The app whose kill waits for a second click
    property string armed: ""

    implicitHeight: column.implicitHeight + 46

    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.armed = ""
    }

    function kill(app) {
        if (armed !== app.key) {
            armed = app.key;
            disarm.restart();
            return;
        }
        armed = "";
        Tasks.kill(app);
    }

    // ── Building blocks ──────────────────────────────────────

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: 16
    }

    component Icon: Text {
        color: Theme.secondary
        font.family: Theme.iconFont
        font.pixelSize: 15
    }

    component TaskRow: Item {
        id: row

        required property var app
        property bool last: false
        readonly property bool isArmed: root.armed === app.key
        readonly property bool busy: app.cpu >= 50

        Layout.fillWidth: true
        implicitHeight: content.implicitHeight + 16

        RowLayout {
            id: content

            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 12

            AppIcon {
                size: 30
                icon: row.app.icon
                glyph: row.app.glyph
                tint: row.app.windowed ? Theme.primary : Theme.frame
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    Layout.fillWidth: true
                    text: row.app.name
                    color: Theme.text
                    font.pixelSize: 15
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: row.app.detail
                    color: Theme.frame
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }

            // CPU as top shows it: 100 is one core
            Label {
                Layout.preferredWidth: 58
                horizontalAlignment: Text.AlignRight
                text: `${Math.round(row.app.cpu)}%`
                color: row.busy ? Theme.warn : Theme.textDim
                font.pixelSize: 14
            }
            Label {
                Layout.preferredWidth: 74
                horizontalAlignment: Text.AlignRight
                text: Tasks.formatMem(row.app.mem)
                color: Theme.muted
                font.pixelSize: 14
            }

            TuiButton {
                implicitWidth: closeLabel.implicitWidth + 18
                implicitHeight: 26
                onClicked: Tasks.close(row.app)

                Label {
                    id: closeLabel
                    anchors.centerIn: parent
                    text: "close"
                    color: parent.hovered ? Theme.text : Theme.muted
                    font.pixelSize: 13
                }
            }

            TuiButton {
                implicitWidth: killLabel.implicitWidth + 18
                implicitHeight: 26
                accent: Theme.danger
                active: row.isArmed
                onClicked: root.kill(row.app)

                Label {
                    id: killLabel
                    anchors.centerIn: parent
                    text: row.isArmed ? "sure?" : "kill"
                    color: row.isArmed || parent.hovered ? Theme.danger : Theme.muted
                    font.pixelSize: 13
                }
            }
        }

        Rectangle {
            visible: !row.last
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Theme.border
        }
    }

    // Scrollable list of TaskRows with a thin scroll indicator
    component TaskList: Item {
        id: list

        property var apps: []
        property int maxHeight: 420
        property string empty: ""

        Layout.fillWidth: true
        implicitHeight: apps.length === 0 ? emptyLabel.implicitHeight + 8 : Math.min(listColumn.implicitHeight, maxHeight)

        Label {
            id: emptyLabel
            visible: list.apps.length === 0
            text: list.empty
            color: Theme.muted
        }

        Flickable {
            id: flick
            anchors.fill: parent
            contentHeight: listColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: listColumn
                width: flick.width - (flick.contentHeight > flick.height ? 12 : 0)
                spacing: 0

                // Rows stay with their app across polls (an armed kill button keeps its state)
                Repeater {
                    model: ScriptModel {
                        values: list.apps
                        objectProp: "key"
                    }

                    TaskRow {
                        required property var modelData
                        required property int index
                        app: modelData
                        last: index === list.apps.length - 1
                    }
                }
            }
        }

        Rectangle {
            visible: flick.contentHeight > flick.height
            anchors.right: parent.right
            width: 4
            y: flick.visibleArea.yPosition * flick.height
            height: flick.visibleArea.heightRatio * flick.height
            color: Theme.frame
        }
    }

    // ── Layout ───────────────────────────────────────────────

    // Keeps clicks on the panel from closing the control center
    MouseArea {
        anchors.fill: parent
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: 0.96
    }

    Frame {
        anchors.fill: parent
        label: "tasks"
        borderColor: Theme.primary
        padding: 0
    }

    ColumnLayout {
        id: column

        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 20; rightMargin: 20; topMargin: 28 }
        spacing: 22

        Frame {
            Layout.fillWidth: true
            implicitHeight: windowList.implicitHeight + 28
            label: `apps with a window · ${Tasks.windowed.length}`
            labelColor: Theme.muted
            padding: 14

            TaskList {
                id: windowList
                anchors { left: parent.left; right: parent.right; top: parent.top }
                apps: Tasks.windowed
                empty: Tasks.loaded ? "no windows open" : "reading /proc …"
            }
        }

        Frame {
            Layout.fillWidth: true
            implicitHeight: backgroundList.implicitHeight + 28
            label: `in the background · ${Tasks.background.length}, busiest first`
            labelColor: Theme.muted
            padding: 14

            TaskList {
                id: backgroundList
                anchors { left: parent.left; right: parent.right; top: parent.top }
                apps: Tasks.background.slice(0, 12)
                maxHeight: 300
                empty: Tasks.loaded ? "nothing" : "reading /proc …"
            }
        }

        Label {
            Layout.fillWidth: true
            text: "close asks the app to quit · kill ends the whole process tree at once, click it twice · cpu: 100% is one core"
            color: Theme.frame
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }
    }
}
