import QtQuick
import QtQuick.Layouts
import qs.components
import qs.config
import qs.services

// System numbers for the control center, with a CPU curve for the last minute.
ColumnLayout {
    id: root

    spacing: 4

    component Label: Text {
        color: Theme.textDim
        font.family: Theme.font
        font.pixelSize: 16
    }

    component StatRow: RowLayout {
        property string name
        property real value
        property string text

        Layout.fillWidth: true
        spacing: 14

        Label {
            Layout.preferredWidth: 56
            text: parent.name
            color: Theme.muted
        }
        Meter {
            Layout.fillWidth: true
            value: parent.value
        }
        Label {
            Layout.preferredWidth: 150
            horizontalAlignment: Text.AlignRight
            text: parent.text
        }
    }

    component Sub: Label {
        Layout.leftMargin: 70
        Layout.bottomMargin: 4
        color: Theme.frame
        font.pixelSize: 13
        visible: text !== ""
    }

    function temp(value) {
        return value > 0 ? ` · ${Math.round(value)}°` : "";
    }

    StatRow {
        name: "cpu"
        value: SystemStats.cpu / 100
        text: `${Math.round(SystemStats.cpu)}%${root.temp(SystemStats.cpuTemp)}`
    }
    Sub { text: SystemStats.cpuName }

    Canvas {
        id: spark

        Layout.fillWidth: true
        Layout.bottomMargin: 6
        implicitHeight: 38

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const data = SystemStats.cpuHistory;
            const w = width, h = height;

            ctx.strokeStyle = Theme.border;
            ctx.lineWidth = 1;
            ctx.beginPath();
            ctx.moveTo(0, h - 0.5);
            ctx.lineTo(w, h - 0.5);
            ctx.stroke();
            if (data.length < 2)
                return;

            // Newest value on the right edge
            const step = w / 59;
            const offset = (60 - data.length) * step;
            ctx.beginPath();
            data.forEach((v, i) => {
                const x = offset + i * step;
                const y = h - 2 - (v / 100) * (h - 4);
                if (i === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            });
            ctx.strokeStyle = Theme.secondary;
            ctx.lineWidth = 1.5;
            ctx.stroke();

            ctx.lineTo(w, h);
            ctx.lineTo(offset, h);
            ctx.closePath();
            ctx.globalAlpha = 0.16;
            ctx.fillStyle = Theme.primary;
            ctx.fill();
            ctx.globalAlpha = 1;
        }

        Connections {
            target: SystemStats
            function onCpuHistoryChanged() {
                spark.requestPaint();
            }
        }
    }

    StatRow {
        name: "gpu"
        value: SystemStats.gpu / 100
        text: `${Math.round(SystemStats.gpu)}%${root.temp(SystemStats.gpuTemp)}`
        visible: SystemStats.gpuName !== "" || SystemStats.gpu > 0
    }
    Sub { text: SystemStats.gpuName }

    StatRow {
        name: "vram"
        value: SystemStats.vramTotal > 0 ? SystemStats.vramUsed / SystemStats.vramTotal : 0
        text: `${SystemStats.vramUsed.toFixed(1)} / ${Math.round(SystemStats.vramTotal)} G`
        visible: SystemStats.vramTotal > 0
    }

    StatRow {
        name: "ram"
        value: SystemStats.memTotal > 0 ? SystemStats.memUsed / SystemStats.memTotal : 0
        text: `${SystemStats.memUsed.toFixed(1)} / ${SystemStats.memTotal.toFixed(1)} G`
    }

    StatRow {
        name: "disk"
        value: SystemStats.diskTotal > 0 ? SystemStats.diskUsed / SystemStats.diskTotal : 0
        text: `${Math.round(SystemStats.diskUsed)} / ${Math.round(SystemStats.diskTotal)} G`
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 6

        Label {
            text: `net ↓ ${SystemStats.formatRate(SystemStats.netDown)}`
            color: Theme.muted
        }
        Item { Layout.fillWidth: true }
        Label {
            text: `↑ ${SystemStats.formatRate(SystemStats.netUp)}`
            color: Theme.muted
        }
    }
}
