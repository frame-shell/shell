pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Front end for ~/.local/bin/frame-keyboard (keyboard package): lighting, Fn keys and
// per-key colors of the AULA F75. Key ids are physical keys named like a US board
// ("y" is the key labelled Z on QWERTZ); actions typed by hand are read as QWERTZ.
//
// Nothing reaches the keyboard while `live` is false: frame-keyboard then only prints the
// packets it would send (shown in `log`) and answers reads with placeholder data.
Singleton {
    id: root

    // Hyprland's environment usually has no ~/.local/bin in PATH
    readonly property string tool: `${Quickshell.env("HOME")}/.local/bin/frame-keyboard`
    property bool available: true
    // Starts from Config.keyboardLive; the switch in the app changes it until the next restart
    property bool live: Config.keyboardLive
    readonly property bool busy: queue.length > 0 || proc.job !== null

    property var devices: []
    property var effects: []
    property var actions: ({ media: [], lighting: [], mods: [], keys: [], defaults: {} })
    // frame-keyboard info --json: { dry, model, id, node, effect, effects: { name: { brightness,
    //   speed, slot } }, layer, keys: { id: { bytes, text } }, colors: { id: "#rrggbb" } }
    property var info: null
    property string layer: "fn1"
    // Output of the last write: in a dry run the packets that would have been sent
    property string log: ""
    property string error: ""

    readonly property bool connected: devices.some(d => d.config)
    readonly property bool dongleOnly: !connected && devices.some(d => d.kind === "dongle")

    property var queue: []

    function refresh() {
        run(["list", "--json"], "devices");
        if (effects.length === 0) {
            run(["effects", "--json"], "effects");
            run(["actions", "--json"], "actions");
        }
        readInfo();
    }

    function readInfo() {
        run(device(["info", "--json", "--layout", "de", "--layer", layer]), "info");
    }

    function setLive(on) {
        live = on;
        readInfo();
    }

    function setLayer(name) {
        layer = name;
        readInfo();
    }

    // speed < 0 and color "" leave those as they are
    function effect(name, brightness, speed, color) {
        const args = ["effect", name, "-b", String(brightness)];
        if (speed >= 0)
            args.push("-s", String(speed));
        if (color !== "")
            args.push("-c", color);
        write(args);
    }

    // items: ["f1=play", "q=ctrl+z", …] with physical key ids on the current layer
    function assign(items) {
        write(["fn", "--layer", layer, "--layout", "us", "--action-layout", "de", "--allow-knob"].concat(items));
    }

    // Back to the factory Fn action (fn1 only)
    function resetKeys(ids) {
        write(["fn", "--reset", "--layer", "fn1", "--layout", "us", "--allow-knob"].concat(ids));
    }

    // colors: { id: "#rrggbb" } for every key that should change
    function paint(colors, brightness) {
        const items = Object.keys(colors).map(id => `${id}=${colors[id]}`);
        if (items.length > 0)
            write(["colors", "--layout", "us", "-b", String(brightness)].concat(items));
    }

    function style(name, brightness) {
        write(["style", name, "-b", String(brightness)]);
    }

    function write(args) {
        run(device(args), "write");
        readInfo();
    }

    function device(args) {
        return live ? args.concat(["--live"]) : args;
    }

    function run(args, kind) {
        queue = queue.concat([{ args: args, kind: kind }]);
        next();
    }

    function next() {
        if (proc.running || proc.job !== null || queue.length === 0)
            return;
        proc.job = queue[0];
        queue = queue.slice(1);
        proc.command = [tool].concat(proc.job.args);
        proc.running = true;
    }

    // The output arrives after the exit signal, so the next command only starts once the
    // output of this one is read (as in Wallpapers)
    Process {
        id: proc

        property var job: null

        onStarted: root.error = ""

        stdout: StdioCollector {
            onStreamFinished: {
                const job = proc.job;
                const text = this.text;
                if (job.kind === "write") {
                    root.log = `$ frame-keyboard ${job.args.join(" ")}\n${text}`;
                } else if (text.trim() !== "") {
                    try {
                        const data = JSON.parse(text);
                        if (job.kind === "devices")
                            root.devices = data;
                        else if (job.kind === "effects")
                            root.effects = data;
                        else if (job.kind === "actions")
                            root.actions = data;
                        else if (job.kind === "info")
                            root.info = data;
                    } catch (e) {
                        console.warn(`keyboard: ${job.kind}: ${e}`);
                    }
                }
                proc.job = null;
                Qt.callLater(root.next);
            }
        }

        // frame-keyboard ends a failed command with "frame-keyboard: <reason>"
        stderr: StdioCollector {
            onStreamFinished: {
                const failure = this.text.trim().split("\n").filter(l => l.startsWith("frame-keyboard: ")).pop() ?? "";
                if (failure !== "")
                    root.error = failure.slice("frame-keyboard: ".length);
            }
        }
    }

    // The keyboard package is not linked into ~/.local/bin (yet)
    FileView {
        path: root.tool
        printErrors: false
        onLoadFailed: root.available = false
        onLoaded: root.available = true
    }
}
