pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string phase: "idle"           // "idle" | "recording" | "stopping" | "finishing"
    readonly property bool recording: phase === "recording"
    readonly property bool stopping: phase === "stopping"
    property int elapsedSeconds: 0
    property string currentTempPath: ""
    property string lastOutputPath: ""
    property bool recordAudio: true
    property bool recordMic: false
    property string preset: "standard"      // "standard" | "low" | "high" | "custom"
    property string resolution: "native"    // "native" | "1080p" | "720p" | "480p"
    property int fps: 30
    property string saveDir: ""

    property int _sessionSeq: 0
    property string _lastError: ""
    property bool _stopRequested: false

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
        if (phase === "recording") {
            stop();
        } else if (phase === "idle" && !recordProc.running && !finishProc.running) {
            start();
        }
    }

    function start() {
        if (phase !== "idle" || recordProc.running || finishProc.running) return;
        _sessionSeq += 1;
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss-zzz");
        currentTempPath = "/tmp/paithosh-rec-" + stamp + "-" + _sessionSeq + ".mp4";
        elapsedSeconds = 0;
        _lastError = "";
        _stopRequested = false;
        phase = "recording";
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
        if (phase !== "recording") return;
        _stopRequested = true;
        phase = "stopping";
        elapsedTimer.stop();
        stopWatchdog.restart();
        SoundService.playRecordStop();
        if (currentTempPath !== "") {
            Quickshell.execDetached([_scriptPath, "stop", currentTempPath]);
        } else if (recordProc.running) {
            recordProc.running = false;
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

    Timer {
        id: stopWatchdog
        interval: 5500
        repeat: false
        onTriggered: {
            if (root.phase !== "stopping") return;
            if (recordProc.running) {
                recordProc.running = false;
            }
            if (!recordProc.running && root.phase === "stopping") {
                root.phase = "idle";
                root.currentTempPath = "";
                root._stopRequested = false;
                root.failed("Recording stop timed out");
            }
        }
    }

    Process {
        id: recordProc
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line.indexOf("ERROR|") === 0) {
                    root._lastError = line.slice(6).trim();
                }
            }
        }
        onExited: (code, status) => {
            stopWatchdog.stop();
            elapsedTimer.stop();

            const finishedPath = root.currentTempPath;
            const wasStopped = root._stopRequested;
            const errText = root._lastError;

            root.currentTempPath = "";
            root._stopRequested = false;
            root._lastError = "";

            if (!wasStopped && (code !== 0 || errText !== "")) {
                root.phase = "idle";
                root.failed(errText !== "" ? errText : "Recording failed");
                return;
            }

            if (finishedPath !== "") {
                root.phase = "finishing";
                finishProc.buffer = "";
                finishProc.command = [root._scriptPath, "finish", finishedPath, root.saveDir];
                finishProc.running = true;
            } else {
                root.phase = "idle";
            }
        }
    }

    Process {
        id: finishProc
        property string buffer: ""
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => { finishProc.buffer += data; }
        }
        onExited: (code, status) => {
            root.phase = "idle";
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
