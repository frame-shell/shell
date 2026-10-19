import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.config
import qs.services

// Notification popups top right on the focused screen. They move left while the
// control center or the history panel is open, so nothing overlaps.
Scope {
    id: root

    property int rightOffset: 14
    property int animatedOffset: rightOffset
    Behavior on animatedOffset {
        NumberAnimation { duration: Theme.anim.normal; easing.type: Easing.OutCubic }
    }

    readonly property ShellScreen focusedScreen: {
        const name = Hyprland.focusedMonitor?.name;
        return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
    }

    PanelWindow {
        screen: root.focusedScreen
        visible: Notifications.popups.length > 0
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-notifications"
        anchors {
            top: true
            right: true
        }
        margins {
            top: 66
            right: root.animatedOffset
        }
        implicitWidth: 460
        implicitHeight: column.implicitHeight + 16

        Column {
            id: column

            y: 14
            width: 460
            spacing: 20

            // ScriptModel keeps existing cards (and their timers) when the list changes
            Repeater {
                model: ScriptModel {
                    values: Notifications.popups
                }

                NotificationCard {
                    required property var modelData
                    entry: modelData
                }
            }

            move: Transition {
                NumberAnimation { properties: "y"; duration: Theme.anim.normal; easing.type: Easing.OutCubic }
            }
        }
    }
}
