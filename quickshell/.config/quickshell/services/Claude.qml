pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Short answers from Claude for the launcher (c), through the Claude Code CLI
// (`claude -p`, signed in as you). The mode only exists when `claude` is installed and
// Config.claudeEnabled is on. Nothing is sent while typing, only on Enter.
// It runs in its own empty folder, so no project's CLAUDE.md or files come along.
Singleton {
    id: root

    property bool installed: false
    readonly property bool available: installed && Config.claudeEnabled

    property string question: ""
    property string answer: ""
    property string error: ""
    readonly property bool busy: proc.running

    readonly property string workDir: `${Quickshell.env("HOME")}/.local/state/frameshell/claude`
    readonly property string instructions: "You answer quick questions typed into a desktop launcher. "
        + "Reply in at most three short sentences of plain text, no markdown, no lists. "
        + "Use the language of the question."

    function ask(text) {
        const q = text.trim();
        if (q === "" || (q === question && (busy || answer !== "")))
            return;
        proc.running = false;
        question = q;
        answer = "";
        error = "";
        const model = Config.claudeModel !== "" ? ["--model", Config.claudeModel] : [];
        proc.asked = q;
        // First line of the output: exit code; the rest: the answer or the error
        proc.command = ["sh", "-c", 'mkdir -p "$0" && cd "$0" || exit 1; out=$(claude "$@" 2>&1); printf "%s\\n%s" "$?" "$out"',
            workDir, "-p", "--append-system-prompt", instructions].concat(model).concat([q]);
        proc.running = true;
    }

    Process {
        id: proc
        property string asked: ""
        stdout: StdioCollector {
            onStreamFinished: {
                if (proc.asked !== root.question)
                    return;
                const newline = text.indexOf("\n");
                const code = newline < 0 ? text.trim() : text.slice(0, newline);
                const out = newline < 0 ? "" : text.slice(newline + 1).trim();
                if (code === "0" && out !== "")
                    root.answer = out;
                else
                    root.error = out.split("\n").pop() || `claude stopped with code ${code || "?"}`;
            }
        }
    }

    Process {
        command: ["sh", "-c", "command -v claude"]
        running: true
        onExited: code => root.installed = code === 0
    }
}
