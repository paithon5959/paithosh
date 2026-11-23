pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool recording: false
    property bool stopping: false
    property int elapsedSeconds: 0
    property string currentTempPath: ""
    property string lastOutputPath: ""
    property bool recordAudio: true
    property bool recordMic: false
    property string preset: "standard"      // "standard" | "low" | "high" | "custom"
    property string resolution: "native"    // "native" | "1080p" | "720p" | "480p"
    property int fps: 30
    property string saveDir: ""

    readonly property string formattedTime: {
        const mins = Math.floor(elapsedSeconds / 60);
        const secs = elapsedSeconds % 60;
        const mm = mins < 10 ? "0" + mins : String(mins);
        const ss = secs < 10 ? "0" + secs : String(secs);
        return mm + ":" + ss;
    }

    signal finished(string action, string path, string sizeText)
    signal failed(string reason)

    readonly property string _scriptPath: decodeURIComponent(Qt.resolvedUrl("../scripts/screen-record.sh").toString().replace(/^file:\/\//, ""))

    function toggle() {
        if (recording) {
            stop();
        } else if (!stopping && !recordProc.running) {
            start();
        }
    }

    function start() {
        if (recording || recordProc.running) return;
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss");
        currentTempPath = "/tmp/paithosh-rec-" + stamp + ".mp4";
        elapsedSeconds = 0;
        stopping = false;
        recording = true;
        elapsedTimer.restart();
        recordProc.command = [
            _scriptPath, "start", currentTempPath,
            recordAudio ? "1" : "0",
            recordMic ? "1" : "0",
            String(fps),
            resolution,
            preset
        ];
        recordProc.running = true;
        SoundService.playRecordStart();
    }

    function stop() {
        if (!recording && !recordProc.running) return;
        stopping = true;
        recording = false;
        elapsedTimer.stop();
        SoundService.playRecordStop();
        if (currentTempPath !== "") {
            stopProc.command = ["pkill", "-INT", "-f", "wf-recorder.*" + currentTempPath];
            stopProc.running = true;
        }
    }

    Timer {
        id: elapsedTimer
        interval: 1000
        repeat: true
        onTriggered: {
            if (root.recording) {
                root.elapsedSeconds += 1;
            }
        }
    }

    Process {
        id: recordProc
        onExited: (code, status) => {
            root.recording = false;
            root.stopping = false;
            elapsedTimer.stop();

            if (root.currentTempPath !== "") {
                finishProc.buffer = "";
                finishProc.command = [root._scriptPath, "finish", root.currentTempPath, root.saveDir];
                finishProc.running = true;
            }
        }
    }

    Process {
        id: stopProc
    }

    Process {
        id: finishProc
        property string buffer: ""
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { finishProc.buffer += data; }
        }
        onExited: (code, status) => {
            const line = finishProc.buffer.trim();
            if (!line) {
                root.failed("Recording failed");
                return;
            }
            const parts = line.split("|");
            const action = parts[0] || "";
            const path = parts[1] || "";
            const sizeText = parts[2] || "";
            if (action === "SAVED" || action === "COPIED") {
                root.lastOutputPath = path;
                root.finished(action, path, sizeText);
            } else {
                root.failed("Recording empty");
            }
        }
    }
}
