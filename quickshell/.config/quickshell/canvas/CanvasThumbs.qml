import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.services

// Takes a picture of every canvas window that is on a screen, every few seconds, for the
// overview (CanvasOverview.qml): Hyprland's window capture gives nothing for a window that
// lies fully off every screen, so the overview falls back to the last picture
// (services/Thumbnails.qml). The captures live in a 1×1 window nobody sees; a grab of an
// item renders it on its own, so the window's size does not matter.
Scope {
    id: root

    readonly property bool active: CanvasLayout.enabled
    readonly property int every: 4000
    readonly property int thumbW: 480

    // Windows at least partly on their screen; only those have a picture to take
    readonly property var onScreen: CanvasLayout.windows.filter(w => {
        const v = CanvasLayout.viewOf(CanvasLayout.monitor(w.monitor));
        return w.x < v.x + v.w && w.x + w.w > v.x && w.y < v.y + v.h && w.y + w.h > v.y;
    })

    // Pictures of windows that are gone go too
    property var known: []
    Connections {
        target: CanvasLayout

        function onWindowsChanged() {
            const now = CanvasLayout.windows.map(w => String(w.address));
            for (const a of root.known)
                if (!now.includes(a))
                    Thumbnails.forget(a);
            root.known = now;
        }
    }

    Process {
        id: mkdir
        command: ["mkdir", "-p", Thumbnails.dir]
        running: root.active
    }

    PanelWindow {
        visible: root.active
        screen: Quickshell.screens[0]
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "qs-thumbs"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        Repeater {
            model: ScriptModel {
                values: root.onScreen
                objectProp: "address"
            }

            Item {
                id: slot

                required property var modelData
                readonly property string address: String(modelData.address)
                readonly property var toplevel: {
                    const wanted = address.replace(/^0x/, "").toLowerCase();
                    const t = Hyprland.toplevels.values.find(t => String(t.address ?? "").replace(/^0x/, "").toLowerCase() === wanted);
                    return t?.wayland ?? null;
                }

                width: root.thumbW
                height: Math.max(1, Math.round(root.thumbW * modelData.h / Math.max(1, modelData.w)))
                visible: true

                ScreencopyView {
                    id: capture
                    anchors.fill: parent
                    captureSource: slot.toplevel
                    live: false
                    paintCursor: false
                }

                // Ask for a frame, grab it once it is there; the first wait is spread out so
                // many windows do not all copy in the same instant
                Timer {
                    interval: 600 + (slot.address.length * 137) % 1500
                    running: slot.toplevel !== null
                    repeat: false
                    onTriggered: tick.start()
                }
                Timer {
                    id: tick
                    interval: root.every
                    repeat: true
                    onTriggered: {
                        if (slot.toplevel === null)
                            return;
                        capture.captureFrame();
                        grab.restart();
                    }
                }
                Timer {
                    id: grab
                    interval: 400
                    onTriggered: {
                        if (!capture.hasContent)
                            return;
                        const address = slot.address;
                        capture.grabToImage(result => {
                            if (result.saveToFile(Thumbnails.file(address)))
                                Thumbnails.touch(address);
                        });
                    }
                }
            }
        }
    }
}
