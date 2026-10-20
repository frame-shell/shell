import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config
import qs.services

// App mixer beside the control center: per-app volume, mute and GoXLR routing.
// From six apps on every app takes one line; apps that play right now come first,
// idle ones are dimmed at the bottom, and the list scrolls inside the panel.
Item {
    id: root

    // Moving a stream to another channel (or a short pause) drops its link for a moment, so
    // the order only follows idle changes after they held for a while; new and gone apps
    // show up at once
    readonly property var rawPlayback: sortActive(Audio.playback)
    readonly property var rawRecording: sortActive(Audio.recording)
    property var playback: []
    property var recording: []
    readonly property bool compact: Audio.playback.length > 5
    readonly property int activeCount: playback.filter(n => !Audio.isIdle(n)).length
    readonly property int idleCount: playback.length - activeCount

    implicitHeight: column.implicitHeight + 46

    function sortActive(list) {
        return list.slice().sort((a, b) => (Audio.isIdle(a) ? 1 : 0) - (Audio.isIdle(b) ? 1 : 0));
    }

    function sameSet(a, b) {
        return a.length === b.length && a.every(n => b.includes(n));
    }

    function sameOrder(a, b) {
        return sameSet(a, b) && a.every((n, i) => n === b[i]);
    }

    onRawPlaybackChanged: sameSet(rawPlayback, playback) ? settle.restart() : playback = rawPlayback
    onRawRecordingChanged: sameSet(rawRecording, recording) ? settle.restart() : recording = rawRecording
    Component.onCompleted: {
        playback = rawPlayback;
        recording = rawRecording;
    }

    Timer {
        id: settle
        interval: 800
        onTriggered: {
            if (!root.sameOrder(root.rawPlayback, root.playback))
                root.playback = root.rawPlayback;
            if (!root.sameOrder(root.rawRecording, root.recording))
                root.recording = root.rawRecording;
        }
    }

    // ── Building blocks ──────────────────────────────────────

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: 16
    }

    component StreamRow: Item {
        id: row

        required property var node
        property var routes: []
        property bool last: false
        // idle and route settle with a delay too: while PipeWire relinks the stream, the
        // row would otherwise dim and lose its chip for a moment
        // No bindings on idle and route: the first change would follow them at once and
        // skip the delay; they start from the live values and then only the timer sets them
        readonly property bool idleNow: Audio.isIdle(node)
        property bool idle: false
        readonly property string routeNow: Audio.routeOf(node)
        property string route: ""
        Component.onCompleted: {
            idle = idleNow;
            route = routeNow;
        }
        onIdleNowChanged: idleSettle.restart()
        onRouteNowChanged: {
            if (routeNow !== "")
                route = routeNow;
            else
                idleSettle.restart();
        }
        Timer {
            id: idleSettle
            interval: 800
            onTriggered: {
                row.idle = row.idleNow;
                row.route = row.routeNow;
            }
        }
        readonly property real volume: node.audio?.volume ?? 0
        readonly property bool muted: node.audio?.muted ?? false
        readonly property string app: Audio.appName(node)

        Layout.fillWidth: true
        implicitHeight: content.implicitHeight + (root.compact ? 12 : 20)
        opacity: idle ? 0.5 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.anim.fast } }

        RowLayout {
            id: content

            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 14

            AppIcon {
                Layout.alignment: root.compact ? Qt.AlignVCenter : Qt.AlignTop
                size: root.compact ? 30 : 40
                icon: Audio.iconName(row.node)
                glyph: row.app.charAt(0).toUpperCase()
                tint: Theme.primary
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.compact ? 2 : 1
                columnSpacing: 12
                rowSpacing: 8

                // Name and what it plays
                ColumnLayout {
                    Layout.preferredWidth: root.compact ? 170 : -1
                    Layout.maximumWidth: root.compact ? 170 : 100000
                    Layout.fillWidth: !root.compact
                    spacing: 0

                    RowLayout {
                        spacing: 8
                        Label {
                            Layout.fillWidth: true
                            text: row.app
                            color: Theme.text
                            font.pixelSize: root.compact ? 15 : 16
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        Label {
                            visible: row.idle && !root.compact
                            text: "idle"
                            color: Theme.frame
                            font.pixelSize: 12
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: Audio.mediaName(row.node) + (row.idle && root.compact ? " · idle" : "")
                        color: Theme.frame
                        font.pixelSize: root.compact ? 12 : 14
                        elide: Text.ElideRight
                        visible: text !== ""
                    }
                }

                // Route chips, volume, mute
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Row {
                        spacing: 6

                        Repeater {
                            model: row.routes

                            TuiButton {
                                required property string modelData

                                implicitWidth: chipLabel.implicitWidth + (root.compact ? 14 : 18)
                                implicitHeight: root.compact ? 22 : 26
                                active: row.route === modelData
                                // Show the new chip at once; PipeWire confirms a moment later
                                onClicked: {
                                    row.route = modelData;
                                    Audio.move(row.node, modelData);
                                }

                                Label {
                                    id: chipLabel
                                    anchors.centerIn: parent
                                    text: parent.parent.modelData
                                    color: parent.parent.active ? Theme.text : Theme.muted
                                    font.pixelSize: root.compact ? 12 : 13
                                }
                            }
                        }
                    }

                    TuiSlider {
                        Layout.fillWidth: true
                        value: row.volume
                        dimmed: row.muted
                        onMoved: value => Audio.setVolume(row.node, value)
                    }

                    Label {
                        Layout.preferredWidth: 52
                        horizontalAlignment: Text.AlignRight
                        text: `${Math.round(row.volume * 100)}%`
                    }

                    TuiButton {
                        implicitWidth: root.compact ? 30 : 34
                        implicitHeight: root.compact ? 26 : 30
                        accent: Theme.danger
                        active: row.muted
                        onClicked: Audio.toggleMute(row.node)

                        Text {
                            anchors.centerIn: parent
                            text: row.muted ? "" : ""
                            color: row.muted ? Theme.danger : Theme.secondary
                            font.family: Theme.iconFont
                            font.pixelSize: 15
                        }
                    }
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

    // Scrollable list of StreamRows with a thin scroll indicator
    component StreamList: Item {
        id: list

        property var nodes: []
        property var routes: []
        property int maxHeight: 470
        property string empty: ""

        Layout.fillWidth: true
        implicitHeight: nodes.length === 0 ? emptyLabel.implicitHeight + 8 : Math.min(listColumn.implicitHeight, maxHeight)

        Label {
            id: emptyLabel
            visible: list.nodes.length === 0
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

                // ScriptModel keeps rows (and a slider being dragged) when PipeWire updates the list
                Repeater {
                    model: ScriptModel {
                        values: list.nodes
                    }

                    StreamRow {
                        required property var modelData
                        required property int index
                        node: modelData
                        routes: list.routes
                        last: index === list.nodes.length - 1
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

    // Keeps clicks on the mixer from closing the control center
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
        label: "app mixer"
        borderColor: Theme.primary
        padding: 0
    }

    ColumnLayout {
        id: column

        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 20; rightMargin: 20; topMargin: 28 }
        spacing: 22

        Frame {
            Layout.fillWidth: true
            implicitHeight: playbackList.implicitHeight + 28
            label: `playback → goxlr channel · ${root.activeCount} active${root.idleCount > 0 ? `, ${root.idleCount} idle` : ""}`
            labelColor: Theme.muted
            padding: 14

            StreamList {
                id: playbackList
                anchors { left: parent.left; right: parent.right; top: parent.top }
                nodes: root.playback
                routes: Audio.outputRoutes
                empty: "nothing is playing"
            }
        }

        Frame {
            Layout.fillWidth: true
            implicitHeight: recordingList.implicitHeight + 28
            label: "recording ← goxlr input"
            labelColor: Theme.muted
            padding: 14

            StreamList {
                id: recordingList
                anchors { left: parent.left; right: parent.right; top: parent.top }
                nodes: root.recording
                routes: Audio.inputRoutes
                maxHeight: 220
                empty: "nothing is recording"
            }
        }

        Label {
            Layout.fillWidth: true
            text: Audio.outputRoutes.length === 0
                ? "no goxlr outputs found · check goxlrOutputs in config/Config.qml"
                : "routing is remembered per app, so Spotify stays on music after a restart"
            color: Theme.frame
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }
    }
}
