import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.components
import qs.config

// Month calendar under the clock in the bar while the mouse is on it (or on the card).
// Weeks start on Monday and show their ISO week number; ‹ › flip the month.
PopupWindow {
    id: root

    property var barWindow
    // Horizontal center of the clock in bar coordinates
    property real anchorX: 0
    property bool open: false
    readonly property bool hovered: hover.hovered
    property int monthOffset: 0

    property real shown: open ? 1 : 0
    Behavior on shown {
        NumberAnimation { duration: root.open ? Theme.anim.normal : Theme.anim.fast; easing.type: Easing.OutCubic }
    }

    // Opening again always starts at the current month
    onOpenChanged: {
        if (open)
            monthOffset = 0;
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property date today: clock.date
    readonly property date month: new Date(today.getFullYear(), today.getMonth() + monthOffset, 1)

    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function isoWeek(date) {
        const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        const day = d.getUTCDay() || 7;
        d.setUTCDate(d.getUTCDate() + 4 - day);
        const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
        return Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
    }

    // 6 weeks × (week number + 7 days)
    readonly property var cells: {
        const lead = (month.getDay() + 6) % 7;
        const start = new Date(month.getFullYear(), month.getMonth(), 1 - lead);
        const out = [];
        for (let w = 0; w < 6; w++) {
            const monday = new Date(start.getFullYear(), start.getMonth(), start.getDate() + w * 7);
            out.push({ text: String(isoWeek(monday)), kind: "week" });
            for (let i = 0; i < 7; i++) {
                const d = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i);
                out.push({
                    text: String(d.getDate()),
                    kind: sameDay(d, today) ? "today" : d.getMonth() !== month.getMonth() ? "other" : i >= 5 ? "weekend" : "day"
                });
            }
        }
        return out;
    }

    visible: open || shown > 0.01
    color: "transparent"
    anchor.window: barWindow
    anchor.rect.x: Math.max(14, Math.min(anchorX - 190, (barWindow?.width ?? 1920) - 14 - 380))
    anchor.rect.y: 52
    implicitWidth: 380
    implicitHeight: card.height + 16

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: 15
        horizontalAlignment: Text.AlignHCenter
    }

    Item {
        id: card

        y: 12
        width: 380
        height: layout.implicitHeight + 44
        opacity: root.shown
        transform: Translate { y: -8 * (1 - root.shown) }

        HoverHandler {
            id: hover
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            opacity: 0.97
        }

        Frame {
            anchors.fill: parent
            label: "calendar"
            borderColor: Theme.primary
            padding: 0
        }

        ColumnLayout {
            id: layout

            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 18; rightMargin: 18; topMargin: 24 }
            spacing: 8

            // ‹ october 2026 ›
            RowLayout {
                Layout.fillWidth: true

                TuiButton {
                    implicitWidth: 30
                    implicitHeight: 26
                    onClicked: root.monthOffset -= 1
                    Label { anchors.centerIn: parent; text: "‹"; color: Theme.secondary }
                }
                Label {
                    Layout.fillWidth: true
                    text: root.month.toLocaleDateString(Qt.locale("en_GB"), "MMMM yyyy").toLowerCase()
                    color: Theme.text
                    font.weight: Font.Medium
                }
                TuiButton {
                    implicitWidth: 30
                    implicitHeight: 26
                    onClicked: root.monthOffset += 1
                    Label { anchors.centerIn: parent; text: "›"; color: Theme.secondary }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 8
                columnSpacing: 2
                rowSpacing: 2

                Repeater {
                    model: ["wk", "mo", "tu", "we", "th", "fr", "sa", "su"]
                    Label {
                        required property string modelData
                        Layout.fillWidth: true
                        text: modelData
                        color: Theme.frame
                        font.pixelSize: 13
                    }
                }

                Repeater {
                    model: root.cells

                    Rectangle {
                        required property var modelData

                        Layout.fillWidth: true
                        implicitHeight: 30
                        color: modelData.kind === "today" ? Theme.primary : "transparent"

                        Label {
                            anchors.centerIn: parent
                            text: parent.modelData.text
                            font.pixelSize: parent.modelData.kind === "week" ? 12 : 15
                            font.weight: parent.modelData.kind === "today" ? Font.Medium : Font.Normal
                            color: parent.modelData.kind === "today" ? Theme.bg
                                : parent.modelData.kind === "week" ? Theme.frame
                                : parent.modelData.kind === "other" ? Theme.border
                                : parent.modelData.kind === "weekend" ? Theme.muted
                                : Theme.textDim
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4

                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignLeft
                    text: `${root.today.toLocaleDateString(Qt.locale("en_GB"), "dddd d MMMM").toLowerCase()} · week ${root.isoWeek(root.today)}`
                    color: Theme.muted
                    font.pixelSize: 13
                }
                Label {
                    visible: root.monthOffset !== 0
                    text: "back to today"
                    color: Theme.secondary
                    font.pixelSize: 13

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.monthOffset = 0
                    }
                }
            }
        }
    }
}
