pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string storageScript: Quickshell.shellDir + "/scripts/paithosh-storage.py"
    readonly property string shellProjectRoot: Quickshell.shellDir.replace(/\/shell\/?$/, "")
    readonly property string settingsPath: (Quickshell.env("HOME") || "/tmp") + "/.config/paithosh/storage-settings.json"

    property bool _settingsLoaded: false
    property bool scanning: false
    property bool cleaning: false
    property string activeOpText: ""
    property bool hasScanned: false
    property double _lastScanMs: 0
    property string lastScanText: "Never"
    property string lastResultText: ""
    property bool lastResultOk: true
    property string lastError: ""

    signal statusEventRequested(string msg, string kind, bool autoHide)

    // Configurable Shredder thresholds
    property int staleDays: 30
    property int minSizeMb: 50

    // Disk & category metrics
    property string mountPoint: "/"
    property string fsType: "btrfs"
    property double totalBytes: 0
    property double usedBytes: 0
    property double freeBytes: 0
    property real usedPct: 0
    property double shellBytes: 0
    property double userCacheBytes: 0
    property double systemCacheBytes: 0
    property var categories: []
    property var userFolders: []
    property var staleFiles: []
    property double staleTotalBytes: 0

    // Root sudo prompt state (consumed by SettingsView sudoAuthOverlay)
    property bool authPromptOpen: false
    property string authPromptTitle: "Root Password Required"
    property string authPromptDesc: "Enter your sudo password to clean system package caches and logs."
    property string authPromptActionLabel: "Clean System Cache"
    property string authPromptError: ""
    property var _pendingPrivCmd: []
    property var _pendingPrivCallback: null

    Component {
        id: procComp
        Process {
            id: proc
            property var cb: null
            property string outBuf: ""
            property string errBuf: ""
            property string pendingStdin: ""

            onRunningChanged: {
                if (running && pendingStdin !== "") {
                    proc.write(pendingStdin);
                    proc.pendingStdin = "";
                    proc.stdinEnabled = false;
                }
            }
            stdout: SplitParser {
                onRead: data => {
                    proc.outBuf += (proc.outBuf !== "" ? "\n" : "") + data;
                }
            }
            stderr: SplitParser {
                onRead: data => {
                    proc.errBuf += (proc.errBuf !== "" ? "\n" : "") + data;
                }
            }
            onExited: (exitCode) => {
                if (cb) cb(exitCode === 0, proc.outBuf, proc.errBuf, exitCode);
                destroy();
            }
        }
    }

    function runCmd(cmdArray, cb, stdinData) {
        const hasStdin = typeof stdinData === "string" && stdinData.length > 0;
        procComp.createObject(root, {
            command: cmdArray,
            stdinEnabled: hasStdin,
            pendingStdin: hasStdin ? stdinData : "",
            cb: cb || null,
            running: true
        });
    }

    function runSudoCmd(password, argv, cb) {
        procComp.createObject(root, {
            command: ["sudo", "-S", "-k", "-p", ""].concat(argv),
            stdinEnabled: true,
            pendingStdin: password + "\n",
            cb: cb || null,
            running: true
        });
    }

    function extractResultJson(outText) {
        const lines = (outText || "").split("\n");
        for (let i = lines.length - 1; i >= 0; --i) {
            const ln = lines[i].trim();
            if (ln.startsWith("RESULT|")) {
                try { return JSON.parse(ln.slice(7)); } catch (e) {}
            } else if (ln.startsWith("{")) {
                try { return JSON.parse(ln); } catch (e) {}
            }
        }
        return null;
    }

    function formatBytes(bytes) {
        const b = Number(bytes || 0);
        if (isNaN(b) || b <= 0) return "0 B";
        if (b < 1024) return Math.round(b) + " B";
        if (b < 1048576) return (b / 1024).toFixed(1) + " KB";
        if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB";
        return (b / 1073741824).toFixed(1) + " GB";
    }

    Component.onCompleted: loadSettings()

    function loadSettings() {
        runCmd(["sh", "-c", 'cat "$1" 2>/dev/null || true', "sh", settingsPath], (ok, out) => {
            try {
                const raw = (out || "").trim();
                if (raw !== "") {
                    const parsed = JSON.parse(raw);
                    if (parsed && typeof parsed === "object") {
                        const d = parseInt(parsed.staleDays, 10);
                        if (!isNaN(d) && d >= 1 && d <= 3650) root.staleDays = d;
                        const m = parseInt(parsed.minSizeMb, 10);
                        if (!isNaN(m) && m >= 1 && m <= 102400) root.minSizeMb = m;
                    }
                }
            } catch (e) {}
            root._settingsLoaded = true;
        });
    }

    function saveSettings() {
        if (!_settingsLoaded) return;
        const payload = JSON.stringify({
            staleDays: root.staleDays,
            minSizeMb: root.minSizeMb
        }, null, 2);
        runCmd([
            "python3", "-c",
            "import os,sys,tempfile; p=sys.argv[1]; d=os.path.dirname(p); os.makedirs(d, exist_ok=True); fd,tp=tempfile.mkstemp(dir=d); os.write(fd, sys.argv[2].encode()); os.close(fd); os.replace(tp, p)",
            settingsPath, payload
        ], null);
    }

    function setStaleDays(days) {
        const d = Math.max(1, Math.min(3650, parseInt(days, 10) || 30));
        if (d === root.staleDays) return;
        root.staleDays = d;
        saveSettings();
        scan(true);
    }

    function setMinSizeMb(mb) {
        const m = Math.max(1, Math.min(102400, parseInt(mb, 10) || 50));
        if (m === root.minSizeMb) return;
        root.minSizeMb = m;
        saveSettings();
        scan(true);
    }

    function scanIfStale() {
        const now = Date.now();
        if (!hasScanned || (now - _lastScanMs) > 60000) {
            scan(false);
        }
    }

    function scan(force) {
        if (scanning) return;
        if (!force && hasScanned && (Date.now() - _lastScanMs) < 5000) return;
        scanning = true;
        if (!cleaning) activeOpText = "Scanning storage...";
        lastError = "";
        runCmd([
            "python3", storageScript, "scan",
            "--stale-days", String(staleDays),
            "--min-mb", String(minSizeMb),
            "--shell-dir", shellProjectRoot
        ], (ok, out, err) => {
            scanning = false;
            if (!cleaning) activeOpText = "";
            const res = extractResultJson(out);
            if (!ok || !res || !res.ok) {
                lastError = (res && res.error) ? res.error : (err || "Storage scan failed");
                statusEventRequested(lastError, "danger", true);
                return;
            }
            mountPoint = res.mountPoint || "/";
            fsType = res.fsType || "linux";
            totalBytes = Number(res.totalBytes || 0);
            usedBytes = Number(res.usedBytes || 0);
            freeBytes = Number(res.freeBytes || 0);
            usedPct = Number(res.usedPct || 0);
            shellBytes = Number(res.shellBytes || 0);
            userCacheBytes = Number(res.userCacheBytes || 0);
            systemCacheBytes = Number(res.systemCacheBytes || 0);
            categories = Array.isArray(res.categories) ? res.categories : [];
            userFolders = Array.isArray(res.userFolders) ? res.userFolders : [];
            staleFiles = Array.isArray(res.staleFiles) ? res.staleFiles : [];
            staleTotalBytes = Number(res.staleTotalBytes || 0);
            hasScanned = true;
            _lastScanMs = Date.now();
            const dt = new Date();
            const hh = String(dt.getHours()).padStart(2, "0");
            const mm = String(dt.getMinutes()).padStart(2, "0");
            const ss = String(dt.getSeconds()).padStart(2, "0");
            lastScanText = hh + ":" + mm + ":" + ss;
        });
    }

    function cleanCache(scope) {
        if (cleaning) return;
        if (scope === "system") {
            _pendingPrivCmd = ["python3", storageScript, "clean-cache", "--scope", "system"];
            _pendingPrivCallback = (ok, res, err) => {
                cleaning = false;
                activeOpText = "";
                if (!ok || !res || !res.ok) {
                    lastResultOk = false;
                    lastResultText = (res && res.error) ? res.error : (err || "System cache cleanup cancelled or failed");
                    statusEventRequested(lastResultText, "danger", true);
                    return;
                }
                lastResultOk = true;
                lastResultText = "Cleaned system cache (" + formatBytes(res.freedBytes) + " freed)";
                statusEventRequested(lastResultText, "ok", true);
                scan(true);
            };
            authPromptTitle = "Root Password Required";
            authPromptDesc = "Enter your sudo password to clean system package caches, /var/tmp, and old journal logs.";
            authPromptActionLabel = "Clean System Cache";
            authPromptError = "";
            authPromptOpen = true;
            return;
        }

        cleaning = true;
        activeOpText = "Cleaning user cache...";
        lastError = "";
        runCmd(["python3", storageScript, "clean-cache", "--scope", "user"], (ok, out, err) => {
            cleaning = false;
            activeOpText = "";
            const res = extractResultJson(out);
            if (!ok || !res || !res.ok) {
                lastResultOk = false;
                lastResultText = (res && res.error) ? res.error : (err || "User cache cleanup failed");
                statusEventRequested(lastResultText, "danger", true);
                return;
            }
            lastResultOk = true;
            lastResultText = "Cleaned user cache & Trash (" + formatBytes(res.freedBytes) + " freed)";
            statusEventRequested(lastResultText, "ok", true);
            scan(true);
        });
    }

    function cancelAuthPrompt() {
        authPromptOpen = false;
        authPromptError = "";
        const cb = _pendingPrivCallback;
        _pendingPrivCmd = [];
        _pendingPrivCallback = null;
        if (cb) cb(false, null, "Authentication cancelled");
    }

    function submitAuthPassword(password) {
        if (!password || password.length === 0) {
            authPromptError = "Password cannot be empty";
            return;
        }
        const argv = _pendingPrivCmd.slice();
        const cb = _pendingPrivCallback;
        authPromptOpen = false;
        authPromptError = "";
        cleaning = true;
        activeOpText = "Cleaning system cache...";

        runSudoCmd(password, argv, (ok, out, err) => {
            const isBadPwd = !ok && /incorrect password|sorry, try again|authentication failure/i.test(err || "");
            if (isBadPwd) {
                cleaning = false;
                activeOpText = "";
                authPromptError = "Incorrect sudo password. Please try again.";
                authPromptOpen = true;
                return;
            }
            _pendingPrivCmd = [];
            _pendingPrivCallback = null;
            const res = extractResultJson(out);
            if (cb) cb(ok, res, err);
        });
    }

    function shredFiles(paths, permanent) {
        if (cleaning || !paths || paths.length === 0) return;
        cleaning = true;
        activeOpText = permanent
            ? ("Shredding " + paths.length + (paths.length === 1 ? " file..." : " files..."))
            : ("Trashing " + paths.length + (paths.length === 1 ? " file..." : " files..."));
        lastError = "";
        const mode = permanent ? "permanent" : "trash";
        const payload = JSON.stringify(paths);
        runCmd([
            "python3", storageScript, "shred-files",
            "--mode", mode,
            "--shell-dir", shellProjectRoot
        ], (ok, out, err) => {
            cleaning = false;
            activeOpText = "";
            const res = extractResultJson(out);
            if (!ok || !res || !res.ok) {
                lastResultOk = false;
                lastResultText = (res && res.error) ? res.error : (err || "Shredder failed");
                statusEventRequested(lastResultText, "danger", true);
                return;
            }
            const count = Number(res.removedCount || 0);
            const verb = permanent ? "Permanently shredded " : "Moved to Trash: ";
            lastResultOk = true;
            lastResultText = verb + count + (count === 1 ? " file (" : " files (") + formatBytes(res.freedBytes) + ")";
            statusEventRequested(lastResultText, "ok", true);
            scan(true);
        }, payload);
    }

    function revealInFiles(dirPath) {
        if (!dirPath) return;
        Quickshell.execDetached(["xdg-open", dirPath]);
    }
}
