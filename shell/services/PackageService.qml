pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Internal backend detection ("dnf5" | "dnf" | "pacman" | "apt" | ""); never exposed in UI
    property string backendTool: ""
    readonly property bool isFedora: backendTool === "dnf5" || backendTool === "dnf"
    readonly property bool isArch: backendTool === "pacman"
    readonly property bool isDebian: backendTool === "apt"
    property bool previewMode: false
    property bool checking: false
    property bool updating: false
    property bool cleaningCache: false
    property int cleanCacheProgress: 0
    property string cacheSizeText: ""
    property bool manualCheckPending: false
    property bool _verifyCheckPending: false
    property var _pendingVerifyPkgs: []
    property var packages: []
    property string lastError: ""
    property string lastCheckedText: ""

    // Auto-update schedule ("off" | "daily" | "weekly" | "monthly") & Fedora beta updates
    property string autoUpdateSchedule: "weekly"
    property bool betaUpdatesEnabled: false
    property double lastAutoUpdateMs: 0
    readonly property string settingsPath: (Quickshell.env("XDG_CONFIG_HOME") || ((Quickshell.env("HOME") || "/tmp") + "/.config")) + "/paithosh/package-settings.json"

    // Paithosh Shell git repo updates ("main" | "release", default "main")
    readonly property string shellProjectRoot: Quickshell.shellDir.replace(/\/shell\/?$/, "")
    property string shellUpdateStream: "main"
    property bool shellChecking: false
    property bool shellUpdating: false
    property bool shellCheckedOnce: false
    property int shellUpdateBehind: 0
    property int shellUpdateAhead: 0
    property string shellBranch: ""
    property string shellCommit: ""
    property string shellCurrentTag: ""
    property string shellTargetVersion: ""
    property string shellLatestSummary: ""
    property string shellReleaseChangelog: ""
    property var shellCommits: []
    signal shellReloadRequested(bool hard, string reason)
    property string shellUpdateError: ""

    // Default Hyprland Lua config sync state
    property string hyprSyncState: "" // "synced" | "outdated" | "unmanaged" | "missing" | ""
    property string hyprSyncMessage: ""
    property string hyprSyncError: ""
    property bool hyprSyncing: false
    property int hyprModifiedCount: 0
    property var hyprModifiedFiles: []
    property string hyprDiffFile: ""
    property var hyprDiffLines: []
    property int hyprDiffAdded: 0
    property int hyprDiffDeleted: 0
    property bool hyprDiffTruncated: false
    property bool hyprDiffLoading: false
    property string hyprDiffError: ""
    property int hyprPendingCount: 0

    // Mandatory core dependency audit (hyprcursor, Cairo/Rsvg, etc.)
    property var missingCoreDeps: []
    property string missingCorePkgs: ""
    property bool checkingDeps: false
    property bool installingDeps: false
    property string depsError: ""

    // Concise status bar event state (never uses notification popup)
    property bool statusEventOpen: false
    property string statusEventText: ""
    property string statusEventKind: "info" // "info" | "ok" | "danger"
    readonly property string activeOpText: {
        if (backingUpBeforeUpdate) return "Pre-update snapshot...";
        if (updating) return "Updating " + selectedCount + (selectedCount === 1 ? " pkg..." : " pkgs...");
        if (cleaningCache) return "Cleaning cache... " + cleanCacheProgress + "%";
        if (shellUpdating) return "Updating shell...";
        if (hyprSyncing) return "Syncing Hyprland...";
        if (installingDeps) return "Installing required packages...";
        if (StorageService.activeOpText !== "") return StorageService.activeOpText;
        return "";
    }

    // Synchronized Pre-Update System Backup state
    property bool autoBackupMajorUpdates: true
    property bool backupBeforeUpdate: false
    property bool userOverrodeBackupToggle: false
    property bool backingUpBeforeUpdate: false

    readonly property var majorWatchedPackages: [
        "linux", "linux-lts", "linux-zen", "kernel", "kernel-core", "kernel-modules",
        "hyprland", "mesa", "systemd", "glibc", "nvidia", "grub2", "btrfs-progs",
        "pipewire", "quickshell"
    ]
    readonly property var matchedMajorPackages: {
        const re = /^(linux|linux-lts|linux-zen|kernel|kernel-core|kernel-modules|hyprland|mesa|systemd|glibc|nvidia|grub2|btrfs-progs|pipewire|quickshell)(-|$)/i;
        const hits = [];
        for (let i = 0; i < packages.length; ++i) {
            const pkg = packages[i];
            if (pkg.selected && re.test(pkg.name)) {
                hits.push(pkg.name);
            }
        }
        return hits;
    }
    readonly property bool isMajorUpdate: matchedMajorPackages.length > 0 || selectedCount >= 10
    readonly property string majorUpdateSummary: {
        if (matchedMajorPackages.length > 0) {
            const head = matchedMajorPackages.slice(0, 3).join(", ");
            const tail = matchedMajorPackages.length > 3 ? (" +" + (matchedMajorPackages.length - 3)) : "";
            return "Core packages: " + head + tail;
        }
        if (selectedCount >= 10) {
            return "Large update (" + selectedCount + " packages)";
        }
        return "";
    }

    Connections {
        target: BackupService
        function onStatusEventRequested(msg, kind, autoHide) {
            root.triggerStatusEvent(msg, kind, autoHide);
        }
    }

    Connections {
        target: StorageService
        function onStatusEventRequested(msg, kind, autoHide) {
            root.triggerStatusEvent(msg, kind, autoHide);
        }
    }

    readonly property int updateCount: packages.length
    readonly property int selectedCount: {
        let c = 0;
        for (let i = 0; i < packages.length; ++i) {
            if (packages[i].selected) c++;
        }
        return c;
    }

    function triggerStatusEvent(msg, kind, autoHide) {
        statusEventText = msg;
        statusEventKind = kind || "info";
        statusEventOpen = true;
        if (autoHide) {
            statusEventTimer.restart();
        } else {
            statusEventTimer.stop();
        }
    }

    function dismissStatusEvent() {
        statusEventTimer.stop();
        statusEventOpen = false;
    }

    function syncBackupRecommendation() {
        if (!userOverrodeBackupToggle && autoBackupMajorUpdates) {
            backupBeforeUpdate = isMajorUpdate;
        }
    }

    function setBackupBeforeUpdate(val) {
        userOverrodeBackupToggle = true;
        backupBeforeUpdate = !!val;
    }

    function setAutoBackupMajorUpdates(val) {
        autoBackupMajorUpdates = !!val;
        userOverrodeBackupToggle = false;
        syncBackupRecommendation();
        saveSettings();
    }

    function scheduleIntervalMs(schedule) {
        if (schedule === "daily") return 86400000;
        if (schedule === "weekly") return 604800000;
        if (schedule === "monthly") return 2592000000;
        return 0;
    }

    function saveSettings() {
        const payload = JSON.stringify({
            autoUpdateSchedule: autoUpdateSchedule,
            betaUpdatesEnabled: betaUpdatesEnabled,
            lastAutoUpdateMs: lastAutoUpdateMs,
            autoBackupMajorUpdates: autoBackupMajorUpdates,
            shellUpdateStream: shellUpdateStream
        });
        saveSettingsProc.command = [
            "sh", "-c",
            'd=$(dirname "$1"); mkdir -p "$d" && tmp="$1.tmp.$$" && printf "%s" "$2" > "$tmp" && mv -f "$tmp" "$1"',
            "_", settingsPath, payload
        ];
        saveSettingsProc.running = false;
        saveSettingsProc.running = true;
    }

    function setShellUpdateStream(stream) {
        const next = (stream === "release") ? "release" : "main";
        if (shellUpdateStream === next) return;
        shellUpdateStream = next;
        shellUpdateBehind = 0;
        shellUpdateAhead = 0;
        shellTargetVersion = "";
        shellLatestSummary = "";
        shellReleaseChangelog = "";
        shellCommits = [];
        shellUpdateError = "";
        saveSettings();
        checkShellUpdate();
    }

    function setAutoUpdateSchedule(schedule) {
        const valid = ["off", "daily", "weekly", "monthly"];
        const next = valid.indexOf(schedule) !== -1 ? schedule : "weekly";
        if (autoUpdateSchedule === next) return;
        autoUpdateSchedule = next;
        saveSettings();
    }

    function setBetaUpdatesEnabled(val) {
        const next = !!val;
        if (betaUpdatesEnabled === next) return;
        betaUpdatesEnabled = next;
        saveSettings();
        if (isFedora) {
            checkUpdates(false);
        }
    }

    function maybeRunScheduledUpdate() {
        const interval = scheduleIntervalMs(autoUpdateSchedule);
        if (interval <= 0) return false;
        const now = Date.now();
        if (lastAutoUpdateMs > 0 && (now - lastAutoUpdateMs) < interval) return false;
        if (updating || checking || backingUpBeforeUpdate) return false;
        lastAutoUpdateMs = now;
        saveSettings();
        checkUpdates(true);
        return true;
    }

    function checkUpdates(isManual) {
        if (checking || updating || backingUpBeforeUpdate) return;
        manualCheckPending = !!isManual;
        checking = true;
        lastError = "";
        checkProc.outBuf = "";
        checkProc.errBuf = "";
        checkProc._stdoutDone = false;
        checkProc._stderrDone = false;
        checkProc._exited = false;
        checkProc._exitCode = -1;
        checkProc.running = false;
        checkProc.running = true;
    }

    function togglePackage(idx) {
        if (idx < 0 || idx >= packages.length || updating || backingUpBeforeUpdate) return;
        const next = packages.slice();
        const item = Object.assign({}, next[idx]);
        item.selected = !item.selected;
        next[idx] = item;
        packages = next;
        syncBackupRecommendation();
    }

    function setAllSelected(selected) {
        if (updating || backingUpBeforeUpdate || packages.length === 0) return;
        const next = [];
        for (let i = 0; i < packages.length; ++i) {
            const item = Object.assign({}, packages[i]);
            item.selected = !!selected;
            next.push(item);
        }
        packages = next;
        syncBackupRecommendation();
    }

    function _finishInstall(ok, parsed, errMsg) {
        root.backingUpBeforeUpdate = false;
        root.updating = false;
        BackupService.refreshAll();
        if (ok && (!parsed || parsed.ok !== false)) {
            root.userOverrodeBackupToggle = false;
            root.lastError = "";
            root._verifyCheckPending = true;
            root.triggerStatusEvent("Verifying updated packages...", "info", false);
            root.checkUpdates(false);
        } else {
            root._verifyCheckPending = false;
            root._pendingVerifyPkgs = [];
            const msg = BackupService.cleanErrorMessage(parsed, errMsg, "Authentication cancelled or update failed");
            root.lastError = msg;
            root.triggerStatusEvent("Update failed", "danger", true);
        }
    }

    function installSelected() {
        if (updating || checking || backingUpBeforeUpdate || selectedCount === 0) return;
        if (backendTool === "") {
            if (!previewMode) {
                lastError = "No supported package manager detected";
                return;
            }
            if (backupBeforeUpdate) {
                backingUpBeforeUpdate = true;
                lastError = "";
                const reason = isMajorUpdate
                    ? ("Pre-update (" + majorUpdateSummary + ")")
                    : ("Pre-update (" + selectedCount + (selectedCount === 1 ? " pkg)" : " pkgs)"));
                BackupService.createSystemBackup(reason, true, function(ok) {
                    root.backingUpBeforeUpdate = false;
                    if (!ok) {
                        root.lastError = "Pre-update system backup failed";
                        root.triggerStatusEvent("Pre-update backup failed", "danger", true);
                        return;
                    }
                    root.updating = true;
                    previewInstallTimer.restart();
                });
                return;
            }
            updating = true;
            previewInstallTimer.restart();
            return;
        }

        const pkgRe = /^[a-zA-Z0-9][a-zA-Z0-9._+:~-]*$/;
        const selectedIds = [];
        const selectedObjs = [];
        const unselectedNames = [];
        for (let i = 0; i < packages.length; ++i) {
            const p = packages[i];
            if (p.selected) {
                if (pkgRe.test(String(p.id || ""))) {
                    selectedIds.push(p.id);
                    selectedObjs.push({ id: p.id, name: p.name, oldVersion: p.oldVersion, newVersion: p.newVersion });
                }
            } else if (pkgRe.test(String(p.name || ""))) {
                unselectedNames.push(p.name);
            }
        }
        if (selectedIds.length === 0) {
            lastError = "No valid package IDs selected";
            return;
        }
        const allSelected = selectedIds.length === packages.length;
        const useBeta = (betaUpdatesEnabled && isFedora) ? "1" : "0";
        const ignoreCsv = isArch ? unselectedNames.join(",") : "";
        _pendingVerifyPkgs = selectedObjs;
        _verifyCheckPending = false;
        lastError = "";

        if (backupBeforeUpdate) {
            const reason = (isMajorUpdate
                ? ("Pre-update (" + majorUpdateSummary + ")")
                : ("Pre-update (" + selectedCount + (selectedCount === 1 ? " pkg)" : " pkgs)")))
                .replace(/[\r\n|"]/g, " ").trim();
            const sysId = "paithosh-sys-" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
            const withBtrfs = (BackupService.isBtrfsRoot && BackupService.useBtrfsSnapshot) ? "1" : "0";
            const stepsAcc = [];
            BackupService.lastAuditSteps = [];
            backingUpBeforeUpdate = true;

            const argv = [
                BackupService.btrfsScript, "pre-update",
                "--id", sysId,
                "--reason", reason,
                "--sys-dir", BackupService.systemBackupDir,
                "--home-dir", BackupService.homeDir,
                "--with-btrfs", withBtrfs,
                "--tool", backendTool,
                "--all", allSelected ? "1" : "0",
                "--beta", useBeta,
                "--ignore", ignoreCsv,
                "--"
            ].concat(selectedIds);

            const backupDesc = (withBtrfs === "1")
                ? ("Creates a verified Btrfs snapshot (" + sysId + ") before upgrading " + selectedCount + " package(s). Upgrade aborts if snapshot fails.")
                : ("Creates a system state archive (" + sysId + ") before upgrading " + selectedCount + " package(s).");

            BackupService.runPrivileged(
                "Pre-Update Snapshot & Upgrade",
                backupDesc,
                "Backup & Update",
                argv,
                (ok, parsed, out, err) => root._finishInstall(ok, parsed, err),
                (line) => {
                    BackupService.parseStepLine(line, stepsAcc);
                    if (line.startsWith("STEP|pkg_upgrade|")) {
                        root.backingUpBeforeUpdate = false;
                        root.updating = true;
                    }
                }
            );
            return;
        }

        const script = [
            'TOOL="$1"; ALL="$2"; USE_BETA="$3"; IGNORE_CSV="$4"; shift 4',
            'if [ "$TOOL" = "dnf5" ] || [ "$TOOL" = "dnf" ]; then',
            '    BETA_FLAG=""; [ "$USE_BETA" = "1" ] && BETA_FLAG="--enablerepo=updates-testing"',
            '    if [ "$ALL" = "1" ]; then exec "$TOOL" upgrade -y $BETA_FLAG; else exec "$TOOL" upgrade -y $BETA_FLAG -- "$@"; fi',
            'elif [ "$TOOL" = "pacman" ]; then',
            '    if [ -n "$IGNORE_CSV" ]; then exec pacman -Syu --noconfirm --ignore "$IGNORE_CSV"; else exec pacman -Syu --noconfirm; fi',
            'elif [ "$TOOL" = "apt" ]; then',
            '    export DEBIAN_FRONTEND=noninteractive',
            '    apt-get update || exit $?',
            '    if [ "$ALL" = "1" ]; then exec apt-get upgrade -y; else exec apt-get install -y --only-upgrade -- "$@"; fi',
            'fi',
            'exit 1'
        ].join("\n");
        updating = true;
        BackupService.runPrivileged(
            "System Package Upgrade",
            "Authorize upgrading " + selectedCount + " selected package(s) using " + backendTool + ".",
            "Install Updates",
            ["sh", "-c", script, "_", backendTool, allSelected ? "1" : "0", useBeta, ignoreCsv].concat(selectedIds),
            (ok, parsed, out, err) => root._finishInstall(ok, parsed, err)
        );
    }

    function refreshCacheSize() {
        if (backendTool === "") {
            if (previewMode && cacheSizeText === "") cacheSizeText = "1.2 GB";
            else if (!previewMode) cacheSizeText = "";
            return;
        }
        const script = [
            'TOOL="$1"',
            'if [ "$TOOL" = "pacman" ]; then',
            '    DIR="/var/cache/pacman/pkg"',
            'elif [ "$TOOL" = "dnf5" ]; then',
            '    DIR="/var/cache/libdnf5"',
            '    [ -d "$DIR" ] || DIR="/var/cache/dnf"',
            'elif [ "$TOOL" = "dnf" ]; then',
            '    DIR="/var/cache/dnf"',
            'elif [ "$TOOL" = "apt" ]; then',
            '    DIR="/var/cache/apt/archives"',
            'else',
            '    exit 0',
            'fi',
            'if [ -d "$DIR" ]; then',
            '    du -sh "$DIR" 2>/dev/null | awk \'{print $1}\'',
            'else',
            '    echo "0B"',
            'fi'
        ].join("\n");
        cacheSizeProc.command = ["sh", "-c", script, "_", backendTool];
        cacheSizeProc.running = false;
        cacheSizeProc.running = true;
    }

    function cleanCache() {
        if (checking || updating || backingUpBeforeUpdate || cleaningCache) return;
        cleanCacheProgress = 0;
        if (backendTool === "") {
            if (!previewMode) {
                lastError = "No supported package backend";
                return;
            }
            cleaningCache = true;
            cleanCacheProgressTimer.restart();
            previewCleanCacheTimer.restart();
            return;
        }
        let targetCmd = [];
        if (backendTool === "dnf5" || backendTool === "dnf") {
            targetCmd = [backendTool, "clean", "all"];
        } else if (backendTool === "pacman") {
            targetCmd = ["pacman", "-Sc", "--noconfirm"];
        } else if (backendTool === "apt") {
            targetCmd = ["apt-get", "clean"];
        } else {
            lastError = "No supported package backend";
            return;
        }
        lastError = "";
        cleaningCache = true;
        cleanCacheProgressTimer.restart();
        BackupService.runPrivileged(
            "Clean Package Cache",
            "Remove cached package manager files using " + backendTool + ".",
            "Clean Cache",
            targetCmd,
            (ok, parsed, out, err) => {
                cleanCacheProgressTimer.stop();
                root.cleaningCache = false;
                root.refreshCacheSize();
                if (ok) {
                    root.cleanCacheProgress = 100;
                    root.lastError = "";
                    root.triggerStatusEvent("Package cache cleaned (100%)", "ok", true);
                } else {
                    root.cleanCacheProgress = 0;
                    const msg = BackupService.cleanErrorMessage(parsed, err, "Authentication cancelled or cache clean failed");
                    root.lastError = msg;
                    root.triggerStatusEvent("Cache clean failed", "danger", true);
                }
            }
        );
    }

    function triggerPreviewUpdates(count) {
        previewMode = true;
        const n = (typeof count === "number") ? count : 4;
        if (n <= 0) {
            packages = [];
            userOverrodeBackupToggle = false;
            syncBackupRecommendation();
            lastError = "";
            lastCheckedText = Qt.formatTime(new Date(), "hh:mm");
            triggerStatusEvent("System up to date", "ok", true);
            return;
        }
        const sample = [
            { id: "hyprland", name: "hyprland", oldVersion: "0.45.0-1", newVersion: "0.45.2-1", selected: true },
            { id: "linux", name: "linux", oldVersion: "6.11.8-1", newVersion: "6.11.9-1", selected: true },
            { id: "mesa", name: "mesa", oldVersion: "24.2.6-1", newVersion: "24.2.7-1", selected: true },
            { id: "pipewire", name: "pipewire", oldVersion: "1.2.5-1", newVersion: "1.2.6-1", selected: true }
        ];
        packages = sample.slice(0, Math.min(n, sample.length));
        userOverrodeBackupToggle = false;
        syncBackupRecommendation();
        lastError = "";
        lastCheckedText = Qt.formatTime(new Date(), "hh:mm");
        triggerStatusEvent(packages.length + (packages.length === 1 ? " update ready" : " updates ready"), "info", true);
    }

    Timer {
        id: statusEventTimer
        interval: 5000
        repeat: false
        onTriggered: root.statusEventOpen = false
    }

    Timer {
        id: startupTimer
        interval: 3500
        running: true
        repeat: false
        onTriggered: {
            BackupService.refreshSystemBackups();
            root.checkUpdates(false);
            root.checkShellUpdate();
            root.checkHyprSyncStatus();
        }
    }

    Timer {
        id: periodicTimer
        interval: 1800000
        running: true
        repeat: true
        onTriggered: {
            if (!root.maybeRunScheduledUpdate()) {
                root.checkUpdates(false);
            }
            root.checkShellUpdate();
        }
    }

    FileView {
        id: settingsFile
        path: root.settingsPath
        preload: true
        onLoaded: {
            try {
                const parsed = JSON.parse(text());
                if (parsed && typeof parsed === "object") {
                    if (typeof parsed.autoUpdateSchedule === "string") {
                        const valid = ["off", "daily", "weekly", "monthly"];
                        if (valid.indexOf(parsed.autoUpdateSchedule) !== -1) {
                            root.autoUpdateSchedule = parsed.autoUpdateSchedule;
                        }
                    }
                    if (typeof parsed.betaUpdatesEnabled === "boolean") {
                        root.betaUpdatesEnabled = parsed.betaUpdatesEnabled;
                    }
                    if (typeof parsed.lastAutoUpdateMs === "number") {
                        root.lastAutoUpdateMs = parsed.lastAutoUpdateMs;
                    }
                    if (typeof parsed.autoBackupMajorUpdates === "boolean") {
                        root.autoBackupMajorUpdates = parsed.autoBackupMajorUpdates;
                        root.syncBackupRecommendation();
                    }
                    if (parsed.shellUpdateStream === "main" || parsed.shellUpdateStream === "release") {
                        root.shellUpdateStream = parsed.shellUpdateStream;
                    }
                }
            } catch (e) {}
        }
    }

    Process {
        id: saveSettingsProc
    }

    Timer {
        id: previewInstallTimer
        interval: 1200
        repeat: false
        onTriggered: {
            const remaining = [];
            for (let i = 0; i < root.packages.length; ++i) {
                if (!root.packages[i].selected) remaining.push(root.packages[i]);
            }
            root.packages = remaining;
            root.userOverrodeBackupToggle = false;
            root.syncBackupRecommendation();
            root.updating = false;
            root.lastCheckedText = Qt.formatTime(new Date(), "hh:mm");
            BackupService.refreshAll();
            root.triggerStatusEvent(remaining.length === 0 ? "Updates installed" : (remaining.length + " updates left"), "ok", true);
        }
    }

    Process {
        id: checkProc
        property string outBuf: ""
        property string errBuf: ""
        property bool _stdoutDone: false
        property bool _stderrDone: false
        property bool _exited: false
        property int _exitCode: -1

        function tryFinish() {
            if (!_stdoutDone || !_stderrDone || !_exited) return;
            _exited = false;
            const lines = (outBuf || "").trim().split("\n");
            const parsed = [];
            let errMsg = "";
            for (let i = 0; i < lines.length; ++i) {
                const line = lines[i].trim();
                if (!line) continue;
                const parts = line.split("|");
                if (parts[0] === "BACKEND" && parts.length >= 2) {
                    root.backendTool = parts[1];
                    root.previewMode = false;
                } else if (parts[0] === "PKG" && parts.length >= 5) {
                    parsed.push({
                        name: parts[1],
                        oldVersion: parts[2],
                        newVersion: parts[3],
                        id: parts[4],
                        selected: true
                    });
                } else if (parts[0] === "ERR" && parts.length >= 2) {
                    errMsg = parts.slice(1).join("|");
                }
            }
            if (_exitCode !== 0 && errMsg === "") {
                const fb = root.extractShellError(errBuf);
                errMsg = fb !== "" ? fb : ("Update check failed (exit " + _exitCode + ")");
            }

            root.checking = false;
            root.lastCheckedText = Qt.formatTime(new Date(), "hh:mm");
            root.refreshCacheSize();

            const wasVerify = root._verifyCheckPending;
            const verifyReq = root._pendingVerifyPkgs.slice();
            root._verifyCheckPending = false;
            root._pendingVerifyPkgs = [];

            if (errMsg !== "") {
                root.lastError = wasVerify ? ("Post-update verification failed: " + errMsg) : errMsg;
                if (wasVerify) {
                    root.triggerStatusEvent("Verification failed", "danger", true);
                } else if (root.manualCheckPending) {
                    root.triggerStatusEvent("Update check failed", "danger", true);
                }
            } else {
                const prevCount = root.packages.length;
                root.packages = parsed;
                root.userOverrodeBackupToggle = false;
                root.syncBackupRecommendation();

                if (wasVerify) {
                    const byId = {};
                    const byName = {};
                    for (let j = 0; j < parsed.length; ++j) {
                        byId[parsed[j].id] = parsed[j];
                        byName[parsed[j].name] = parsed[j];
                    }
                    const unverified = [];
                    for (let j = 0; j < verifyReq.length; ++j) {
                        const r = verifyReq[j];
                        const still = byId[r.id] || byName[r.name];
                        if (still && (still.oldVersion === r.oldVersion || (r.oldVersion === "" && still.newVersion === r.newVersion))) {
                            unverified.push(r.name);
                        }
                    }
                    if (unverified.length > 0) {
                        const head = unverified.slice(0, 4).join(", ");
                        const tail = unverified.length > 4 ? (" +" + (unverified.length - 4)) : "";
                        root.lastError = "Verification failed: " + unverified.length + " package(s) not upgraded (" + head + tail + ")";
                        root.triggerStatusEvent("Partial update (" + unverified.length + " skipped)", "warn", true);
                    } else {
                        root.lastError = "";
                        root.triggerStatusEvent(parsed.length === 0 ? "Updates installed" : (parsed.length + (parsed.length === 1 ? " update left" : " updates left")), "ok", true);
                    }
                } else {
                    root.lastError = "";
                    if (parsed.length > 0 && (parsed.length !== prevCount || root.manualCheckPending)) {
                        root.triggerStatusEvent(parsed.length + (parsed.length === 1 ? " update ready" : " updates ready"), "info", true);
                    } else if (parsed.length === 0 && root.manualCheckPending) {
                        root.triggerStatusEvent("System up to date", "ok", true);
                    }
                }
            }
            root.manualCheckPending = false;
        }

        command: [
            "sh", "-c",
            [
                'DNF_PY=$(cat <<\'PY\'\nimport re, subprocess, sys\ntool, use_beta, is_manual = sys.argv[1:4]\ncmd = [tool, "check-upgrade", "-q"]\nif use_beta == "1": cmd.append("--enablerepo=updates-testing")\nif is_manual == "1": cmd.append("--refresh")\nres = subprocess.run(cmd, capture_output=True, text=True)\nif res.returncode == 0: sys.exit(0)\nif res.returncode != 100:\n    errs = [ln.strip() for ln in (res.stderr or res.stdout or "").splitlines() if ln.strip()]\n    print("ERR|" + (errs[-1] if errs else "Unable to check for updates"))\n    sys.exit(1)\ndef evr_key(evr):\n    epoch = 0\n    if ":" in evr:\n        ep, evr = evr.split(":", 1)\n        try: epoch = int(ep)\n        except ValueError: epoch = 0\n    def segs(s):\n        out = []\n        for x in re.findall(r"\\d+|[A-Za-z]+|~", s):\n            if x == "~": out.append((-1, ""))\n            elif x.isdigit(): out.append((1, int(x)))\n            else: out.append((0, x))\n        return out\n    ver, _, rel = evr.partition("-")\n    return (epoch, segs(ver), segs(rel))\nrpm_out = subprocess.check_output(["rpm", "-qa", "--qf", "%{NAME}.%{ARCH}\\t%{NAME}\\t%{EPOCH}\\t%{VERSION}-%{RELEASE}\\n"], text=True)\nby_id, by_name = {}, {}\nfor ln in rpm_out.splitlines():\n    ps = ln.split("\\t")\n    if len(ps) != 4: continue\n    pid, nm, ep, vr = ps\n    evr = f"{ep}:{vr}" if (ep and ep != "(none)") else vr\n    k = evr_key(evr)\n    if pid not in by_id or k > by_id[pid][0]: by_id[pid] = (k, evr)\n    if nm not in by_name or k > by_name[nm][0]: by_name[nm] = (k, evr)\nentries, pending_id = [], None\nfor raw in res.stdout.splitlines():\n    s = raw.strip()\n    if not s:\n        pending_id = None\n        continue\n    low = s.lower()\n    if low.startswith("obsoleting"): break\n    if low in ("upgrades", "security:", "bugfix:", "enhancement:") or low.startswith("last metadata"):\n        pending_id = None\n        continue\n    parts = s.split()\n    if raw[0].isspace():\n        if pending_id and len(parts) >= 2 and not parts[1].startswith("@"):\n            entries.append((pending_id, parts[0]))\n        pending_id = None\n        continue\n    if len(parts) == 1 and "." in parts[0]:\n        pending_id = parts[0]\n        continue\n    pending_id = None\n    if len(parts) >= 3 and "." in parts[0] and not parts[2].startswith("@"):\n        entries.append((parts[0], parts[1]))\n    elif len(parts) == 2 and "." in parts[0]:\n        entries.append((parts[0], parts[1]))\nfor pkg_id, new_ver in entries:\n    name = pkg_id.rsplit(".", 1)[0]\n    old_ver = (by_id.get(pkg_id) or by_name.get(name) or (None, ""))[1]\n    print(f"PKG|{name}|{old_ver}|{new_ver}|{pkg_id}")\nPY\n)',
                'if command -v dnf5 >/dev/null 2>&1; then',
                '    echo "BACKEND|dnf5"',
                '    python3 -c "$DNF_PY" dnf5 "$1" "$2"',
                '    exit $?',
                'elif command -v dnf >/dev/null 2>&1; then',
                '    echo "BACKEND|dnf"',
                '    python3 -c "$DNF_PY" dnf "$1" "$2"',
                '    exit $?',
                'elif command -v pacman >/dev/null 2>&1; then',
                '    echo "BACKEND|pacman"',
                '    if command -v checkupdates >/dev/null 2>&1; then',
                '        ERR_FILE=$(mktemp)',
                '        OUT=$(checkupdates 2>"$ERR_FILE"); RC=$?',
                '        ERR_TXT=$(tr "\\r\\n" "  " < "$ERR_FILE" | sed "s/[[:space:]]*$//")',
                '        rm -f "$ERR_FILE"',
                '        if [ $RC -eq 2 ]; then exit 0; fi',
                '        if [ $RC -ne 0 ]; then echo "ERR|${ERR_TXT:-Unable to check for updates}"; exit 1; fi',
                '    else',
                '        OUT=$(pacman -Qu 2>/dev/null); RC=$?',
                '        if [ $RC -ne 0 ] && [ -z "$OUT" ]; then exit 0; fi',
                '    fi',
                '    printf "%s\\n" "$OUT" | while IFS= read -r line; do',
                '        case "$line" in *"[ignored]"*) continue ;; esac',
                '        set -f; set -- $line; set +f',
                '        [ $# -lt 4 ] && continue',
                '        printf "PKG|%s|%s|%s|%s\\n" "$1" "$2" "$4" "$1"',
                '    done',
                '    exit 0',
                'elif command -v apt-get >/dev/null 2>&1 && command -v apt >/dev/null 2>&1; then',
                '    echo "BACKEND|apt"',
                '    OUT=$(LANGUAGE=C LC_ALL=C apt list --upgradable 2>/dev/null); RC=$?',
                '    if [ $RC -ne 0 ]; then echo "ERR|Unable to check for apt updates"; exit 1; fi',
                '    printf "%s\\n" "$OUT" | python3 -c \'import re, sys\nfor ln in sys.stdin:\n    m = re.match(r"^([^/\\s]+)/\\S+\\s+(\\S+)\\s+\\S+\\s+\\[upgradable from:\\s*([^\\]]+)\\]", ln.strip())\n    if m: print(f"PKG|{m.group(1)}|{m.group(3).strip()}|{m.group(2)}|{m.group(1)}")\'',
                '    exit 0',
                'else',
                '    echo "ERR|No supported package system found"',
                '    exit 1',
                'fi'
            ].join("\n"),
            "_",
            root.betaUpdatesEnabled ? "1" : "0",
            root.manualCheckPending ? "1" : "0"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                checkProc.outBuf = text || "";
                checkProc._stdoutDone = true;
                checkProc.tryFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                checkProc.errBuf = text || "";
                checkProc._stderrDone = true;
                checkProc.tryFinish();
            }
        }
        onExited: function(exitCode) {
            checkProc._exitCode = exitCode;
            checkProc._exited = true;
            checkProc.tryFinish();
        }
    }

    Timer {
        id: cleanCacheProgressTimer
        interval: 250
        repeat: true
        onTriggered: {
            if (!root.cleaningCache) {
                stop();
                return;
            }
            if (root.cleanCacheProgress < 99) {
                const step = root.cleanCacheProgress < 50 ? 5 : (root.cleanCacheProgress < 80 ? 2 : 1);
                root.cleanCacheProgress = Math.min(99, root.cleanCacheProgress + step);
            }
        }
    }

    Timer {
        id: previewCleanCacheTimer
        interval: 1200
        repeat: false
        onTriggered: {
            cleanCacheProgressTimer.stop();
            root.cleanCacheProgress = 100;
            root.cleaningCache = false;
            root.cacheSizeText = "0 B";
            root.lastError = "";
            root.triggerStatusEvent("Package cache cleaned (100%)", "ok", true);
        }
    }

    Process {
        id: cacheSizeProc
        stdout: StdioCollector {
            onStreamFinished: {
                const val = text.trim();
                if (val !== "") root.cacheSizeText = val;
            }
        }
    }

    function extractShellError(raw) {
        const lines = (raw || "").split("\n").map(s => s.trim()).filter(s => s.length > 0);
        if (lines.length === 0) return "";
        const filtered = lines.filter(ln => !/^From\s+/i.test(ln) && !/^hint:/i.test(ln) && !/^[0-9a-f]+\.\.[0-9a-f]+\s+/i.test(ln));
        const pool = filtered.length > 0 ? filtered : lines;
        for (let i = 0; i < pool.length; ++i) {
            if (/^(fatal:|error:|\[paithosh\])/i.test(pool[i])) {
                return pool[i];
            }
        }
        return pool[pool.length - 1];
    }

    function checkShellUpdate() {
        if (shellChecking || shellUpdating) return;
        shellChecking = true;
        shellCheckedOnce = true;
        shellUpdateError = "";
        shellCheckProc.outBuf = "";
        shellCheckProc.errBuf = "";
        shellCheckProc._stdoutDone = false;
        shellCheckProc._stderrDone = false;
        shellCheckProc._exited = false;
        shellCheckProc._exitCode = -1;
        shellCheckProc.running = false;
        shellCheckProc.running = true;
    }

    function updateShell() {
        if (shellChecking || shellUpdating || hyprSyncing) return;
        shellUpdating = true;
        shellUpdateError = "";
        shellUpdateProc.outBuf = "";
        shellUpdateProc.errBuf = "";
        shellUpdateProc._stdoutDone = false;
        shellUpdateProc._stderrDone = false;
        shellUpdateProc._exited = false;
        shellUpdateProc._exitCode = -1;
        triggerStatusEvent("Updating Paithosh Shell...", "info", false);
        shellUpdateProc.running = false;
        shellUpdateProc.running = true;
    }

    function checkHyprSyncStatus() {
        if (hyprSyncStatusProc.running || hyprSyncing) return;
        hyprSyncStatusProc.outBuf = "";
        hyprSyncStatusProc.errBuf = "";
        hyprSyncStatusProc._stdoutDone = false;
        hyprSyncStatusProc._stderrDone = false;
        hyprSyncStatusProc._exited = false;
        hyprSyncStatusProc._exitCode = -1;
        hyprSyncStatusProc.running = true;
    }

    function syncHyprConfig(mode) {
        if (hyprSyncing || shellUpdating) return;
        const syncMode = (mode === "update") ? "update" : "replace";
        hyprSyncing = true;
        hyprSyncError = "";
        hyprSyncProc.outBuf = "";
        hyprSyncProc.errBuf = "";
        hyprSyncProc._stdoutDone = false;
        hyprSyncProc._stderrDone = false;
        hyprSyncProc._exited = false;
        hyprSyncProc._exitCode = -1;
        hyprSyncProc.command = [
            "bash", root.shellProjectRoot + "/installer/lib/sync-hypr.sh",
            "--repo-root", root.shellProjectRoot,
            "--mode", syncMode
        ];
        triggerStatusEvent(syncMode === "update" ? "Updating Hyprland config..." : "Syncing Hyprland defaults...", "info", false);
        hyprSyncProc.running = false;
        hyprSyncProc.running = true;
    }

    function clearHyprFileDiff() {
        hyprDiffFile = "";
        hyprDiffLines = [];
        hyprDiffAdded = 0;
        hyprDiffDeleted = 0;
        hyprDiffTruncated = false;
        hyprDiffError = "";
        hyprDiffLoading = false;
    }

    function loadHyprFileDiff(relPath) {
        if (!relPath || relPath.startsWith("/") || relPath.indexOf("..") !== -1) return;
        if (hyprDiffFile === relPath && !hyprDiffLoading) {
            clearHyprFileDiff();
            return;
        }
        hyprDiffFile = relPath;
        hyprDiffLines = [];
        hyprDiffAdded = 0;
        hyprDiffDeleted = 0;
        hyprDiffTruncated = false;
        hyprDiffError = "";
        hyprDiffLoading = true;
        hyprDiffProc.outBuf = "";
        hyprDiffProc.errBuf = "";
        hyprDiffProc._stdoutDone = false;
        hyprDiffProc._stderrDone = false;
        hyprDiffProc._exited = false;
        hyprDiffProc.command = [
            "bash", "-c",
            "python3 \"$2/installer/lib/hypr-config-diff.py\" diff \"$2/defaults/hypr/$1\" \"${XDG_CONFIG_HOME:-$HOME/.config}/hypr/$1\" \"$1\"",
            "_", relPath, root.shellProjectRoot
        ];
        hyprDiffProc.running = false;
        hyprDiffProc.running = true;
    }

    function checkRequiredDeps(onDone) {
        if (depsAuditProc.running) {
            if (typeof onDone === "function") depsAuditProc._callbacks.push(onDone);
            return;
        }
        checkingDeps = true;
        depsError = "";
        depsAuditProc._callbacks = typeof onDone === "function" ? [onDone] : [];
        depsAuditProc.outBuf = "";
        depsAuditProc.errBuf = "";
        depsAuditProc._stdoutDone = false;
        depsAuditProc._stderrDone = false;
        depsAuditProc._exited = false;
        depsAuditProc._exitCode = -1;
        depsAuditProc.running = true;
    }

    function installMissingCoreDeps(onDone) {
        const cb = typeof onDone === "function" ? onDone : null;
        if (installingDeps) {
            if (cb) cb(false);
            return;
        }
        if (missingCorePkgs === "") {
            if (cb) cb(true);
            return;
        }
        const aurRawStdin = missingCorePkgs.split(",").indexOf("quickshell-git") !== -1;
        const argv = [
            "bash", root.shellProjectRoot + "/installer/lib/apply.sh",
            "--packages-only",
            "--packages", missingCorePkgs
        ];
        if (aurRawStdin) argv.push("--sudo-stdin");
        installingDeps = true;
        depsError = "";
        BackupService.runPrivileged(
            "Install Required Shell Packages",
            "Install mandatory Paithosh dependencies (" + missingCorePkgs + ").",
            "Install Required",
            argv,
            (ok, parsed, out, err) => {
                root.installingDeps = false;
                if (ok) {
                    root.checkRequiredDeps((hasMissing) => {
                        CursorService.checkDeps(() => {
                            if (CursorService.depsReady) CursorService.applyNow(true);
                        });
                        if (hasMissing) {
                            root.depsError = "Verification failed — still missing: " + root.missingCorePkgs;
                            root.triggerStatusEvent("Required packages incomplete", "danger", true);
                            if (cb) cb(false);
                        } else {
                            root.depsError = "";
                            root.triggerStatusEvent("Required packages installed", "ok", true);
                            if (cb) cb(true);
                        }
                    });
                } else {
                    const msg = BackupService.cleanErrorMessage(parsed, err, "Authentication cancelled or package install failed");
                    root.depsError = msg;
                    root.triggerStatusEvent("Required package install failed", "danger", true);
                    if (cb) cb(false);
                }
            },
            null,
            aurRawStdin,
            aurRawStdin
        );
    }

    Timer {
        id: shellReloadTimer
        interval: 400
        repeat: false
        onTriggered: {
            root.shellReloadRequested(false, "Shell Updated");
        }
    }

    Process {
        id: shellCheckProc
        property string outBuf: ""
        property string errBuf: ""
        property bool _stdoutDone: false
        property bool _stderrDone: false
        property bool _exited: false
        property int _exitCode: -1

        function tryFinish() {
            if (!_stdoutDone || !_stderrDone || !_exited) return;
            _exited = false;
            root.shellChecking = false;
            const prevBehind = root.shellUpdateBehind;
            const lines = (outBuf || "").trim().split("\n");
            let err = "";
            const commits = [];
            const changelogLines = [];
            for (let i = 0; i < lines.length; ++i) {
                const eq = lines[i].indexOf("=");
                if (eq === -1) continue;
                const k = lines[i].slice(0, eq);
                const rawV = lines[i].slice(eq + 1).replace(/\r$/, "");
                const v = rawV.trim();
                if (k === "ERR") err = v;
                else if (k === "BRANCH") root.shellBranch = v;
                else if (k === "LOCAL") root.shellCommit = v;
                else if (k === "CUR_TAG") root.shellCurrentTag = v;
                else if (k === "TARGET") root.shellTargetVersion = v;
                else if (k === "BEHIND") root.shellUpdateBehind = parseInt(v, 10) || 0;
                else if (k === "AHEAD") root.shellUpdateAhead = parseInt(v, 10) || 0;
                else if (k === "SUMMARY") root.shellLatestSummary = v;
                else if (k === "CHANGELOG") changelogLines.push(rawV);
                else if (k === "COMMIT" && v !== "") {
                    const sp = v.indexOf(" ");
                    if (sp !== -1) commits.push({ hash: v.slice(0, sp), subject: v.slice(sp + 1).trim() });
                    else commits.push({ hash: v, subject: "" });
                }
            }
            root.shellCommits = (_exitCode === 0 && root.shellUpdateStream !== "release" && root.shellUpdateBehind > 0) ? commits : [];
            root.shellReleaseChangelog = (_exitCode === 0 && root.shellUpdateStream === "release" && (root.shellUpdateBehind > 0 || root.shellUpdateAhead > 0))
                ? changelogLines.join("\n").trim()
                : "";
            if (_exitCode !== 0) {
                const fallbackErr = root.extractShellError(errBuf);
                root.shellUpdateError = err !== "" ? err : (fallbackErr !== "" ? fallbackErr : "Failed to check shell updates");
            } else {
                root.shellUpdateError = "";
                if (root.shellUpdateBehind > 0 && root.shellUpdateBehind > prevBehind) {
                    const label = root.shellUpdateStream === "release" && root.shellTargetVersion !== ""
                        ? ("Paithosh Shell " + root.shellTargetVersion + " available")
                        : ("Paithosh Shell update available (" + root.shellUpdateBehind + ")");
                    root.triggerStatusEvent(label, "info", true);
                }
            }
            root.checkRequiredDeps();
        }

        command: [
            "sh", "-c",
            "dir=\"$1\"; stream=\"${2:-main}\"; " +
            "git -C \"$dir\" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo 'ERR=Not a git repository'; exit 1; }; " +
            "branch=$(git -C \"$dir\" symbolic-ref --short HEAD 2>/dev/null || echo HEAD); " +
            "local_hash=$(git -C \"$dir\" rev-parse --short HEAD 2>/dev/null || echo ''); " +
            "cur_tag=$(git -C \"$dir\" describe --tags --exact-match HEAD 2>/dev/null || echo ''); " +
            "remote=$(git -C \"$dir\" config \"branch.$branch.remote\" 2>/dev/null || echo origin); " +
            "git -C \"$dir\" remote get-url \"$remote\" >/dev/null 2>&1 || remote=origin; " +
            "if [ \"$(git -C \"$dir\" rev-parse --is-shallow-repository 2>/dev/null || echo false)\" = \"true\" ]; then " +
                "GIT_TERMINAL_PROMPT=0 timeout 60 git -C \"$dir\" fetch --unshallow --tags --quiet \"$remote\" 2>/dev/null || true; " +
            "fi; " +
            "if [ \"$stream\" = \"release\" ]; then " +
                "GIT_TERMINAL_PROMPT=0 timeout 30 git -C \"$dir\" fetch --tags --quiet \"$remote\" 2>/dev/null || { echo \"ERR=Failed to fetch releases from $remote\"; exit 1; }; " +
                "latest_tag=$(git -C \"$dir\" tag -l 'v*' --sort=-v:refname 2>/dev/null | head -n1); " +
                "[ -z \"$latest_tag\" ] && latest_tag=$(git -C \"$dir\" tag -l --sort=-v:refname 2>/dev/null | head -n1); " +
                "[ -n \"$latest_tag\" ] || { echo 'ERR=No release tags found in repository'; exit 1; }; " +
                "head_full=$(git -C \"$dir\" rev-parse HEAD 2>/dev/null || echo ''); " +
                "tag_full=$(git -C \"$dir\" rev-parse \"${latest_tag}^{commit}\" 2>/dev/null || echo ''); " +
                "if [ \"$head_full\" = \"$tag_full\" ]; then behind=0; ahead=0; " +
                "else behind=$(git -C \"$dir\" rev-list --count \"HEAD..${latest_tag}\" 2>/dev/null || echo 0); " +
                "ahead=$(git -C \"$dir\" rev-list --count \"${latest_tag}..HEAD\" 2>/dev/null || echo 0); fi; " +
                "summary=''; [ \"$behind\" -gt 0 ] 2>/dev/null && summary=$(git -C \"$dir\" log -1 --pretty=%s \"$latest_tag\" 2>/dev/null || echo ''); " +
                "printf 'BRANCH=%s\\nLOCAL=%s\\nCUR_TAG=%s\\nTARGET=%s\\nBEHIND=%s\\nAHEAD=%s\\nSUMMARY=%s\\n' \"$branch\" \"$local_hash\" \"$cur_tag\" \"$latest_tag\" \"$behind\" \"$ahead\" \"$summary\"; " +
                "([ \"$behind\" -gt 0 ] || [ \"$ahead\" -gt 0 ]) 2>/dev/null && git -C \"$dir\" tag -l --format='%(contents)' \"$latest_tag\" 2>/dev/null | sed 's/^/CHANGELOG=/' || true; " +
            "else " +
                "GIT_TERMINAL_PROMPT=0 timeout 30 git -C \"$dir\" fetch --quiet \"$remote\" 2>/dev/null || { echo \"ERR=Failed to fetch from $remote\"; exit 1; }; " +
                "if git -C \"$dir\" rev-parse --verify \"${remote}/main\" >/dev/null 2>&1; then target=\"${remote}/main\"; " +
                "elif git -C \"$dir\" rev-parse --verify \"${remote}/HEAD\" >/dev/null 2>&1; then target=$(git -C \"$dir\" symbolic-ref --short \"refs/remotes/${remote}/HEAD\" 2>/dev/null || echo \"${remote}/master\"); " +
                "elif git -C \"$dir\" rev-parse --verify \"${remote}/master\" >/dev/null 2>&1; then target=\"${remote}/master\"; " +
                "else echo \"ERR=Remote main branch not found on $remote\"; exit 1; fi; " +
                "behind=$(git -C \"$dir\" rev-list --count \"HEAD..${target}\" 2>/dev/null || echo 0); " +
                "ahead=$(git -C \"$dir\" rev-list --count \"${target}..HEAD\" 2>/dev/null || echo 0); " +
                "summary=''; [ \"$behind\" -gt 0 ] 2>/dev/null && summary=$(git -C \"$dir\" log -1 --pretty=%s \"$target\" 2>/dev/null || echo ''); " +
                "printf 'BRANCH=%s\\nLOCAL=%s\\nCUR_TAG=%s\\nTARGET=%s\\nBEHIND=%s\\nAHEAD=%s\\nSUMMARY=%s\\n' \"$branch\" \"$local_hash\" \"$cur_tag\" \"$target\" \"$behind\" \"$ahead\" \"$summary\"; " +
                "[ \"$behind\" -gt 0 ] 2>/dev/null && git -C \"$dir\" log --pretty=format:'COMMIT=%h %s' -n 30 \"HEAD..${target}\" 2>/dev/null || true; " +
            "fi",
            "sh", root.shellProjectRoot, root.shellUpdateStream
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                shellCheckProc.outBuf = text || "";
                shellCheckProc._stdoutDone = true;
                shellCheckProc.tryFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                shellCheckProc.errBuf = text || "";
                shellCheckProc._stderrDone = true;
                shellCheckProc.tryFinish();
            }
        }
        onExited: function(exitCode) {
            shellCheckProc._exitCode = exitCode;
            shellCheckProc._exited = true;
            shellCheckProc.tryFinish();
        }
    }

    Process {
        id: shellUpdateProc
        property string outBuf: ""
        property string errBuf: ""
        property bool _stdoutDone: false
        property bool _stderrDone: false
        property bool _exited: false
        property int _exitCode: -1

        function tryFinish() {
            if (!_stdoutDone || !_stderrDone || !_exited) return;
            _exited = false;
            root.shellUpdating = false;
            if (_exitCode === 0) {
                const lines = (outBuf || "").trim().split("\n");
                let hyprSyncWarn = false;
                for (let i = 0; i < lines.length; ++i) {
                    const eq = lines[i].indexOf("=");
                    if (eq === -1) continue;
                    const k = lines[i].slice(0, eq);
                    const v = lines[i].slice(eq + 1).trim();
                    if (k === "BRANCH") root.shellBranch = v;
                    else if (k === "LOCAL") root.shellCommit = v;
                    else if (k === "CUR_TAG") root.shellCurrentTag = v;
                    else if (k === "HYPR_SYNC_WARN") hyprSyncWarn = true;
                }
                root.shellUpdateBehind = 0;
                root.shellUpdateAhead = 0;
                root.shellLatestSummary = "";
                root.shellReleaseChangelog = "";
                root.shellCommits = [];
                root.shellUpdateError = "";
                if (hyprSyncWarn) {
                    root.hyprSyncError = "Hyprland config auto-sync reported a warning after shell update";
                }
                root.checkHyprSyncStatus();
                root.checkRequiredDeps((hasMissing) => {
                    if (hasMissing) {
                        root.triggerStatusEvent("Installing required shell packages...", "info", false);
                        root.installMissingCoreDeps((ok) => {
                            root.triggerStatusEvent(ok ? "Paithosh Shell updated — reloading..." : "Updated shell (install missing deps in Updates)", ok ? "ok" : "warn", true);
                            shellReloadTimer.interval = ok ? 400 : 2200;
                            shellReloadTimer.restart();
                        });
                    } else {
                        root.triggerStatusEvent("Paithosh Shell updated — reloading...", "ok", true);
                        shellReloadTimer.interval = 400;
                        shellReloadTimer.restart();
                    }
                });
            } else {
                const parsedErr = root.extractShellError(errBuf);
                root.shellUpdateError = parsedErr !== "" ? parsedErr : (root.shellUpdateStream === "release" ? "Release checkout failed" : "Fast-forward pull failed");
                root.triggerStatusEvent("Shell update failed", "danger", true);
            }
        }

        command: [
            "sh", "-c",
            "set -eu; dir=\"$1\"; stream=\"${2:-main}\"; " +
            "git -C \"$dir\" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo 'Not a git repository' >&2; exit 1; }; " +
            "if ! git -C \"$dir\" diff --quiet || ! git -C \"$dir\" diff --cached --quiet; then " +
            "echo 'error: Local modifications in repository block update' >&2; exit 1; fi; " +
            "branch=$(git -C \"$dir\" symbolic-ref --short HEAD 2>/dev/null || true); " +
            "remote=$(git -C \"$dir\" config \"branch.${branch}.remote\" 2>/dev/null || echo origin); " +
            "git -C \"$dir\" remote get-url \"$remote\" >/dev/null 2>&1 || remote=origin; " +
            "if [ \"$(git -C \"$dir\" rev-parse --is-shallow-repository 2>/dev/null || echo false)\" = \"true\" ]; then " +
                "GIT_TERMINAL_PROMPT=0 timeout 60 git -C \"$dir\" fetch --unshallow --tags --quiet \"$remote\" 2>/dev/null || true; " +
            "fi; " +
            "if [ \"$stream\" = \"release\" ]; then " +
                "GIT_TERMINAL_PROMPT=0 timeout 30 git -C \"$dir\" fetch --tags --quiet \"$remote\"; " +
                "latest_tag=$(git -C \"$dir\" tag -l 'v*' --sort=-v:refname 2>/dev/null | head -n1); " +
                "[ -z \"$latest_tag\" ] && latest_tag=$(git -C \"$dir\" tag -l --sort=-v:refname 2>/dev/null | head -n1); " +
                "[ -n \"$latest_tag\" ] || { echo 'error: No release tags found in repository' >&2; exit 1; }; " +
                "git -C \"$dir\" checkout --quiet \"$latest_tag\"; " +
            "else " +
                "GIT_TERMINAL_PROMPT=0 timeout 30 git -C \"$dir\" fetch --quiet \"$remote\"; " +
                "if git -C \"$dir\" rev-parse --verify \"${remote}/main\" >/dev/null 2>&1; then target_branch=main; target=\"${remote}/main\"; " +
                "elif git -C \"$dir\" rev-parse --verify \"${remote}/HEAD\" >/dev/null 2>&1; then target=$(git -C \"$dir\" symbolic-ref --short \"refs/remotes/${remote}/HEAD\" 2>/dev/null || echo \"${remote}/master\"); target_branch=\"${target#*/}\"; " +
                "elif git -C \"$dir\" rev-parse --verify \"${remote}/master\" >/dev/null 2>&1; then target_branch=master; target=\"${remote}/master\"; " +
                "else echo \"error: Remote main branch not found on $remote\" >&2; exit 1; fi; " +
                "if [ \"$branch\" != \"$target_branch\" ]; then " +
                    "if git -C \"$dir\" show-ref --verify --quiet \"refs/heads/${target_branch}\"; then git -C \"$dir\" checkout --quiet \"$target_branch\"; " +
                    "else git -C \"$dir\" checkout --quiet -b \"$target_branch\" \"$target\"; fi; " +
                "fi; " +
                "GIT_TERMINAL_PROMPT=0 timeout 30 git -C \"$dir\" merge --ff-only --quiet \"$target\"; " +
            "fi; " +
            "printf 'BRANCH=%s\\nLOCAL=%s\\nCUR_TAG=%s\\n' \"$(git -C \"$dir\" symbolic-ref --short HEAD 2>/dev/null || echo HEAD)\" \"$(git -C \"$dir\" rev-parse --short HEAD 2>/dev/null || echo '')\" \"$(git -C \"$dir\" describe --tags --exact-match HEAD 2>/dev/null || echo '')\"; " +
            "if [ -f \"$dir/installer/lib/sync-hypr.sh\" ]; then " +
            "bash \"$dir/installer/lib/sync-hypr.sh\" --repo-root \"$dir\" --mode update || echo 'HYPR_SYNC_WARN=1'; fi",
            "sh", root.shellProjectRoot, root.shellUpdateStream
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                shellUpdateProc.outBuf = text || "";
                shellUpdateProc._stdoutDone = true;
                shellUpdateProc.tryFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                shellUpdateProc.errBuf = text || "";
                shellUpdateProc._stderrDone = true;
                shellUpdateProc.tryFinish();
            }
        }
        onExited: function(exitCode) {
            shellUpdateProc._exitCode = exitCode;
            shellUpdateProc._exited = true;
            shellUpdateProc.tryFinish();
        }
    }

    Process {
        id: hyprSyncStatusProc
        property string outBuf: ""
        property string errBuf: ""
        property bool _stdoutDone: false
        property bool _stderrDone: false
        property bool _exited: false
        property int _exitCode: -1

        function tryFinish() {
            if (!_stdoutDone || !_stderrDone || !_exited) return;
            _exited = false;
            if (_exitCode !== 0) {
                const parsedErr = root.extractShellError(errBuf);
                if (parsedErr !== "") root.hyprSyncError = parsedErr;
                return;
            }
            try {
                const data = JSON.parse((outBuf || "").trim());
                const st = data.state || "";
                const modFiles = Array.isArray(data.modifiedFiles) ? data.modifiedFiles : [];
                const modCount = modFiles.length;
                const pendCount = (Array.isArray(data.pendingFiles) ? data.pendingFiles.length : 0) + (data.rootMismatch ? 1 : 0);
                root.hyprSyncState = st;
                root.hyprModifiedCount = modCount;
                root.hyprModifiedFiles = modFiles;
                root.hyprPendingCount = pendCount;
                root.hyprSyncError = "";
                if (st === "synced") {
                    root.hyprSyncMessage = modCount > 0
                        ? ("Synced with defaults • " + modCount + " custom file(s) preserved")
                        : "Synced with defaults/hypr";
                } else if (st === "outdated") {
                    root.hyprSyncMessage = pendCount + (pendCount === 1 ? " default update available" : " default updates available")
                        + (modCount > 0 ? (" • " + modCount + " custom preserved") : "");
                } else if (st === "unmanaged") {
                    root.hyprSyncMessage = "Custom ~/.config/hypr detected (auto-sync skipped; click Sync Defaults to back up & apply)";
                } else if (st === "missing") {
                    root.hyprSyncMessage = "~/.config/hypr not configured yet";
                } else {
                    root.hyprSyncMessage = "";
                }
            } catch (e) {}
        }

        command: [
            "bash", root.shellProjectRoot + "/installer/lib/sync-hypr.sh",
            "--repo-root", root.shellProjectRoot,
            "--status"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                hyprSyncStatusProc.outBuf = text || "";
                hyprSyncStatusProc._stdoutDone = true;
                hyprSyncStatusProc.tryFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                hyprSyncStatusProc.errBuf = text || "";
                hyprSyncStatusProc._stderrDone = true;
                hyprSyncStatusProc.tryFinish();
            }
        }
        onExited: function(exitCode) {
            hyprSyncStatusProc._exitCode = exitCode;
            hyprSyncStatusProc._exited = true;
            hyprSyncStatusProc.tryFinish();
        }
    }

    Process {
        id: hyprDiffProc
        property string outBuf: ""
        property string errBuf: ""
        property bool _stdoutDone: false
        property bool _stderrDone: false
        property bool _exited: false

        function tryFinish() {
            if (!_stdoutDone || !_stderrDone || !_exited) return;
            _exited = false;
            root.hyprDiffLoading = false;
            try {
                const data = JSON.parse((outBuf || "").trim());
                if (data.error) {
                    root.hyprDiffError = data.error;
                    root.hyprDiffLines = [];
                    return;
                }
                const lines = Array.isArray(data.lines) ? data.lines : [];
                if (lines.length === 0) {
                    root.hyprDiffError = "No manual custom diff (Settings-only changes are ignored)";
                    root.hyprDiffLines = [];
                    root.hyprDiffAdded = 0;
                    root.hyprDiffDeleted = 0;
                    root.hyprDiffTruncated = false;
                    return;
                }
                root.hyprDiffLines = lines;
                root.hyprDiffAdded = data.added || 0;
                root.hyprDiffDeleted = data.deleted || 0;
                root.hyprDiffTruncated = !!data.truncated;
                root.hyprDiffError = "";
            } catch (e) {
                const parsedErr = root.extractShellError(errBuf);
                root.hyprDiffError = parsedErr !== "" ? parsedErr : "Failed to parse diff output";
                root.hyprDiffLines = [];
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                hyprDiffProc.outBuf = text || "";
                hyprDiffProc._stdoutDone = true;
                hyprDiffProc.tryFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                hyprDiffProc.errBuf = text || "";
                hyprDiffProc._stderrDone = true;
                hyprDiffProc.tryFinish();
            }
        }
        onExited: function() {
            hyprDiffProc._exited = true;
            hyprDiffProc.tryFinish();
        }
    }

    Process {
        id: hyprSyncProc
        property string outBuf: ""
        property string errBuf: ""
        property bool _stdoutDone: false
        property bool _stderrDone: false
        property bool _exited: false
        property int _exitCode: -1

        function tryFinish() {
            if (!_stdoutDone || !_stderrDone || !_exited) return;
            _exited = false;
            root.hyprSyncing = false;
            root.checkHyprSyncStatus();
            if (_exitCode === 0) {
                root.hyprSyncError = "";
                KeybindService.refresh();
                root.triggerStatusEvent("Hyprland config synced", "ok", true);
            } else {
                const parsedErr = root.extractShellError(errBuf);
                root.hyprSyncError = parsedErr !== "" ? parsedErr : "Failed to sync Hyprland config";
                root.triggerStatusEvent("Hyprland sync failed", "danger", true);
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                hyprSyncProc.outBuf = text || "";
                hyprSyncProc._stdoutDone = true;
                hyprSyncProc.tryFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                hyprSyncProc.errBuf = text || "";
                hyprSyncProc._stderrDone = true;
                hyprSyncProc.tryFinish();
            }
        }
        onExited: function(exitCode) {
            hyprSyncProc._exitCode = exitCode;
            hyprSyncProc._exited = true;
            hyprSyncProc.tryFinish();
        }
    }

    Process {
        id: depsAuditProc
        property string outBuf: ""
        property string errBuf: ""
        property bool _stdoutDone: false
        property bool _stderrDone: false
        property bool _exited: false
        property int _exitCode: -1
        property var _callbacks: []
        command: ["bash", root.shellProjectRoot + "/installer/lib/audit.sh", "--json"]

        function tryFinish() {
            if (!_stdoutDone || !_stderrDone || !_exited) return;
            _exited = false;
            root.checkingDeps = false;
            const cbs = depsAuditProc._callbacks.slice();
            depsAuditProc._callbacks = [];
            let hasMissing = false;
            if (_exitCode === 0) {
                try {
                    const data = JSON.parse(depsAuditProc.outBuf.trim());
                    const pkgs = Array.isArray(data.packages) ? data.packages : [];
                    const missing = [];
                    const tokList = [];
                    for (let i = 0; i < pkgs.length; ++i) {
                        const p = pkgs[i];
                        if (!p.installed && (p.required || p.group === "core")) {
                            missing.push(p);
                            const toks = String(p.pkg || "").split(/\s+/);
                            for (let j = 0; j < toks.length; ++j) {
                                if (toks[j] !== "" && tokList.indexOf(toks[j]) === -1) tokList.push(toks[j]);
                            }
                        }
                    }
                    root.missingCoreDeps = missing;
                    root.missingCorePkgs = tokList.join(",");
                    hasMissing = missing.length > 0 && root.missingCorePkgs !== "";
                } catch (e) {
                    root.depsError = "Failed to parse dependency audit";
                }
            } else {
                const parsedErr = root.extractShellError(depsAuditProc.errBuf);
                root.depsError = parsedErr !== "" ? parsedErr : ("Dependency audit failed (exit " + _exitCode + ")");
            }
            for (let k = 0; k < cbs.length; ++k) {
                cbs[k](hasMissing);
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                depsAuditProc.outBuf = text || "";
                depsAuditProc._stdoutDone = true;
                depsAuditProc.tryFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                depsAuditProc.errBuf = text || "";
                depsAuditProc._stderrDone = true;
                depsAuditProc.tryFinish();
            }
        }
        onExited: (code) => {
            depsAuditProc._exitCode = code;
            depsAuditProc._exited = true;
            depsAuditProc.tryFinish();
        }
    }
}
