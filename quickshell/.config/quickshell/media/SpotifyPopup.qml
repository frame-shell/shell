import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

// Popup top left whenever Spotify starts another song: cover, title, artist, album,
// progress and controls. Hides after six seconds and stays while the mouse is on it.
// Not for songs skipped from the media card under the bar.
// No like button: Spotify does not offer liking over MPRIS.
Scope {
    id: root

    readonly property MprisPlayer spotify: Mpris.players.values.find(p => p.identity === "Spotify") ?? null
    property string lastTrack: ""
    property bool open: false
    property real remaining: 1

    property real shown: open ? 1 : 0
    Behavior on shown {
        NumberAnimation { duration: root.open ? Theme.anim.normal : Theme.anim.fast; easing.type: Easing.OutCubic }
    }

    function trackKey(player) {
        return player ? `${player.trackTitle}|${player.trackArtist}` : "";
    }

    function format(seconds) {
        const s = Math.max(0, Math.floor(seconds || 0));
        return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
    }

    function trackChanged() {
        const key = trackKey(spotify);
        if (!spotify || spotify.trackTitle === "" || key === lastTrack)
            return;
        lastTrack = key;
        // Skipped from the card under the bar: you are already looking at it
        if (Spotify.cardOpen)
            return;
        open = true;
        hideAnimation.restart();
    }

    // No popup for the song that was already playing when the shell started
    onSpotifyChanged: lastTrack = trackKey(spotify)

    Connections {
        target: root.spotify
        function onTrackTitleChanged() {
            root.trackChanged();
        }
        function onTrackArtistChanged() {
            root.trackChanged();
        }
    }

    NumberAnimation {
        id: hideAnimation
        target: root
        property: "remaining"
        from: 1
        to: 0
        duration: 6000
        paused: cardHover.hovered
        onFinished: root.open = false
    }

    // MPRIS does not push the position, so ask for it while the popup is visible
    Timer {
        running: root.open && (root.spotify?.isPlaying ?? false)
        interval: 1000
        repeat: true
        onTriggered: root.spotify.positionChanged()
    }

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: 14
        elide: Text.ElideRight
    }

    component Control: TuiButton {
        id: control

        property string glyph
        implicitWidth: 34
        implicitHeight: 28

        Text {
            anchors.centerIn: parent
            text: control.glyph
            color: control.hovered ? Theme.text : Theme.secondary
            font.family: Theme.iconFont
            font.pixelSize: 16
        }
    }

    PanelWindow {
        id: window

        screen: {
            const name = Hyprland.focusedMonitor?.name;
            return Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0];
        }
        visible: (root.open || root.shown > 0.01) && root.spotify !== null
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-media-popup"
        anchors {
            top: true
            left: true
        }
        margins {
            top: 66
            left: 14
        }
        implicitWidth: 420
        implicitHeight: card.height + 16

        Item {
            id: card

            y: 12
            width: 420
            height: layout.implicitHeight + 36
            opacity: root.shown
            transform: Translate { x: -24 * (1 - root.shown) }

            HoverHandler {
                id: cardHover
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.bg
                opacity: 0.96
            }

            Frame {
                anchors.fill: parent
                label: "now playing · spotify"
                borderColor: Theme.primary
                padding: 0
            }

            GridLayout {
                id: layout

                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 16; rightMargin: 16; topMargin: 24 }
                columns: 2
                columnSpacing: 14
                rowSpacing: 10

                Rectangle {
                    implicitWidth: 72
                    implicitHeight: 72
                    color: Theme.surface2

                    Image {
                        anchors.fill: parent
                        source: root.spotify?.trackArtUrl ?? ""
                        sourceSize: Qt.size(144, 144)
                        fillMode: Image.PreserveAspectCrop
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Label {
                        Layout.fillWidth: true
                        text: root.spotify?.trackTitle ?? ""
                        color: Theme.text
                        font.pixelSize: 17
                        font.weight: Font.Medium
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.spotify?.trackArtist ?? ""
                        color: Theme.secondary
                    }
                    Label {
                        Layout.fillWidth: true
                        text: root.spotify?.trackAlbum ?? ""
                        color: Theme.frame
                        font.pixelSize: 13
                    }

                    Row {
                        Layout.topMargin: 6
                        spacing: 6

                        Control {
                            glyph: ""
                            available: root.spotify?.canGoPrevious ?? false
                            onClicked: root.spotify.previous()
                        }
                        Control {
                            glyph: root.spotify?.isPlaying ? "" : ""
                            onClicked: root.spotify.togglePlaying()
                        }
                        Control {
                            glyph: ""
                            available: root.spotify?.canGoNext ?? false
                            onClicked: root.spotify.next()
                        }
                    }
                }

                RowLayout {
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    spacing: 12

                    Label {
                        Layout.preferredWidth: 40
                        text: root.format(root.spotify?.position)
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                    Meter {
                        Layout.fillWidth: true
                        implicitHeight: 3
                        value: (root.spotify?.length ?? 0) > 0 ? root.spotify.position / root.spotify.length : 0
                        fill: Theme.primary
                    }
                    Label {
                        Layout.preferredWidth: 40
                        horizontalAlignment: Text.AlignRight
                        text: root.format(root.spotify?.length)
                        color: Theme.muted
                        font.pixelSize: 12
                    }
                }
            }

            // Time until the popup hides
            Rectangle {
                anchors { left: parent.left; bottom: parent.bottom }
                width: parent.width * root.remaining
                height: 2
                color: Theme.frame
            }
        }
    }
}
