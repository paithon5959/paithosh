pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property int cpuPct: 18
    property int ramPct: 40
    property int cpuTempC: 49
    readonly property bool overheatAlert: cpuTempC >= 90

    property string memSummary: "Mem: 6.4 / 16 GB"
    property string swapSummary: "Swap: 0.2 / 4 GB"
    property string uptimeText: "Up: 0h 00m"

    property var cpuHistory: [12, 16, 14, 22, 18, 25, 19, 24, 18]
    property var ramHistory: [36, 37, 38, 37, 40, 39, 41, 40, 40]
    property var processList: []
    property bool monitorActive: false

    property real lastIdle: 0
    property real lastTotal: 0

    function setMonitorActive(active) {
        monitorActive = active;
        if (active) {
            statsProc.running = true;
            psProc.running = true;
        }
    }

    function pushPoint(arr, val) {
        const copy = arr.slice(-19);
        copy.push(val);
        return copy;
    }

    Process {
        id: statsProc
        command: [
            "sh", "-c",
            "head -n1 /proc/stat; grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo; cat /proc/uptime; for z in /sys/class/thermal/thermal_zone*/temp; do cat \"$z\" 2>/dev/null; break; done"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                let memTotal = 0, memAvail = 0, swapTotal = 0, swapFree = 0;
                for (let i = 0; i < lines.length; ++i) {
                    const line = lines[i].trim();
                    if (line.startsWith("cpu ")) {
                        const cols = line.split(/\s+/).slice(1).map(Number);
                        const idle = (cols[3] || 0) + (cols[4] || 0);
                        let total = 0;
                        for (let c = 0; c < cols.length; ++c) total += (cols[c] || 0);
                        if (root.lastTotal > 0 && total > root.lastTotal) {
                            const dTotal = total - root.lastTotal;
                            const dIdle = idle - root.lastIdle;
                            const pct = Math.max(0, Math.min(100, Math.round(((dTotal - dIdle) / dTotal) * 100)));
                            root.cpuPct = pct;
                            root.cpuHistory = root.pushPoint(root.cpuHistory, pct);
                        }
                        root.lastIdle = idle;
                        root.lastTotal = total;
                    } else if (line.startsWith("MemTotal:")) {
                        memTotal = parseInt(line.split(/\s+/)[1], 10) || 0;
                    } else if (line.startsWith("MemAvailable:")) {
                        memAvail = parseInt(line.split(/\s+/)[1], 10) || 0;
                    } else if (line.startsWith("SwapTotal:")) {
                        swapTotal = parseInt(line.split(/\s+/)[1], 10) || 0;
                    } else if (line.startsWith("SwapFree:")) {
                        swapFree = parseInt(line.split(/\s+/)[1], 10) || 0;
                    } else if (/^\d+\.\d+\s+\d+\.\d+$/.test(line)) {
                        const secs = Math.floor(parseFloat(line.split(/\s+/)[0]));
                        const h = Math.floor(secs / 3600);
                        const m = Math.floor((secs % 3600) / 60);
                        root.uptimeText = "Up: " + h + "h " + m + "m";
                    } else if (/^\d+$/.test(line)) {
                        const rawT = parseInt(line, 10);
                        root.cpuTempC = rawT > 1000 ? Math.round(rawT / 1000) : rawT;
                    }
                }
                if (memTotal > 0) {
                    const usedGb = (memTotal - memAvail) / (1024 * 1024);
                    const totGb = memTotal / (1024 * 1024);
                    const pct = Math.round(((memTotal - memAvail) / memTotal) * 100);
                    root.ramPct = pct;
                    root.ramHistory = root.pushPoint(root.ramHistory, pct);
                    root.memSummary = "Mem: " + usedGb.toFixed(1) + " / " + totGb.toFixed(0) + " GB";
                }
                if (swapTotal > 0) {
                    const sUsed = (swapTotal - swapFree) / (1024 * 1024);
                    const sTot = swapTotal / (1024 * 1024);
                    root.swapSummary = "Swap: " + sUsed.toFixed(1) + " / " + sTot.toFixed(0) + " GB";
                } else {
                    root.swapSummary = "Swap: 0 / 0 GB";
                }
            }
        }
    }

    Process {
        id: psProc
        command: ["ps", "-eo", "pid=,comm=,%cpu=,rss=", "--sort=-%cpu"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const out = [];
                for (let i = 0; i < lines.length && out.length < 25; ++i) {
                    const m = lines[i].trim().match(/^(\d+)\s+(\S+)\s+([\d.]+)\s+(\d+)$/);
                    if (!m) continue;
                    const pid = parseInt(m[1], 10);
                    const name = m[2];
                    const cpu = m[3];
                    const rssKb = parseInt(m[4], 10);
                    const memStr = rssKb >= 1048576
                        ? (rssKb / 1048576).toFixed(1) + " GB"
                        : Math.round(rssKb / 1024) + " MB";
                    out.push({ pid: pid, name: name, cpu: cpu, memText: memStr });
                }
                root.processList = out;
            }
        }
    }

    function killProcess(pid) {
        Quickshell.execDetached(["kill", "-TERM", String(pid)]);
        const next = [];
        for (let i = 0; i < processList.length; ++i) {
            if (processList[i].pid !== pid) next.push(processList[i]);
        }
        processList = next;
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            statsProc.running = true;
            if (root.monitorActive) psProc.running = true;
        }
    }

    Component.onCompleted: statsProc.running = true
}
