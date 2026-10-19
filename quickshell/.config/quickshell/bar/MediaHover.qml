import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import qs.components
import qs.config

// Card under the media segment of the bar while the mouse is on it: cover, title,
// progress and play/pause. Next/previous only show when the player supports them
// (Spotify does, a YouTube tab in the browser usually does not).
PopupWindow {
    id: root

    property MprisPlayer player
    // The bar window this card hangs from
    property var barWindow
    // Left edge of the media segment in bar coordinates
    property real anchorX: 0
    property bool open: false
    readonly property bool hovered: hover.hovered

    property real shown: open ? 1 : 0
    Behavior on shown {
        NumberAnimation { duration: root.open ? Theme.anim.normal : Theme.anim.fast; easing.type: Easing.OutCubic }
    }

    readonly property bool canSkip: (player?.canGoNext ?? false) || (player?.canGoPrevious ?? false)

    function format(seconds) {
        const s = Math.max(0, Math.floor(seconds || 0));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    visible: (open || shown > 0.01) && player !== null
    color: "transparent"
    anchor.window: barWindow
    anchor.rect.x: Math.max(14, Math.min(anchorX - 16, (barWindow?.width ?? 1920) - 14 - 430))
    anchor.rect.y: 52
    implicitWidth: 430
    implicitHeight: card.height + 16

    Timer {
        running: root.open && (root.player?.isPlaying ?? false)
        interval: 1000
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: 15
        elide: Text.ElideRight
    }

    component Control: TuiButton {
        property string glyph
        implicitWidth: 38
        implicitHeight: 30

        Text {
            anchors.centerIn: parent
            text: parent.glyph
            color: parent.hovered ? Theme.text : Theme.secondary
            font.family: Theme.iconFont
            font.pixelSize: 15
        }
    }

    Item {
        id: card

        y: 12
        width: 430
        height: layout.implicitHeight + 42
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
            label: (root.player?.identity ?? "media").toLowerCase()
            borderColor: Theme.primary
            padding: 0
        }

        GridLayout {
            id: layout

            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 24 }
            columns: 2
            columnSpacing: 16
            rowSpacing: 14

            Rectangle {
                implicitWidth: 76
                implicitHeight: 76
                color: Theme.surface2

                Image {
                    anchors.fill: parent
                    source: root.player?.trackArtUrl ?? ""
                    sourceSize: Qt.size(152, 152)
                    fillMode: Image.PreserveAspectCrop
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    Layout.fillWidth: true
                    text: root.player?.trackTitle ?? ""
                    color: Theme.text
                    font.pixelSize: 16
                    font.weight: Font.Medium
                }
                Label {
                    Layout.fillWidth: true
                    text: root.player?.trackArtist ?? ""
                    color: Theme.secondary
                }

                RowLayout {
                    Layout.topMargin: 10
                    spacing: 8

                    Control {
                        visible: root.player?.canGoPrevious ?? false
                        glyph: ""
                        onClicked: root.player.previous()
                    }
                    Control {
                        glyph: root.player?.isPlaying ? "" : ""
                        available: root.player?.canTogglePlaying ?? true
                        onClicked: root.player.togglePlaying()
                    }
                    Control {
                        visible: root.player?.canGoNext ?? false
                        glyph: ""
                        onClicked: root.player.next()
                    }
                    Label {
                        visible: !root.canSkip
                        text: "no next/previous here"
                        color: Theme.frame
                        font.pixelSize: 12
                    }
                }
            }

            RowLayout {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                spacing: 10

                Label {
                    Layout.preferredWidth: 44
                    text: root.format(root.player?.position)
                    color: Theme.muted
                    font.pixelSize: 13
                }
                Meter {
                    Layout.fillWidth: true
                    implicitHeight: 3
                    value: (root.player?.length ?? 0) > 0 ? root.player.position / root.player.length : 1
                    fill: Theme.primary
                }
                Label {
                    Layout.preferredWidth: 44
                    horizontalAlignment: Text.AlignRight
                    text: (root.player?.length ?? 0) > 0 ? root.format(root.player.length) : "live"
                    color: Theme.muted
                    font.pixelSize: 13
                }
            }
        }
    }
}
