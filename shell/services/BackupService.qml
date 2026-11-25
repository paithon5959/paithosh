pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string homeDir: Quickshell.env("HOME") || "/tmp"
    readonly property string backupBaseDir: homeDir + "/Backups"
    property string dataBackupDir: backupBaseDir + "/data"
    readonly property string systemBackupDir: backupBaseDir + "/system"
    readonly property string restoredDir: backupBaseDir + "/restored"
    readonly property string backupSettingsPath: homeDir + "/.config/paithosh/backup-settings.json"

    readonly property string btrfsScript: decodeURIComponent(Qt.resolvedUrl("../scripts/paithosh-btrfs.sh").toString().replace(/^file:\/\//, ""))
    readonly property string pakScript: decodeURIComponent(Qt.resolvedUrl("../scripts/paithosh-pak.py").toString().replace(/^file:\/\//, ""))

    property var btrfsInfo: ({
        isBtrfsRoot: false,
        rootFstype: "",
        rootDevice: "",
        rootUuid: "",
        rootSubvol: "",
        homeSeparateSubvol: false,
        bootSeparate: false,
        bootFstype: "",
        kernelRunning: "",
        vmlinuzExists: false,
        initramfsExists: false,
        polkitAgentActive: false,
        diskUsedPct: 0,
        diskAvailBytes: 0,
        legacyNestedCount: 0,
        snapshotTopDir: "@paithosh-snapshots"
    })
    readonly property bool isBtrfsRoot: Boolean(btrfsInfo.isBtrfsRoot)
    property var stagedRollback: null

    property bool useBtrfsSnapshot: true
    property bool excludeHeavyCache: true
    property bool _settingsLoaded: false

    property bool backingUpData: false
    property bool backingUpSystem: false
    property bool restoringData: false
    property int backupProgress: 0
    property string activeRestorePath: ""
    property bool deleting: false
    property bool verifying: false
    property bool rollingBack: false
    property bool importingPak: false
    readonly property bool busy: backingUpData || backingUpSystem || restoringData || deleting || verifying || rollingBack || importingPak
    readonly property string activeStatusText: {
        if (backingUpData) return "Packing .pak... " + backupProgress + "%";
        if (backingUpSystem) return statusText !== "" ? statusText : "Snapshotting system...";
        if (restoringData) return "Restoring .pak...";
        if (rollingBack) return "Staging rollback...";
        if (verifying) return "Verifying snapshot...";
        if (importingPak) return "Importing .pak...";
        if (deleting) return "Deleting backup...";
        return "";
    }

    property string statusText: ""
    property string systemError: ""
    property string dataError: ""
    property string lastError: ""
    property string lastDataBackupTime: ""
    property string lastSystemBackupTime: ""
    property string lastPreparedSysId: ""
    property var lastAuditSteps: []

    // Inspect / Verify / Rollback Modal State
    property bool inspectModalOpen: false
    property string inspectKind: "" // "pak" | "system" | "rollback"
    property bool inspectBusy: false
    property string inspectError: ""
    property var inspectData: null

    // Unified Privileged Sudo Auth Prompt State (fallback when Polkit agent is absent)
    property bool authPromptOpen: false
    property string authPromptTitle: "Administrator Authentication"
    property string authPromptDesc: "Enter your sudo password to continue."
    property string authPromptActionLabel: "Authenticate"
    property string authPromptError: ""
    property var _pendingPrivCmd: []
    property var _pendingPrivOnLine: null
    property var _pendingPrivCallback: null
    property string _pendingPrivTitle: ""
    property string _pendingPrivDesc: ""
    property string _pendingPrivActionLabel: ""

    property var dataFolders: [
        { id: "Documents", label: "Documents", relPath: "Documents", selected: true, exists: true, sizeText: "" },
        { id: "Projects", label: "Projects", relPath: "Projects", selected: true, exists: true, sizeText: "" },
        { id: "Pictures", label: "Pictures", relPath: "Pictures", selected: true, exists: true, sizeText: "" },
        { id: "Desktop", label: "Desktop", relPath: "Desktop", selected: true, exists: true, sizeText: "" },
        { id: ".config", label: "App Configs (.config)", relPath: ".config", selected: true, exists: true, sizeText: "" },
        { id: "Music", label: "Music", relPath: "Music", selected: false, exists: true, sizeText: "" },
        { id: "Videos", label: "Videos", relPath: "Videos", selected: false, exists: true, sizeText: "" },
        { id: "Downloads", label: "Downloads", relPath: "Downloads", selected: false, exists: true, sizeText: "" }
    ]

    readonly property int selectedFolderCount: {
        let c = 0;
        for (let i = 0; i < dataFolders.length; ++i) {
            if (dataFolders[i].selected && dataFolders[i].exists) c++;
        }
        return c;
    }

    readonly property int existingFolderCount: {
        let c = 0;
        for (let i = 0; i < dataFolders.length; ++i) {
            if (dataFolders[i].exists) c++;
        }
        return c;
    }

    property var dataBackups: []
    property var systemBackups: []
    readonly property int totalBackupsCount: dataBackups.length + systemBackups.length

    signal statusEventRequested(string msg, string kind, bool autoHide)

    Component {
        id: procComp
        Process {
            id: proc
            property var onLine: null
            property var cb: null
            property string outBuf: ""
            property string errBuf: ""
            property string pendingStdin: ""

            onStarted: {
                if (pendingStdin !== "") {
                    proc.write(pendingStdin);
                    proc.pendingStdin = "";
                    proc.stdinEnabled = false;
                }
            }
            stdout: SplitParser {
                onRead: data => {
                    proc.outBuf += (proc.outBuf !== "" ? "\n" : "") + data;
                    if (proc.onLine) proc.onLine(data);
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

    function runCmd(cmdArray, cb, onLine) {
        procComp.createObject(root, {
            command: cmdArray,
            onLine: onLine || null,
            cb: cb || null,
            running: true
        });
    }

    function runSudoCmd(password, argv, cb, onLine) {
        procComp.createObject(root, {
            command: ["sudo", "-S", "-k", "-p", ""].concat(argv),
            stdinEnabled: true,
            pendingStdin: password + "\n",
            onLine: onLine || null,
            cb: cb || null,
            running: true
        });
    }

    Component.onCompleted: loadSettings()

    function loadSettings() {
        runCmd(["sh", "-c", 'cat "$1" 2>/dev/null || true', "sh", backupSettingsPath], (ok, out) => {
            try {
                const raw = (out || "").trim();
                if (raw !== "") {
                    const parsed = JSON.parse(raw);
                    if (parsed && typeof parsed === "object") {
                        if (typeof parsed.useBtrfsSnapshot === "boolean") root.useBtrfsSnapshot = parsed.useBtrfsSnapshot;
                        if (typeof parsed.excludeHeavyCache === "boolean") root.excludeHeavyCache = parsed.excludeHeavyCache;
                        if (typeof parsed.dataBackupDir === "string" && parsed.dataBackupDir.trim() !== "") {
                            root.dataBackupDir = parsed.dataBackupDir.trim();
                        }
                        if (Array.isArray(parsed.selectedFolders)) {
                            const selSet = {};
                            for (let i = 0; i < parsed.selectedFolders.length; ++i) {
                                selSet[String(parsed.selectedFolders[i])] = true;
                            }
                            const next = [];
                            for (let i = 0; i < root.dataFolders.length; ++i) {
                                const item = Object.assign({}, root.dataFolders[i]);
                                item.selected = !!selSet[item.relPath];
                                next.push(item);
                            }
                            root.dataFolders = next;
                        }
                    }
                }
            } catch (e) {}
            root._settingsLoaded = true;
            root.refreshAll();
        });
    }

    function saveSettings() {
        if (!_settingsLoaded) return;
        const selected = [];
        for (let i = 0; i < dataFolders.length; ++i) {
            if (dataFolders[i].selected) selected.push(dataFolders[i].relPath);
        }
        const payload = JSON.stringify({
            useBtrfsSnapshot: useBtrfsSnapshot,
            excludeHeavyCache: excludeHeavyCache,
            dataBackupDir: dataBackupDir,
            selectedFolders: selected
        }, null, 2);
        runCmd([
            "python3", "-c",
            "import os,sys,tempfile; p=sys.argv[1]; d=os.path.dirname(p); os.makedirs(d, exist_ok=True); fd,tp=tempfile.mkstemp(dir=d); os.write(fd, sys.argv[2].encode()); os.close(fd); os.replace(tp, p)",
            backupSettingsPath, payload
        ], null);
    }

    function setUseBtrfsSnapshot(val) {
        const next = !!val;
        if (useBtrfsSnapshot === next) return;
        useBtrfsSnapshot = next;
        saveSettings();
    }

    function setExcludeHeavyCache(val) {
        const next = !!val;
        if (excludeHeavyCache === next) return;
        excludeHeavyCache = next;
        saveSettings();
    }

    function setDataStoreDir(dirPath) {
        const clean = String(dirPath || "").trim().replace(/\/+$/, "");
        if (!clean || clean === dataBackupDir) return;
        dataBackupDir = clean;
        dataError = "";
        saveSettings();
        refreshDataBackups();
    }

    function formatBytes(bytes) {
        if (isNaN(bytes) || bytes < 0) return "";
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB";
        if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + " MB";
        return (bytes / 1073741824).toFixed(2) + " GB";
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

    function parseStepLine(line, stepsAcc) {
        if (!line || !line.startsWith("STEP|")) return;
        const parts = line.split("|");
        if (parts.length < 4) return;
        const item = {
            step: parts[1],
            status: parts[2],
            detail: parts.slice(3).join("|")
        };
        stepsAcc.push(item);
        root.lastAuditSteps = stepsAcc.slice();
        if (item.detail !== "") root.statusText = item.detail;
    }

    function cleanErrorMessage(parsed, errBuf, fallback) {
        if (parsed && parsed.error) return String(parsed.error);
        const raw = (errBuf || "").trim();
        if (raw !== "") {
            const lines = raw.split("\n").filter(s => s.trim() !== "");
            if (lines.length > 0) return lines[lines.length - 1].trim();
        }
        return fallback;
    }

    function isPathInStore(filePath) {
        if (!filePath) return false;
        const normStore = dataBackupDir.replace(/\/+$/, "");
        const slash = filePath.lastIndexOf("/");
        const parent = slash > 0 ? filePath.slice(0, slash) : "/";
        return parent === normStore;
    }

    // Unified Privileged Execution: pkexec if Polkit agent active (unless forceSudo), else shared sudo stdin modal
    function runPrivileged(title, desc, actionLabel, argv, onDone, onLine, forceSudo) {
        if (!forceSudo && btrfsInfo && btrfsInfo.polkitAgentActive) {
            runCmd(["pkexec"].concat(argv), (ok, out, err, code) => {
                const parsed = extractResultJson(out);
                if (onDone) onDone(ok, parsed, out, err, code);
            }, onLine);
            return;
        }
        _pendingPrivTitle = title || "Administrator Authentication";
        _pendingPrivDesc = desc || "No active Polkit agent detected. Enter your sudo password to authorize this system operation.";
        _pendingPrivActionLabel = actionLabel || "Authorize";
        _pendingPrivCmd = argv.slice();
        _pendingPrivOnLine = onLine || null;
        _pendingPrivCallback = onDone || null;

        authPromptTitle = _pendingPrivTitle;
        authPromptDesc = _pendingPrivDesc;
        authPromptActionLabel = _pendingPrivActionLabel;
        authPromptError = "";
        authPromptOpen = true;
    }

    function cancelAuthPrompt() {
        authPromptOpen = false;
        authPromptError = "";
        const cb = _pendingPrivCallback;
        _pendingPrivCmd = [];
        _pendingPrivOnLine = null;
        _pendingPrivCallback = null;
        if (cb) cb(false, null, "", "Authentication cancelled", 126);
    }

    function submitAuthPassword(password) {
        if (!password || password.length === 0) {
            authPromptError = "Password cannot be empty";
            return;
        }
        const argv = _pendingPrivCmd.slice();
        const onLine = _pendingPrivOnLine;
        const cb = _pendingPrivCallback;
        authPromptOpen = false;
        authPromptError = "";

        runSudoCmd(password, argv, (ok, out, err, code) => {
            const isBadPwd = !ok && /incorrect password|sorry, try again|authentication failure/i.test(err || "");
            if (isBadPwd) {
                authPromptTitle = _pendingPrivTitle;
                authPromptDesc = _pendingPrivDesc;
                authPromptActionLabel = _pendingPrivActionLabel;
                authPromptError = "Incorrect sudo password. Please try again.";
                authPromptOpen = true;
                return;
            }
            _pendingPrivCmd = [];
            _pendingPrivOnLine = null;
            _pendingPrivCallback = null;
            const parsed = extractResultJson(out);
            if (cb) cb(ok, parsed, out, err, code);
        }, onLine);
    }

    function refreshAll() {
        refreshSystemBackups();
        refreshDataBackups();
        refreshFolders();
    }

    function refreshSystemBackups() {
        runCmd([btrfsScript, "probe", "--sys-dir", systemBackupDir], (ok, out) => {
            const parsed = extractResultJson(out);
            if (!parsed || !parsed.ok) return;
            if (parsed.env) root.btrfsInfo = parsed.env;
            root.stagedRollback = parsed.stagedRollback || null;
            const list = Array.isArray(parsed.snapshots) ? parsed.snapshots : [];
            for (let i = 0; i < list.length; ++i) {
                list[i].sizeText = formatBytes(Number(list[i].sizeBytes || 0));
            }
            root.systemBackups = list;
        });
    }

    function refreshDataBackups() {
        runCmd(["python3", pakScript, "list", "--store-dir", dataBackupDir], (ok, out) => {
            const parsed = extractResultJson(out);
            if (!parsed || !parsed.ok) return;
            const list = Array.isArray(parsed.items) ? parsed.items : [];
            for (let i = 0; i < list.length; ++i) {
                list[i].sizeText = formatBytes(Number(list[i].sizeBytes || 0));
                list[i].uncompressedText = formatBytes(Number(list[i].uncompressedBytes || 0));
                list[i].foldersText = Array.isArray(list[i].folders) ? list[i].folders.join(", ") : "";
            }
            root.dataBackups = list;
        });
    }

    function refreshFolders() {
        const script = [
            'HOME_DIR="$1"',
            'for d in Documents Projects Pictures Desktop .config Music Videos Downloads; do',
            '    p="$HOME_DIR/$d"',
            '    if [ -d "$p" ]; then printf "DIR|%s|1\\n" "$d"; else printf "DIR|%s|0\\n" "$d"; fi',
            'done'
        ].join("\n");
        runCmd(["sh", "-c", script, "sh", homeDir], (ok, out) => {
            if (!ok) return;
            const lines = (out || "").trim().split("\n");
            const existsMap = {};
            for (let i = 0; i < lines.length; ++i) {
                const parts = lines[i].trim().split("|");
                if (parts[0] === "DIR" && parts.length >= 3) existsMap[parts[1]] = (parts[2] === "1");
            }
            const next = [];
            for (let i = 0; i < root.dataFolders.length; ++i) {
                const item = Object.assign({}, root.dataFolders[i]);
                if (existsMap[item.relPath] !== undefined) {
                    item.exists = existsMap[item.relPath];
                    if (!item.exists) item.selected = false;
                }
                next.push(item);
            }
            root.dataFolders = next;
        });
        refreshFolderSizes();
    }

    function refreshFolderSizes() {
        const script = [
            'HOME_DIR="$1"',
            'for d in Documents Projects Pictures Desktop .config Music Videos Downloads; do',
            '    p="$HOME_DIR/$d"',
            '    if [ -d "$p" ]; then',
            '        sz=$(timeout 2s du -sh "$p" 2>/dev/null | awk "{print \\$1}" || true)',
            '        [ -n "$sz" ] && printf "SZ|%s|%s\\n" "$d" "$sz"',
            '    fi',
            'done'
        ].join("\n");
        runCmd(["sh", "-c", script, "sh", homeDir], (ok, out) => {
            if (!ok) return;
            const lines = (out || "").trim().split("\n");
            const sizeMap = {};
            for (let i = 0; i < lines.length; ++i) {
                const parts = lines[i].trim().split("|");
                if (parts[0] === "SZ" && parts.length >= 3) sizeMap[parts[1]] = parts[2];
            }
            const next = [];
            for (let i = 0; i < root.dataFolders.length; ++i) {
                const item = Object.assign({}, root.dataFolders[i]);
                if (sizeMap[item.relPath] !== undefined) item.sizeText = sizeMap[item.relPath];
                next.push(item);
            }
            root.dataFolders = next;
        });
    }

    function toggleDataFolder(idx) {
        if (idx < 0 || idx >= dataFolders.length || busy) return;
        const next = dataFolders.slice();
        const item = Object.assign({}, next[idx]);
        item.selected = !item.selected;
        next[idx] = item;
        dataFolders = next;
        saveSettings();
    }

    function setAllDataFolders(selected) {
        if (busy) return;
        const next = [];
        for (let i = 0; i < dataFolders.length; ++i) {
            const item = Object.assign({}, dataFolders[i]);
            if (item.exists) item.selected = !!selected;
            next.push(item);
        }
        dataFolders = next;
        saveSettings();
    }

    function selectOnlyFolder(relPath) {
        if (busy) return;
        const next = [];
        for (let i = 0; i < dataFolders.length; ++i) {
            const item = Object.assign({}, dataFolders[i]);
            item.selected = (item.relPath === relPath && item.exists);
            next.push(item);
        }
        dataFolders = next;
        saveSettings();
    }

    function createDataBackup() {
        if (busy || selectedFolderCount === 0) return;
        const relPaths = [];
        for (let i = 0; i < dataFolders.length; ++i) {
            if (dataFolders[i].selected && dataFolders[i].exists) {
                relPaths.push(dataFolders[i].relPath);
            }
        }
        if (relPaths.length === 0) return;

        backingUpData = true;
        backupProgress = 0;
        dataError = "";
        lastError = "";
        statusText = "Packing .pak... 0%";

        const cmd = [
            "python3", pakScript, "create",
            "--home", homeDir,
            "--store-dir", dataBackupDir,
            "--exclude-cache", excludeHeavyCache ? "1" : "0",
            "--folders"
        ].concat(relPaths);

        runCmd(cmd, (ok, out, err) => {
            root.backingUpData = false;
            const parsed = extractResultJson(out);
            if (ok && parsed && parsed.ok) {
                root.backupProgress = 100;
                root.lastDataBackupTime = Qt.formatTime(new Date(), "hh:mm");
                root.dataError = "";
                root.lastError = "";
                const skipNote = parsed.skippedCount > 0 ? (" • " + parsed.skippedCount + " special file(s) skipped") : "";
                root.statusText = "Saved " + parsed.name + " (" + parsed.fileCount + " files, CRC verified" + skipNote + ")";
                root.statusEventRequested(".pak backup saved (100%)", "ok", true);
                root.refreshDataBackups();
            } else {
                root.backupProgress = 0;
                const msg = cleanErrorMessage(parsed, err, "Failed to create .pak data backup");
                root.dataError = msg;
                root.lastError = msg;
                root.statusText = msg;
                root.statusEventRequested(".pak backup failed", "danger", true);
            }
        }, (line) => {
            if (line && line.startsWith("PROGRESS|")) {
                const pct = parseInt(line.slice(9), 10);
                if (!isNaN(pct)) {
                    root.backupProgress = pct;
                    root.statusText = "Packing .pak... " + pct + "%";
                }
            }
        });
    }

    function closeInspectModal() {
        inspectModalOpen = false;
        inspectBusy = false;
        inspectError = "";
    }

    function inspectPak(pakPath) {
        if (!pakPath) return;
        inspectKind = "pak";
        inspectBusy = true;
        inspectError = "";
        inspectData = {
            path: pakPath,
            name: String(pakPath).split("/").pop(),
            inStore: isPathInStore(pakPath),
            folders: [],
            entryCount: 0,
            sizeBytes: 0,
            uncompressedBytes: 0,
            crcOk: null,
            sha256: "",
            unsafePaths: [],
            skippedCount: 0,
            skippedSample: []
        };
        inspectModalOpen = true;

        runCmd(["python3", pakScript, "inspect", "--file", pakPath], (ok, out, err) => {
            root.inspectBusy = false;
            const parsed = extractResultJson(out);
            if (parsed) {
                parsed.inStore = root.isPathInStore(parsed.path || pakPath);
                root.inspectData = parsed;
                root.inspectError = parsed.ok ? "" : cleanErrorMessage(parsed, err, "Invalid .pak archive");
            } else {
                root.inspectError = cleanErrorMessage(null, err, "Failed to inspect .pak file");
            }
        });
    }

    function verifyPak(pakPath) {
        if (!pakPath) return;
        inspectKind = "pak";
        inspectBusy = true;
        inspectError = "";
        inspectModalOpen = true;

        runCmd(["python3", pakScript, "verify", "--file", pakPath], (ok, out, err) => {
            root.inspectBusy = false;
            const parsed = extractResultJson(out);
            if (parsed) {
                parsed.inStore = root.isPathInStore(parsed.path || pakPath);
                root.inspectData = parsed;
                root.inspectError = parsed.ok ? "" : cleanErrorMessage(parsed, err, ".pak verification failed");
                if (parsed.ok) {
                    root.statusEventRequested(".pak verified (CRC-32 OK)", "ok", true);
                } else {
                    root.statusEventRequested(".pak verification failed", "danger", true);
                }
            } else {
                root.inspectError = cleanErrorMessage(null, err, "Failed to verify .pak file");
            }
        });
    }

    function importPakToStore(pakPath) {
        if (busy || !pakPath) return;
        importingPak = true;
        dataError = "";
        runCmd(["python3", pakScript, "import", "--file", pakPath, "--store-dir", dataBackupDir, "--allow-zip"], (ok, out, err) => {
            root.importingPak = false;
            const parsed = extractResultJson(out);
            if (ok && parsed && parsed.ok) {
                root.dataError = "";
                root.statusText = parsed.alreadyInStore
                    ? (parsed.name + " is already in .pak store")
                    : ("Imported " + parsed.name + " into .pak store");
                root.statusEventRequested("Imported .pak to store", "ok", true);
                root.refreshDataBackups();
                if (root.inspectModalOpen && root.inspectKind === "pak") {
                    const updated = Object.assign({}, root.inspectData || {});
                    updated.path = parsed.path;
                    updated.name = parsed.name;
                    updated.inStore = true;
                    updated.crcOk = true;
                    updated.sha256 = parsed.sha256 || updated.sha256;
                    root.inspectData = updated;
                }
            } else {
                const msg = cleanErrorMessage(parsed, err, "Failed to import .pak into store");
                root.dataError = msg;
                root.inspectError = msg;
                root.statusEventRequested("Import .pak failed", "danger", true);
            }
        });
    }

    function restoreDataBackup(pakPath, mode, customDestDir) {
        if (busy || !pakPath) return;
        const restoreMode = (mode === "direct") ? "direct" : "staged";
        const destTarget = customDestDir && customDestDir !== ""
            ? customDestDir
            : (restoreMode === "direct" ? homeDir : restoredDir);

        restoringData = true;
        activeRestorePath = pakPath;
        dataError = "";
        lastError = "";
        statusText = "Verifying & restoring " + String(pakPath).split("/").pop() + "...";

        runCmd([
            "python3", pakScript, "restore",
            "--file", pakPath,
            "--dest", destTarget,
            "--mode", restoreMode,
            "--home", homeDir
        ], (ok, out, err) => {
            root.restoringData = false;
            root.activeRestorePath = "";
            const parsed = extractResultJson(out);
            if (ok && parsed && parsed.ok) {
                root.dataError = "";
                root.lastError = "";
                root.statusText = "Restored " + parsed.restoredCount + " entries to " + parsed.destDir;
                root.statusEventRequested("Restored .pak backup", "ok", true);
                if (root.inspectModalOpen && root.inspectKind === "pak") {
                    root.inspectModalOpen = false;
                }
            } else {
                const msg = cleanErrorMessage(parsed, err, "Failed to restore .pak backup");
                root.dataError = msg;
                root.lastError = msg;
                root.inspectError = msg;
                root.statusText = msg;
                root.statusEventRequested("Restore failed", "danger", true);
            }
        });
    }

    function createSystemBackup(reason, skipBtrfs, onDone) {
        if (busy) {
            if (onDone) onDone(false, "");
            return;
        }
        const cleanReason = String(reason || "Manual system backup").replace(/[\r\n|"]/g, " ").trim() || "Manual system backup";
        const baseId = "paithosh-sys-" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
        let sysId = baseId;
        for (let i = 0; i < systemBackups.length; ++i) {
            if (systemBackups[i].id === sysId) {
                sysId = baseId + "-" + String(Date.now() % 10000);
                break;
            }
        }
        lastPreparedSysId = sysId;
        const withBtrfs = (!skipBtrfs && isBtrfsRoot && useBtrfsSnapshot);
        const stepsAcc = [];
        lastAuditSteps = [];
        backingUpSystem = true;
        systemError = "";
        lastError = "";
        statusText = withBtrfs ? "Creating verified Btrfs snapshot & system state archive..." : "Creating system state archive...";

        const argv = [
            btrfsScript, "create",
            "--id", sysId,
            "--reason", cleanReason,
            "--trigger", "manual",
            "--sys-dir", systemBackupDir,
            "--home-dir", homeDir,
            "--with-btrfs", withBtrfs ? "1" : "0"
        ];

        const handleFinish = function(ok, parsed, out, err) {
            root.backingUpSystem = false;
            if (ok && parsed && parsed.ok) {
                root.lastSystemBackupTime = Qt.formatTime(new Date(), "hh:mm");
                root.systemError = "";
                root.lastError = "";
                if (parsed.btrfsCreated) {
                    root.statusText = "Verified Btrfs snapshot " + sysId + " (" + String(parsed.btrfsUuid || "").slice(0, 8) + "...)";
                    root.statusEventRequested("Btrfs snapshot saved", "ok", true);
                } else {
                    root.statusText = "System state archive saved (no Btrfs snapshot)";
                    root.statusEventRequested("System archive saved", "ok", true);
                }
                root.refreshSystemBackups();
                if (onDone) onDone(true, sysId);
            } else {
                const msg = cleanErrorMessage(parsed, err, "System backup failed");
                root.systemError = msg;
                root.lastError = msg;
                root.statusText = msg;
                root.statusEventRequested("System backup failed", "danger", true);
                root.refreshSystemBackups();
                if (onDone) onDone(false, "");
            }
        };

        if (withBtrfs) {
            runPrivileged(
                "System Snapshot Authorization",
                "Creating a read-only Btrfs snapshot of subvol=" + (btrfsInfo.rootSubvol || "root") + " requires administrator privileges.",
                "Create Snapshot",
                argv,
                handleFinish,
                (line) => parseStepLine(line, stepsAcc)
            );
        } else {
            runCmd(argv, (ok, out, err) => {
                handleFinish(ok, extractResultJson(out), out, err);
            }, (line) => parseStepLine(line, stepsAcc));
        }
    }

    function _runSystemVerify(id, modalKind) {
        if (busy || !id) return;
        verifying = true;
        systemError = "";
        inspectKind = modalKind;
        inspectBusy = true;
        inspectError = "";
        inspectData = { id: id, checks: [], canRollback: false, matchedKernels: [] };
        inspectModalOpen = true;

        runPrivileged(
            "Verify Btrfs Snapshot",
            "Mounting Btrfs top-level subvolid=5 temporarily to verify snapshot integrity and /boot kernel compatibility.",
            "Verify Snapshot",
            [btrfsScript, "verify", "--id", id, "--sys-dir", systemBackupDir],
            (ok, parsed, out, err) => {
                root.verifying = false;
                root.inspectBusy = false;
                if (parsed) {
                    root.inspectData = parsed;
                    if (parsed.canRollback) {
                        root.inspectError = "";
                        root.statusEventRequested("Snapshot verified", "ok", true);
                    } else {
                        root.inspectError = cleanErrorMessage(parsed, err, "Snapshot verification failed checks");
                        root.statusEventRequested("Verification failed", "danger", true);
                    }
                } else {
                    const msg = cleanErrorMessage(null, err, "Failed to verify snapshot");
                    root.inspectError = msg;
                    root.systemError = msg;
                    root.statusEventRequested("Verification error", "danger", true);
                }
            }
        );
    }

    function verifySystemBackup(id) {
        _runSystemVerify(id, "system");
    }

    function requestRollbackSystemBackup(id) {
        _runSystemVerify(id, "rollback");
    }

    function confirmRollbackSystemBackup(id) {
        if (busy || !id) return;
        const stepsAcc = [];
        lastAuditSteps = [];
        rollingBack = true;
        systemError = "";
        inspectBusy = true;
        inspectError = "";
        statusText = "Staging Btrfs rollback to " + id + "...";

        runPrivileged(
            "Confirm System Rollback",
            "Rollback replaces subvol=" + (btrfsInfo.rootSubvol || "root") + " with snapshot " + id + " for next boot. /home is untouched and previous root is preserved.",
            "Stage Rollback",
            [btrfsScript, "rollback", "--id", id, "--sys-dir", systemBackupDir],
            (ok, parsed, out, err) => {
                root.rollingBack = false;
                root.inspectBusy = false;
                if (ok && parsed && parsed.ok) {
                    root.inspectModalOpen = false;
                    root.systemError = "";
                    root.stagedRollback = parsed.stagedRollback || null;
                    root.statusText = "Rollback staged to " + id + ". Reboot to activate (or click Undo).";
                    root.statusEventRequested("Rollback staged — reboot ready", "ok", true);
                    root.refreshSystemBackups();
                } else {
                    const msg = cleanErrorMessage(parsed, err, "Failed to stage Btrfs rollback");
                    root.inspectError = msg;
                    root.systemError = msg;
                    root.statusText = msg;
                    root.statusEventRequested("Rollback failed", "danger", true);
                }
            },
            (line) => parseStepLine(line, stepsAcc)
        );
    }

    function undoStagedRollback() {
        if (busy || !stagedRollback) return;
        const stepsAcc = [];
        lastAuditSteps = [];
        rollingBack = true;
        systemError = "";
        statusText = "Undoing staged rollback...";

        runPrivileged(
            "Undo Staged Rollback",
            "Restore your original subvol=" + (btrfsInfo.rootSubvol || "root") + " before rebooting.",
            "Undo Rollback",
            [btrfsScript, "undo-rollback"],
            (ok, parsed, out, err) => {
                root.rollingBack = false;
                if (ok && parsed && parsed.ok) {
                    root.stagedRollback = null;
                    root.systemError = "";
                    root.statusText = "Staged rollback undone; original system root restored";
                    root.statusEventRequested("Rollback undone", "ok", true);
                    root.refreshSystemBackups();
                } else {
                    const msg = cleanErrorMessage(parsed, err, "Failed to undo staged rollback");
                    root.systemError = msg;
                    root.statusText = msg;
                    root.statusEventRequested("Undo failed", "danger", true);
                }
            },
            (line) => parseStepLine(line, stepsAcc)
        );
    }

    function rebootNow() {
        PowerService.executeAction("Reboot");
    }

    function deleteBackup(kind, pathOrId, hasBtrfsSnap) {
        if (busy || !pathOrId) return;
        deleting = true;

        if (kind !== "system") {
            dataError = "";
            runCmd(["rm", "-f", "--", pathOrId], (ok, out, err) => {
                root.deleting = false;
                if (!ok) {
                    root.dataError = cleanErrorMessage(null, err, "Failed to delete .pak file");
                    root.statusEventRequested("Delete failed", "danger", true);
                } else {
                    root.statusEventRequested("Deleted .pak backup", "ok", true);
                }
                root.refreshDataBackups();
            });
            return;
        }

        systemError = "";
        const id = pathOrId;
        const argv = [btrfsScript, "delete", "--id", id, "--sys-dir", systemBackupDir, "--has-btrfs", hasBtrfsSnap ? "1" : "0"];
        const onFinish = function(ok, parsed, out, err) {
            root.deleting = false;
            if (ok && (!parsed || parsed.ok !== false)) {
                root.systemError = "";
                root.statusEventRequested("Deleted system backup", "ok", true);
            } else {
                const msg = cleanErrorMessage(parsed, err, "Failed to delete system backup");
                root.systemError = msg;
                root.statusEventRequested("Delete failed", "danger", true);
            }
            root.refreshSystemBackups();
        };

        if (hasBtrfsSnap) {
            runPrivileged(
                "Delete Btrfs Snapshot",
                "Deleting Btrfs snapshot @paithosh-snapshots/" + id + " requires administrator privileges.",
                "Delete Snapshot",
                argv,
                onFinish
            );
        } else {
            runCmd(argv, (ok, out, err) => onFinish(ok, extractResultJson(out), out, err));
        }
    }

    function openBackupFolder(subDir) {
        let target = root.backupBaseDir;
        if (subDir === "data") target = root.dataBackupDir;
        else if (subDir === "system") target = root.systemBackupDir;
        else if (subDir === "restored") target = root.restoredDir;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && exec xdg-open "$1"', "sh", target]);
    }
}
