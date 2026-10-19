pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// CPU, GPU, memory, disk and network numbers for the bar and the control center.
// Reads /proc and /sys once a second. GPU values come from amdgpu sysfs files.
Singleton {
    id: root

    property real cpu: 0            // percent
    property real cpuTemp: 0        // °C
    property string cpuName: ""
    property var cpuHistory: []     // last 60 cpu values, oldest first
    property real gpu: 0            // percent
    property real gpuTemp: 0
    property string gpuName: ""
    property real vramUsed: 0       // GiB
    property real vramTotal: 0
    property real memUsed: 0        // GiB
    property real memTotal: 0
    property real diskUsed: 0       // GiB, root filesystem
    property real diskTotal: 0
    property real netDown: 0        // bytes per second, all interfaces except lo
    property real netUp: 0

    // sysfs paths found at startup
    property string cpuTempPath: ""
    property string gpuDir: ""
    property string gpuTempPath: ""

    property var lastCpu: null
    property var lastNet: null
    property real lastNetTime: 0

    readonly property real gib: 1024 * 1024 * 1024

    function readNumber(view) {
        const n = Number(view.text().trim());
        return isNaN(n) ? 0 : n;
    }

    function parseStat(text) {
        const parts = text.split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
        const idle = parts[3] + (parts[4] ?? 0);
        const total = parts.reduce((a, b) => a + b, 0);
        if (lastCpu) {
            const dTotal = total - lastCpu.total;
            const dIdle = idle - lastCpu.idle;
            if (dTotal > 0)
                cpu = Math.max(0, Math.min(100, 100 * (1 - dIdle / dTotal)));
        }
        lastCpu = { total, idle };
        cpuHistory = cpuHistory.concat([cpu]).slice(-60);
    }

    function parseMeminfo(text) {
        const get = key => Number((new RegExp(`^${key}:\\s+(\\d+)`, "m").exec(text) ?? [0, 0])[1]) * 1024;
        memTotal = get("MemTotal") / gib;
        memUsed = (get("MemTotal") - get("MemAvailable")) / gib;
    }

    function parseNet(text) {
        let rx = 0, tx = 0;
        for (const line of text.split("\n").slice(2)) {
            const [iface, data] = line.split(":");
            if (!data || iface.trim() === "lo")
                continue;
            const cols = data.trim().split(/\s+/).map(Number);
            rx += cols[0];
            tx += cols[8];
        }
        const now = Date.now();
        if (lastNet && now > lastNetTime) {
            const seconds = (now - lastNetTime) / 1000;
            netDown = Math.max(0, (rx - lastNet.rx) / seconds);
            netUp = Math.max(0, (tx - lastNet.tx) / seconds);
        }
        lastNet = { rx, tx };
        lastNetTime = now;
    }

    // 2400000 → "2.4 MB/s"
    function formatRate(bytes) {
        if (bytes >= 1e6)
            return `${(bytes / 1e6).toFixed(1)} MB/s`;
        if (bytes >= 1e3)
            return `${Math.round(bytes / 1e3)} KB/s`;
        return `${Math.round(bytes)} B/s`;
    }

    FileView { id: stat; path: "/proc/stat"; onLoaded: root.parseStat(text()) }
    FileView { id: meminfo; path: "/proc/meminfo"; onLoaded: root.parseMeminfo(text()) }
    FileView { id: netdev; path: "/proc/net/dev"; onLoaded: root.parseNet(text()) }
    FileView { id: cpuTempFile; printErrors: false; path: root.cpuTempPath; onLoaded: root.cpuTemp = root.readNumber(this) / 1000 }
    FileView { id: gpuBusy; printErrors: false; path: root.gpuDir !== "" ? `${root.gpuDir}/gpu_busy_percent` : ""; onLoaded: root.gpu = root.readNumber(this) }
    FileView { id: gpuTempFile; printErrors: false; path: root.gpuTempPath; onLoaded: root.gpuTemp = root.readNumber(this) / 1000 }
    FileView { id: vramUsedFile; printErrors: false; path: root.gpuDir !== "" ? `${root.gpuDir}/mem_info_vram_used` : ""; onLoaded: root.vramUsed = root.readNumber(this) / root.gib }
    FileView { id: vramTotalFile; printErrors: false; path: root.gpuDir !== "" ? `${root.gpuDir}/mem_info_vram_total` : ""; onLoaded: root.vramTotal = root.readNumber(this) / root.gib }

    // Finds the hwmon/drm paths and the hardware names once
    Process {
        running: true
        command: ["sh", "-c", `
            for h in /sys/class/hwmon/hwmon*; do
                case "$(cat "$h/name" 2>/dev/null)" in
                    k10temp|zenpower|coretemp) echo "cputemp $h/temp1_input" ;;
                    amdgpu) echo "gputemp $h/temp1_input" ;;
                esac
            done
            for d in /sys/class/drm/card*/device; do
                [ -f "$d/gpu_busy_percent" ] && { echo "gpu $d"; break; }
            done
            echo "cpuname $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2-)"
            echo "gpuname $(lspci 2>/dev/null | grep -iE 'vga|3d controller' | head -1 | cut -d: -f3-)"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of this.text.split("\n")) {
                    const space = line.indexOf(" ");
                    const key = line.slice(0, space);
                    const value = line.slice(space + 1).trim();
                    if (key === "cputemp" && root.cpuTempPath === "")
                        root.cpuTempPath = value;
                    else if (key === "gputemp" && root.gpuTempPath === "")
                        root.gpuTempPath = value;
                    else if (key === "gpu")
                        root.gpuDir = value;
                    else if (key === "cpuname")
                        root.cpuName = value.replace(/\s+\d+-Core Processor$/, "").replace(/\s+/g, " ");
                    else if (key === "gpuname") {
                        // "… Navi 32 [Radeon RX 7700 XT / 7800 XT] (rev c8)" → "Radeon RX 7700 XT / 7800 XT"
                        const bracket = /\[([^\]]*(Radeon|GeForce|Arc)[^\]]*)\]/.exec(value);
                        root.gpuName = bracket ? bracket[1] : value;
                    }
                }
            }
        }
    }

    Process {
        id: df
        command: ["df", "-B1", "--output=used,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const cols = (this.text.trim().split("\n")[1] ?? "").trim().split(/\s+/).map(Number);
                if (cols.length === 2) {
                    root.diskUsed = cols[0] / root.gib;
                    root.diskTotal = cols[1] / root.gib;
                }
            }
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload();
            meminfo.reload();
            netdev.reload();
            if (root.cpuTempPath !== "")
                cpuTempFile.reload();
            if (root.gpuDir !== "") {
                gpuBusy.reload();
                vramUsedFile.reload();
                vramTotalFile.reload();
            }
            if (root.gpuTempPath !== "")
                gpuTempFile.reload();
        }
    }

    Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: df.running = true
    }
}
