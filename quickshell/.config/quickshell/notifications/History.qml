import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

// Notification history under the bell in the bar.
// `qs ipc call notifications toggle`, also `open` and `close`.
Scope {
    id: root

    property bool open: false
    property real shown: open ? 1 : 0
    Behavior on shown {
        NumberAnimation { duration: root.open ? Theme.anim.normal : Theme.anim.fast; easing.type: Easing.OutCubic }
    }

    function show(screen) {
        if (open)
            return;
        const name = Hyprland.focusedMonitor?.name;
        window.screen = screen ?? Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
        open = true;
        Notifications.markSeen();
    }

    function hide() {
        open = false;
    }

    function toggle(screen) {
        if (open)
            hide();
        else
            show(screen);
    }

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: 15
    }

    PanelWindow {
        id: window

        visible: root.open || root.shown > 0.01
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-notification-history"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.hide()
        }

        FocusScope {
            anchors.fill: parent
            focus: root.open
            Keys.onEscapePressed: root.hide()

            Item {
                id: panel

                anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: 78 }
                width: 460
                height: list.implicitHeight + 46
                opacity: root.shown
                transform: Translate { y: -12 * (1 - root.shown) }

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
                    label: "notifications"
                    borderColor: Theme.primary
                    padding: 0
                }

                TuiButton {
                    anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: -height / 2 }
                    implicitWidth: clearLabel.implicitWidth + 20
                    implicitHeight: 22
                    color: Theme.bg
                    onClicked: Notifications.clearHistory()

                    Label {
                        id: clearLabel
                        anchors.centerIn: parent
                        text: "clear all"
                        color: Theme.secondary
                        font.pixelSize: 13
                    }
                }

                ColumnLayout {
                    id: list

                    anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 18; rightMargin: 18; topMargin: 28 }
                    spacing: 0

                    Label {
                        visible: Notifications.history.length === 0
                        Layout.bottomMargin: 4
                        text: "no notifications"
                        color: Theme.muted
                    }

                    Repeater {
                        model: Notifications.history.slice(0, 8)

                        Item {
                            id: row

                            required property var modelData
                            required property int index

                            Layout.fillWidth: true
                            implicitHeight: rowContent.implicitHeight + 16

                            RowLayout {
                                id: rowContent

                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 12

                                AppIcon {
                                    size: 30
                                    icon: row.modelData.image
                                    glyph: row.modelData.glyph
                                    tint: row.modelData.kind === "voice" ? Theme.violet : Theme.primary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0

                                    RowLayout {
                                        Label {
                                            Layout.fillWidth: true
                                            text: row.modelData.title
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            text: `${row.modelData.app} · ${Notifications.ago(row.modelData.time)}`
                                            color: Theme.frame
                                            font.pixelSize: 13
                                        }
                                    }

                                    Label {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: row.modelData.body
                                        color: Theme.muted
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                }
                            }

                            Rectangle {
                                visible: row.index < Math.min(8, Notifications.history.length) - 1
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                height: 1
                                color: Theme.border
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            root.toggle(null);
        }

        function open(): void {
            root.show(null);
        }

        function close(): void {
            root.hide();
        }
    }
}
