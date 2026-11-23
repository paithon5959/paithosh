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

    property string memSummary: "Mem: -- / -- GB"
    property string memDetail: "-- / -- GB"
    property string swapSummary: "Swap: -- / -- GB"
    property string uptimeText: "Up: 0h 0m"

    // System & Hardware Specs
    property string osName: "Linux"
    property string arch: "x86_64"
    property string kernel: ""
    property string hostname: "localhost"
    property string hyprVersion: "Hyprland (Wayland)"
    property string shellName: "zsh"
    property string cpuModel: "Processor"
    property string cpuCores: ""
    property string ramTotalGb: "-- GB"
    property string gpuName: "Integrated Graphics"
    property string storageTotal: "-- GB"
    property string storageDetail: ""

    property var cpuHistory: [12, 16, 14, 22, 18, 25, 19, 24, 18]
    property var ramHistory: [36, 37, 38, 37, 40, 39, 41, 40, 40]
    property var processList: []
    property var appList: []
    property var pidStatsMap: ({})
    property var pidChildrenMap: ({})

    function formatMemKb(kb) {
        return kb >= 1048576
            ? (kb / 1048576).toFixed(1) + " GB"
            : Math.round(kb / 1024) + " MB";
    }

    function getTreeStats(rootPid) {
        if (!rootPid || !pidStatsMap[rootPid]) return null;
        let totalCpu = 0;
        let totalRssKb = 0;
        const queue = [rootPid];
        const visited = {};
        while (queue.length > 0) {
            const p = queue.shift();
            if (visited[p]) continue;
            visited[p] = true;
            const st = pidStatsMap[p];
            if (st) {
                totalCpu += st.cpuVal;
                totalRssKb += st.rssKb;
            }
            const children = pidChildrenMap[p];
            if (children) {
                for (let i = 0; i < children.length; ++i) {
                    if (!visited[children[i]]) queue.push(children[i]);
                }
            }
        }
        return {
            cpu: totalCpu.toFixed(1),
            memText: formatMemKb(totalRssKb)
        };
    }
    property bool monitorActive: false

    property real lastIdle: 0
    property real lastTotal: 0

    function setMonitorActive(active) {
        monitorActive = active;
        if (active) {
            statsProc.running = true;
            psProc.running = true;
            appsProc.running = true;
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
                    root.ramTotalGb = totGb.toFixed(0) + " GB RAM";
                    root.memDetail = usedGb.toFixed(1) + " / " + totGb.toFixed(0) + " GB";
                    root.memSummary = "Mem: " + root.memDetail;
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
        command: ["ps", "-eo", "pid=,ppid=,%cpu=,rss=,comm=", "--sort=-%cpu"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const out = [];
                const pmap = {};
                const cmap = {};
                for (let i = 0; i < lines.length; ++i) {
                    const m = lines[i].trim().match(/^(\d+)\s+(\d+)\s+([\d.]+)\s+(\d+)\s+(.+)$/);
                    if (!m) continue;
                    const pid = parseInt(m[1], 10);
                    const ppid = parseInt(m[2], 10);
                    const cpu = m[3];
                    const rssKb = parseInt(m[4], 10);
                    const name = m[5].trim();
                    const memStr = root.formatMemKb(rssKb);
                    pmap[pid] = { cpuVal: parseFloat(cpu) || 0, rssKb: rssKb, memText: memStr };
                    if (!cmap[ppid]) cmap[ppid] = [];
                    cmap[ppid].push(pid);
                    if (out.length < 25) {
                        out.push({ pid: pid, name: name, cpu: cpu, memText: memStr });
                    }
                }
                root.pidStatsMap = pmap;
                root.pidChildrenMap = cmap;
                root.processList = out;
                if (root.appList.length > 0) {
                    const updatedApps = [];
                    for (let i = 0; i < root.appList.length; ++i) {
                        const a = root.appList[i];
                        const st = root.getTreeStats(a.pid);
                        updatedApps.push({
                            pid: a.pid,
                            name: a.name,
                            title: a.title,
                            address: a.address,
                            workspace: a.workspace,
                            cpu: st ? st.cpu : a.cpu,
                            memText: st ? st.memText : a.memText
                        });
                    }
                    root.appList = updatedApps;
                }
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

    Process {
        id: appsProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const clients = JSON.parse(text);
                    const out = [];
                    for (let i = 0; i < clients.length; ++i) {
                        const c = clients[i];
                        if (!c || !c.mapped) continue;
                        const pid = c.pid || 0;
                        const st = root.getTreeStats(pid);
                        out.push({
                            pid: pid,
                            name: c["class"] || c.initialClass || "App",
                            title: c.title || "",
                            address: c.address || "",
                            workspace: c.workspace ? c.workspace.id : 0,
                            cpu: st ? st.cpu : "0.0",
                            memText: st ? st.memText : "--"
                        });
                    }
                    root.appList = out;
                } catch (e) {
                    // ignore malformed hyprctl output
                }
            }
        }
    }

    function focusApp(address) {
        if (!address) return;
        Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + address]);
    }

    function closeApp(address, pid) {
        if (address) {
            Quickshell.execDetached(["hyprctl", "dispatch", "closewindow", "address:" + address]);
        } else if (pid > 0) {
            Quickshell.execDetached(["kill", "-TERM", String(pid)]);
        }
        const next = [];
        for (let i = 0; i < appList.length; ++i) {
            if (appList[i].address !== address) next.push(appList[i]);
        }
        appList = next;
    }

    Process {
        id: specsProc
        command: [
            "sh", "-c",
            "printf 'OS=%s\\n' \"$(. /etc/os-release 2>/dev/null && printf '%s' \"$PRETTY_NAME\")\"; " +
            "printf 'KERNEL=%s\\n' \"$(uname -r)\"; " +
            "printf 'ARCH=%s\\n' \"$(uname -m)\"; " +
            "printf 'HOST=%s\\n' \"$(uname -n)\"; " +
            "printf 'SHELL=%s\\n' \"$(basename \"${SHELL:-sh}\")\"; " +
            "printf 'HYPR=%s\\n' \"$(hyprctl version 2>/dev/null | head -n1 | sed 's/Hyprland \\([^, ]*\\).*/Hyprland \\1/')\"; " +
            "printf 'CPU=%s\\n' \"$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')\"; " +
            "printf 'THREADS=%s\\n' \"$(nproc 2>/dev/null || echo 1)\"; " +
            "printf 'CORES=%s\\n' \"$(grep -m1 'cpu cores' /proc/cpuinfo | cut -d: -f2- | tr -d ' ')\"; " +
            "printf 'GPU=%s\\n' \"$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -n1 | cut -d: -f3- | sed 's/^ *//; s/ (rev .*//')\"; " +
            "printf 'DF=%s\\n' \"$(df -hT / 2>/dev/null | tail -n1)\""
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                let cores = "";
                let threads = "";
                for (let i = 0; i < lines.length; ++i) {
                    const line = lines[i];
                    const eq = line.indexOf("=");
                    if (eq === -1) continue;
                    const k = line.slice(0, eq);
                    const v = line.slice(eq + 1).trim();
                    if (!v) continue;
                    if (k === "OS") root.osName = v;
                    else if (k === "KERNEL") root.kernel = v;
                    else if (k === "ARCH") root.arch = v;
                    else if (k === "HOST") root.hostname = v;
                    else if (k === "SHELL") root.shellName = v;
                    else if (k === "HYPR") root.hyprVersion = v + " (Wayland)";
                    else if (k === "CPU") root.cpuModel = v.replace(/\(R\)|\(TM\)|CPU @.*/g, "").replace(/\s+/g, " ").trim();
                    else if (k === "CORES") cores = v;
                    else if (k === "THREADS") threads = v;
                    else if (k === "GPU") root.gpuName = v.replace(/Corporation |Integrated Graphics Controller/g, "").replace(/\s+/g, " ").trim();
                    else if (k === "DF") {
                        const cols = v.split(/\s+/);
                        // Filesystem Type Size Used Avail Use% Mounted
                        if (cols.length >= 6) {
                            const fs = cols[1];
                            const size = cols[2];
                            const used = cols[3];
                            const avail = cols[4];
                            const pct = cols[5];
                            root.storageTotal = size + " (" + fs + ")";
                            root.storageDetail = used + " used • " + avail + " free (" + pct + ")";
                        }
                    }
                }
                if (cores && threads) root.cpuCores = cores + " Cores / " + threads + " Threads";
                else if (threads) root.cpuCores = threads + " Threads";
            }
        }
    }

    function refreshSpecs() {
        specsProc.running = true;
        statsProc.running = true;
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            statsProc.running = true;
            if (root.monitorActive) {
                psProc.running = true;
                appsProc.running = true;
            }
        }
    }

    Component.onCompleted: {
        statsProc.running = true;
        specsProc.running = true;
    }
}
