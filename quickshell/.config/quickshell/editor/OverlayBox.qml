import QtQuick
import QtQuick.Effects
import qs.config

// A blur box or a picture on top of the video or picture being edited, with a frame, a name
// tag and a corner to size it. Used by both editors (EditorView, ImageEditorView).
//
// o is the overlay ({ id, type: "blur" | "picture", x, y, w, h, … } as fractions of the
// frame), store the project it lives in (snapshot(), updateOverlay()), frame the item that
// covers the shown picture, capture the item to blur (the video or the picture itself, laid
// out over the same area as frame's parent).
Item {
    id: box

    property var o: null
    property var store: null
    property Item frame: null
    property Item capture: null
    // Pixel width of the original, so a blur's strength looks alike in the preview and the export
    property real nativeWidth: 1
    property bool shown: true
    property bool selected: false

    signal picked()

    readonly property real block: Math.max(4, (o?.strength ?? 14) * 1.4 * (frame?.width ?? 1) / Math.max(1, nativeWidth))

    visible: shown && o !== null
    x: (o?.x ?? 0) * (frame?.width ?? 0)
    y: (o?.y ?? 0) * (frame?.height ?? 0)
    width: (o?.w ?? 0.1) * (frame?.width ?? 0)
    height: (o && o.h > 0 ? o.h : (o?.w ?? 0.1)) * (frame?.height ?? 0)

    // Blur: what is under the box, through the blur or shrunk to blocks (pixelate)
    ShaderEffectSource {
        id: under

        anchors.fill: parent
        visible: box.o?.type === "blur" && box.o.style === "pixel"
        sourceItem: box.o?.type === "blur" ? box.capture : null
        sourceRect: Qt.rect((box.frame?.x ?? 0) + box.x, (box.frame?.y ?? 0) + box.y, box.width, box.height)
        live: true
        smooth: false
        textureSize: box.o?.style === "pixel"
            ? Qt.size(Math.max(1, Math.round(box.width / box.block)), Math.max(1, Math.round(box.height / box.block)))
            : Qt.size(Math.max(1, box.width), Math.max(1, box.height))
    }

    MultiEffect {
        anchors.fill: parent
        visible: box.o?.type === "blur" && box.o.style !== "pixel"
        source: under
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: Math.max(8, Math.min(64, Math.round((box.o?.strength ?? 14) * 3)))
    }

    Image {
        anchors.fill: parent
        visible: box.o?.type === "picture"
        source: box.o?.type === "picture" ? "file://" + box.o.src.split("/").map(encodeURIComponent).join("/") : ""
        opacity: box.o?.opacity ?? 1
        asynchronous: true
        fillMode: Image.Stretch
        // A new picture keeps its own shape
        onStatusChanged: {
            if (status === Image.Ready && box.o && box.o.h < 0 && implicitWidth > 0 && box.frame && box.frame.height > 0) {
                const h = box.o.w * box.frame.width * implicitHeight / implicitWidth / box.frame.height;
                box.store.updateOverlay(box.o.id, { h: Math.min(1 - box.o.y, h) }, false);
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: box.o?.type === "blur" ? Theme.warn : Theme.secondary
        visible: box.selected || move.containsMouse
        opacity: box.selected ? 1 : 0.5
    }

    Rectangle {
        visible: box.selected
        y: -height
        width: tag.implicitWidth + 10
        height: tag.implicitHeight + 2
        color: box.o?.type === "blur" ? Theme.warn : Theme.secondary

        Text {
            id: tag
            anchors.centerIn: parent
            text: box.o?.name ?? ""
            color: Theme.bg
            font.family: Theme.font
            font.pixelSize: 11
        }
    }

    MouseArea {
        id: move

        property point start
        property var from

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.SizeAllCursor
        onPressed: mouse => {
            box.picked();
            box.store.snapshot();
            start = mapToItem(box.frame, mouse.x, mouse.y);
            from = { x: box.o.x, y: box.o.y };
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return;
            const p = mapToItem(box.frame, mouse.x, mouse.y);
            const h = box.o.h > 0 ? box.o.h : box.o.w;
            box.store.updateOverlay(box.o.id, {
                x: Math.max(0, Math.min(1 - box.o.w, from.x + (p.x - start.x) / box.frame.width)),
                y: Math.max(0, Math.min(1 - h, from.y + (p.y - start.y) / box.frame.height))
            }, false);
        }
    }

    // Bottom right: size
    Rectangle {
        visible: box.selected
        x: parent.width - 6
        y: parent.height - 6
        width: 12
        height: 12
        color: box.o?.type === "blur" ? Theme.warn : Theme.secondary

        MouseArea {
            property point start
            property var from

            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.SizeFDiagCursor
            onPressed: mouse => {
                box.store.snapshot();
                start = mapToItem(box.frame, mouse.x, mouse.y);
                from = { w: box.o.w, h: box.o.h > 0 ? box.o.h : box.o.w };
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return;
                const p = mapToItem(box.frame, mouse.x, mouse.y);
                box.store.updateOverlay(box.o.id, {
                    w: Math.max(0.02, Math.min(1 - box.o.x, from.w + (p.x - start.x) / box.frame.width)),
                    h: Math.max(0.02, Math.min(1 - box.o.y, from.h + (p.y - start.y) / box.frame.height))
                }, false);
            }
        }
    }
}
