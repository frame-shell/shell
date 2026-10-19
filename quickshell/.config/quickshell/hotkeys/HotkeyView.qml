import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// Hotkey overlay content: a German QWERTZ keyboard with every key lit that does
// something together with Super, then all binds grouped (shell, apps, windows, …).
// Hovering a key says what Super+key and Super+Shift+key do.
Item {
    id: root

    property string hovered: ""

    readonly property int unit: 46
    readonly property int gap: 4

    // [label, key name as Hyprland calls it, width in keys]
    readonly property var keyRows: [
        [["^", "asciicircum", 1], ["1", "1", 1], ["2", "2", 1], ["3", "3", 1], ["4", "4", 1], ["5", "5", 1], ["6", "6", 1],
         ["7", "7", 1], ["8", "8", 1], ["9", "9", 1], ["0", "0", 1], ["ß", "ssharp", 1], ["´", "dead_acute", 1], ["⌫", "backspace", 2]],
        [["tab", "tab", 1.5], ["Q", "q", 1], ["W", "w", 1], ["E", "e", 1], ["R", "r", 1], ["T", "t", 1], ["Z", "z", 1], ["U", "u", 1],
         ["I", "i", 1], ["O", "o", 1], ["P", "p", 1], ["Ü", "udiaeresis", 1], ["+", "plus", 1], ["⏎", "return", 1.5]],
        [["caps", "caps_lock", 1.75], ["A", "a", 1], ["S", "s", 1], ["D", "d", 1], ["F", "f", 1], ["G", "g", 1], ["H", "h", 1],
         ["J", "j", 1], ["K", "k", 1], ["L", "l", 1], ["Ö", "odiaeresis", 1], ["Ä", "adiaeresis", 1], ["#", "numbersign", 1], ["", "", 1.25]],
        [["shift", "shift_l", 1.25], ["<", "less", 1], ["Y", "y", 1], ["X", "x", 1], ["C", "c", 1], ["V", "v", 1], ["B", "b", 1],
         ["N", "n", 1], ["M", "m", 1], [",", "comma", 1], [".", "period", 1], ["-", "minus", 1], ["shift", "shift_r", 2.75]],
        [["ctrl", "control_l", 1.5], ["super", "super_l", 1.25], ["alt", "alt_l", 1.25], ["space", "space", 7],
         ["alt gr", "iso_level3_shift", 1.25], ["menu", "menu", 1.25], ["ctrl", "control_r", 1.5]]
    ]
    readonly property var arrowRows: [
        [["", "", 1], ["↑", "up", 1], ["", "", 1]],
        [["←", "left", 1], ["↓", "down", 1], ["→", "right", 1]]
    ]

    // Super+1 … Super+0 share one row in Binds
    function bindsOf(keyId) {
        return keyId === "" ? [] : Binds.forKey(/^[0-9]$/.test(keyId) ? "1…0" : keyId);
    }

    function plain(keyId) {
        return bindsOf(keyId).some(r => !r.mods.includes("shift"));
    }

    function shifted(keyId) {
        return bindsOf(keyId).some(r => r.mods.includes("shift"));
    }

    function capsOf(row) {
        return row.mods.concat([row.key]);
    }

    readonly property string hoverText: {
        if (hovered === "")
            return "hover a key: what super + key and super + shift + key do";
        const list = bindsOf(hovered);
        if (list.length === 0)
            return "nothing bound with super";
        return list.map(r => `${r.mods.join(" + ")} + ${r.key}: ${r.label}`).join("   ·   ");
    }

    implicitWidth: content.implicitWidth + 56
    implicitHeight: content.implicitHeight + 60
    width: implicitWidth
    height: implicitHeight

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: 14
    }

    component KeyCap: Rectangle {
        id: cap
        property string text: ""
        implicitWidth: capText.implicitWidth + 12
        implicitHeight: 22
        color: "transparent"
        border.width: 1
        border.color: Theme.frame
        Label {
            id: capText
            anchors.centerIn: parent
            text: cap.text
            color: Theme.text
            font.pixelSize: 12
        }
    }

    // One key of the map: lit when Super+key is bound, a dot when only Super+Shift+key is
    component Key: Rectangle {
        id: key

        property var spec: ["", "", 1]
        readonly property string keyId: spec[1]
        readonly property bool isSuper: keyId === "super_l"
        readonly property bool lit: root.plain(keyId)
        readonly property bool marked: !lit && root.shifted(keyId)

        width: spec[2] * root.unit - root.gap
        height: root.unit - root.gap
        color: lit ? Theme.primary : "transparent"
        border.width: keyId === "" ? 0 : 1
        border.color: isSuper || keyHover.hovered ? Theme.secondary : lit ? Theme.primary : Theme.border

        Label {
            anchors.centerIn: parent
            text: key.spec[0]
            color: key.lit ? Theme.bg : key.isSuper ? Theme.secondary : Theme.muted
            font.pixelSize: key.spec[0].length > 1 ? 12 : 15
            font.weight: key.lit ? Font.Medium : Font.Normal
        }

        Rectangle {
            visible: key.marked
            anchors { right: parent.right; top: parent.top; margins: 5 }
            width: 5
            height: 5
            color: Theme.accent
        }

        HoverHandler {
            id: keyHover
            onHoveredChanged: {
                if (hovered)
                    root.hovered = key.keyId;
                else if (root.hovered === key.keyId)
                    root.hovered = "";
            }
        }
    }

    // Swallows clicks so they do not close the overlay
    MouseArea {
        anchors.fill: parent
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: 0.97
    }

    Frame {
        anchors.fill: parent
        label: "hotkeys · hold super"
        borderColor: Theme.primary
        padding: 0
    }

    ColumnLayout {
        id: content

        anchors { left: parent.left; top: parent.top; leftMargin: 28; topMargin: 32 }
        spacing: 18

        // Keyboard and arrow keys
        RowLayout {
            spacing: root.unit / 2

            Column {
                spacing: root.gap
                Repeater {
                    model: root.keyRows
                    Row {
                        id: keyRow
                        required property var modelData
                        spacing: root.gap
                        Repeater {
                            model: keyRow.modelData
                            Key {
                                required property var modelData
                                spec: modelData
                            }
                        }
                    }
                }
            }

            Column {
                Layout.alignment: Qt.AlignBottom
                spacing: root.gap
                Repeater {
                    model: root.arrowRows
                    Row {
                        id: arrowRow
                        required property var modelData
                        spacing: root.gap
                        Repeater {
                            model: arrowRow.modelData
                            Key {
                                required property var modelData
                                spec: modelData
                            }
                        }
                    }
                }
            }
        }

        // What the hovered key does, and the legend
        RowLayout {
            Layout.fillWidth: true
            spacing: 18

            Label {
                Layout.fillWidth: true
                text: root.hoverText
                color: root.hovered === "" ? Theme.frame : Theme.secondary
                elide: Text.ElideRight
            }

            Row {
                spacing: 6
                Rectangle { width: 12; height: 12; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                Label { text: "super + key"; color: Theme.muted; font.pixelSize: 12 }
                Item { width: 10; height: 1 }
                Rectangle { width: 6; height: 6; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                Label { text: "only with shift"; color: Theme.muted; font.pixelSize: 12 }
            }
        }

        // All binds by group
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 22
            rowSpacing: 26

            Repeater {
                model: Binds.groupOrder.filter(g => Binds.inGroup(g).length > 0)

                Frame {
                    id: group

                    required property string modelData
                    readonly property var rows: Binds.inGroup(modelData)

                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 360
                    implicitHeight: groupColumn.implicitHeight + 34
                    label: modelData
                    labelColor: Theme.muted
                    padding: 0

                    ColumnLayout {
                        id: groupColumn
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; topMargin: 20 }
                        spacing: 6

                        Repeater {
                            // Long groups get cut, the overlay has to fit on one screen
                            model: group.rows.slice(0, 9)

                            RowLayout {
                                id: bindRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 4

                                Repeater {
                                    model: root.capsOf(bindRow.modelData)
                                    KeyCap {
                                        required property string modelData
                                        text: modelData
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 8
                                    text: bindRow.modelData.label
                                    elide: Text.ElideRight
                                }

                                Label {
                                    text: bindRow.modelData.source
                                    color: bindRow.modelData.source === "frame" ? Theme.primary : Theme.frame
                                    font.pixelSize: 11
                                }
                            }
                        }

                        Label {
                            visible: group.rows.length > 9
                            text: `+ ${group.rows.length - 9} more`
                            color: Theme.frame
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }

        Label {
            visible: !Binds.loaded
            text: "reading binds from hyprctl …"
            color: Theme.muted
        }

        Label {
            text: "release super to close · read live from hyprctl binds; descriptions come from the binds"
            color: Theme.frame
            font.pixelSize: 12
        }
    }
}
