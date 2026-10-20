pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Screen recording with wf-recorder, started from the screenshot tool (Super+Shift+R,
// `qs ipc call screenshot record`): the same picker, then the region, window or screen is
// recorded until you stop it, from the bar (● rec) or with the same key again. Videos go
// to ~/Videos/recordings (your XDG videos folder); a notification offers open, folder,
// copy (the file, for pasting into chats) and delete.
Singleton {
    id: root

    property bool recording: false
    property bool stopping: false
    property real startedAt: 0
    property real now: Date.now()
    readonly property int seconds: recording ? Math.max(0, Math.floor((now - startedAt) / 1000)) : 0
    readonly property string elapsed: `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`

    property string videosDir: `${Quickshell.env("HOME")}/Videos`
    readonly property string folder: `${videosDir}/recordings`
    property string file: ""

    // args as grim takes them: ["-g", "x,y wxh"] or ["-o", "<monitor>"]
    function start(args) {
        if (recording || proc.running)
            return;
        const d = new Date();
        const p = n => String(n).padStart(2, "0");
        file = `${folder}/recording-${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}.mp4`;
        const audio = Config.recordAudio ? ["-a"] : [];
        proc.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && f=$1 && shift && exec wf-recorder -f "$f" "$@"', "frame-record", file]
            .concat(args).concat(audio);
        proc.running = true;
        startedAt = Date.now();
        now = startedAt;
        recording = true;
        stopping = false;
    }

    // wf-recorder finishes the file on SIGINT, as with Ctrl+C
    function stop() {
        if (!recording || stopping)
            return;
        stopping = true;
        proc.signal(2);
    }

    Process {
        id: proc
        stderr: StdioCollector {
            id: errors
        }
        onExited: code => {
            const file = root.file;
            const name = file.slice(file.lastIndexOf("/") + 1);
            const wasStopped = root.stopping;
            root.now = Date.now();
            // Read before recording turns false, which sets the clock back to 0:00
            const length = root.elapsed;
            root.recording = false;
            root.stopping = false;
            // wf-recorder ends with 0 or the signal's code when it was stopped
            if (!wasStopped && code !== 0) {
                Notifications.push({ app: "recording", glyph: "✗", title: "recording failed",
                    body: errors.text.trim().split("\n").pop() || "is wf-recorder installed?" });
                return;
            }
            Notifications.push({
                app: "recording",
                glyph: "●",
                title: `recording saved · ${length}`,
                body: name,
                actions: [
                    { id: "open", label: "open", style: "ok" },
                    { id: "folder", label: "folder", style: "" },
                    { id: "copy", label: "copy", style: "" },
                    { id: "delete", label: "delete", style: "" }
                ],
                onAction: id => {
                    if (id === "open")
                        Quickshell.execDetached(["xdg-open", file]);
                    else if (id === "folder")
                        Quickshell.execDetached(["xdg-open", root.folder]);
                    else if (id === "copy")
                        // As a file, so chat apps and file managers take the video itself
                        Quickshell.execDetached(["sh", "-c", 'printf "file://%s\\n" "$1" | wl-copy --type text/uri-list', "frame-record", file]);
                    else if (id === "delete")
                        Quickshell.execDetached(["rm", "-f", file]);
                }
            });
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.now = Date.now()
    }

    Process {
        command: ["xdg-user-dir", "VIDEOS"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const dir = this.text.trim();
                if (dir !== "")
                    root.videosDir = dir;
            }
        }
    }
}
