pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Internal backend detection ("dnf5" | "dnf" | "pacman" | ""); never exposed in UI
    property string backendTool: ""
    readonly property bool isFedora: backendTool === "dnf5" || backendTool === "dnf"
    readonly property bool isArch: backendTool === "pacman"
    property bool checking: false
    property bool updating: false
    property bool cleaningCache: false
    property int cleanCacheProgress: 0
    property string cacheSizeText: ""
    property bool sudoPromptOpen: false
    property string sudoPromptError: ""
    property bool manualCheckPending: false
    property var packages: []
    property string lastError: ""
    property string lastCheckedText: ""

    // Auto-update schedule ("off" | "daily" | "weekly" | "monthly") & Fedora beta updates
    property string autoUpdateSchedule: "weekly"
    property bool betaUpdatesEnabled: false
    property double lastAutoUpdateMs: 0
    readonly property string settingsPath: (Quickshell.env("HOME") || "/tmp") + "/.config/paithosh/package-settings.json"

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
    property var shellCommits: []
    property string shellUpdateError: ""

    // Default Hyprland Lua config sync state
    property string hyprSyncState: "" // "synced" | "outdated" | "unmanaged" | "missing" | ""
    property string hyprSyncMessage: ""
    property string hyprSyncError: ""
    property bool hyprSyncing: false
    property int hyprModifiedCount: 0
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
            'mkdir -p "$(dirname "$1")" && printf "%s" "$2" > "$1"',
            "_", settingsPath, payload
        ];
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
        if (interval <= 0) return;
        const now = Date.now();
        if (lastAutoUpdateMs > 0 && (now - lastAutoUpdateMs) < interval) return;
        lastAutoUpdateMs = now;
        saveSettings();
        if (!updating && !checking && !backingUpBeforeUpdate) {
            checkUpdates(true);
        }
    }

    function checkUpdates(isManual) {
        if (checking || updating || backingUpBeforeUpdate) return;
        manualCheckPending = !!isManual;
        checking = true;
        lastError = "";
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
            const remaining = [];
            for (let i = 0; i < root.packages.length; ++i) {
                if (!root.packages[i].selected) remaining.push(root.packages[i]);
            }
            root.packages = remaining;
            root.userOverrodeBackupToggle = false;
            root.syncBackupRecommendation();
            root.lastError = "";
            root.lastCheckedText = Qt.formatTime(new Date(), "hh:mm");
            root.triggerStatusEvent(remaining.length === 0 ? "Updates installed" : (remaining.length + " updates left"), "ok", true);
            if (remaining.length === 0) {
                root.checkUpdates(false);
            }
        } else {
            const msg = BackupService.cleanErrorMessage(parsed, errMsg, "Authentication cancelled or update failed");
            root.lastError = msg;
            root.triggerStatusEvent("Update failed", "danger", true);
        }
    }

    function installSelected() {
        if (updating || checking || backingUpBeforeUpdate || selectedCount === 0) return;
        if (backendTool === "") {
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

        const selectedIds = [];
        for (let i = 0; i < packages.length; ++i) {
            if (packages[i].selected) selectedIds.push(packages[i].id);
        }
        const allSelected = selectedIds.length === packages.length;
        const useBeta = (betaUpdatesEnabled && isFedora) ? "1" : "0";
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
                "--"
            ].concat(selectedIds);

            BackupService.runPrivileged(
                "Pre-Update Snapshot & Upgrade",
                "Creates a verified Btrfs snapshot (" + sysId + ") before upgrading " + selectedCount + " package(s). Upgrade aborts if snapshot fails.",
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
            'TOOL="$1"; ALL="$2"; USE_BETA="$3"; shift 3',
            'if [ "$TOOL" = "dnf5" ] || [ "$TOOL" = "dnf" ]; then',
            '    BETA_FLAG=""; [ "$USE_BETA" = "1" ] && BETA_FLAG="--enablerepo=updates-testing"',
            '    if [ "$ALL" = "1" ]; then exec "$TOOL" upgrade -y $BETA_FLAG; else exec "$TOOL" upgrade -y $BETA_FLAG "$@"; fi',
            'elif [ "$TOOL" = "pacman" ]; then',
            '    if [ "$ALL" = "1" ]; then exec pacman -Syu --noconfirm; else exec pacman -S --noconfirm "$@"; fi',
            'fi',
            'exit 1'
        ].join("\n");
        updating = true;
        BackupService.runPrivileged(
            "System Package Upgrade",
            "Authorize upgrading " + selectedCount + " selected package(s) using " + backendTool + ".",
            "Install Updates",
            ["sh", "-c", script, "_", backendTool, allSelected ? "1" : "0", useBeta].concat(selectedIds),
            (ok, parsed, out, err) => root._finishInstall(ok, parsed, err)
        );
    }

    function refreshCacheSize() {
        if (backendTool === "") {
            if (cacheSizeText === "") cacheSizeText = "1.2 GB";
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
        cacheSizeProc.running = true;
    }

    function cleanCache() {
        if (checking || updating || backingUpBeforeUpdate || cleaningCache) return;
        cleanCacheProgress = 0;
        if (backendTool === "") {
            cleaningCache = true;
            cleanCacheProgressTimer.restart();
            previewCleanCacheTimer.restart();
            return;
        }
        sudoPromptError = "";
        sudoPromptOpen = true;
    }

    function cancelSudoPrompt() {
        sudoPromptOpen = false;
        sudoPromptError = "";
    }

    function submitSudoPassword(password) {
        if (!password || password.length === 0) {
            sudoPromptError = "Password cannot be empty";
            return;
        }
        let targetCmd = [];
        if (backendTool === "dnf5" || backendTool === "dnf") {
            targetCmd = ["sudo", "-S", "-k", "-p", "", backendTool, "clean", "all"];
        } else if (backendTool === "pacman") {
            targetCmd = ["sudo", "-S", "-k", "-p", "", "pacman", "-Sc", "--noconfirm"];
        } else {
            sudoPromptError = "No supported package backend";
            return;
        }
        sudoPromptOpen = false;
        sudoPromptError = "";
        cleaningCache = true;
        cleanCacheProgress = 0;
        lastError = "";
        cleanCacheProc.errBuf = "";
        cleanCacheProc.pendingStdin = password + "\n";
        cleanCacheProc.stdinEnabled = true;
        cleanCacheProc.command = targetCmd;
        cleanCacheProgressTimer.restart();
        cleanCacheProc.running = true;
    }

    function triggerPreviewUpdates(count) {
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
            root.checkUpdates(false);
            root.checkShellUpdate();
            root.maybeRunScheduledUpdate();
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
        command: [
            "sh", "-c",
            [
                'BETA_FLAG=""; [ "$1" = "1" ] && BETA_FLAG="--enablerepo=updates-testing"',
                'if command -v dnf5 >/dev/null 2>&1; then',
                '    echo "BACKEND|dnf5"',
                '    OUT=$(dnf5 check-upgrade -q $BETA_FLAG 2>/dev/null); RC=$?',
                '    if [ $RC -eq 0 ]; then exit 0; fi',
                '    if [ $RC -eq 100 ]; then',
                '        printf "%s\\n" "$OUT" | while IFS= read -r line; do',
                '            set -- $line',
                '            [ $# -lt 2 ] && continue',
                '            case "$1" in *.*) ;; *) continue ;; esac',
                '            PKG_ID="$1"; NEW_VER="$2"; NAME="${1%.*}"',
                '            OLD_VER=$(rpm -q --qf "%{VERSION}-%{RELEASE}" "$NAME" 2>/dev/null || true)',
                '            printf "PKG|%s|%s|%s|%s\\n" "$NAME" "$OLD_VER" "$NEW_VER" "$PKG_ID"',
                '        done',
                '        exit 0',
                '    fi',
                '    echo "ERR|Unable to check for updates"',
                '    exit 1',
                'elif command -v dnf >/dev/null 2>&1; then',
                '    echo "BACKEND|dnf"',
                '    OUT=$(dnf check-upgrade -q $BETA_FLAG 2>/dev/null); RC=$?',
                '    if [ $RC -eq 0 ]; then exit 0; fi',
                '    if [ $RC -eq 100 ]; then',
                '        printf "%s\\n" "$OUT" | while IFS= read -r line; do',
                '            set -- $line',
                '            [ $# -lt 2 ] && continue',
                '            case "$1" in *.*) ;; *) continue ;; esac',
                '            PKG_ID="$1"; NEW_VER="$2"; NAME="${1%.*}"',
                '            OLD_VER=$(rpm -q --qf "%{VERSION}-%{RELEASE}" "$NAME" 2>/dev/null || true)',
                '            printf "PKG|%s|%s|%s|%s\\n" "$NAME" "$OLD_VER" "$NEW_VER" "$PKG_ID"',
                '        done',
                '        exit 0',
                '    fi',
                '    echo "ERR|Unable to check for updates"',
                '    exit 1',
                'elif command -v pacman >/dev/null 2>&1; then',
                '    echo "BACKEND|pacman"',
                '    if command -v checkupdates >/dev/null 2>&1; then',
                '        OUT=$(checkupdates 2>/dev/null); RC=$?',
                '        if [ $RC -eq 2 ]; then exit 0; fi',
                '        if [ $RC -ne 0 ]; then echo "ERR|Unable to check for updates"; exit 1; fi',
                '    else',
                '        OUT=$(pacman -Qu 2>/dev/null); RC=$?',
                '        if [ $RC -ne 0 ] && [ -z "$OUT" ]; then exit 0; fi',
                '    fi',
                '    printf "%s\\n" "$OUT" | while IFS= read -r line; do',
                '        set -- $line',
                '        [ $# -lt 4 ] && continue',
                '        printf "PKG|%s|%s|%s|%s\\n" "$1" "$2" "$4" "$1"',
                '    done',
                '    exit 0',
                'else',
                '    echo "ERR|No supported package system found"',
                '    exit 1',
                'fi'
            ].join("\n"),
            "_",
            root.betaUpdatesEnabled ? "1" : "0"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const parsed = [];
                let errMsg = "";
                for (let i = 0; i < lines.length; ++i) {
                    const line = lines[i].trim();
                    if (!line) continue;
                    const parts = line.split("|");
                    if (parts[0] === "BACKEND" && parts.length >= 2) {
                        root.backendTool = parts[1];
                    } else if (parts[0] === "PKG" && parts.length >= 5) {
                        parsed.push({
                            name: parts[1],
                            oldVersion: parts[2],
                            newVersion: parts[3],
                            id: parts[4],
                            selected: true
                        });
                    } else if (parts[0] === "ERR" && parts.length >= 2) {
                        errMsg = parts[1];
                    }
                }

                root.checking = false;
                root.lastCheckedText = Qt.formatTime(new Date(), "hh:mm");
                root.refreshCacheSize();

                if (errMsg !== "") {
                    root.lastError = errMsg;
                    if (root.manualCheckPending) {
                        root.triggerStatusEvent("Update check failed", "danger", true);
                    }
                } else {
                    root.lastError = "";
                    const prevCount = root.packages.length;
                    root.packages = parsed;
                    root.userOverrodeBackupToggle = false;
                    root.syncBackupRecommendation();
                    if (parsed.length > 0 && (parsed.length !== prevCount || root.manualCheckPending)) {
                        root.triggerStatusEvent(parsed.length + (parsed.length === 1 ? " update ready" : " updates ready"), "info", true);
                    } else if (parsed.length === 0 && root.manualCheckPending) {
                        root.triggerStatusEvent("System up to date", "ok", true);
                    }
                }
                root.manualCheckPending = false;
            }
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

    Process {
        id: cleanCacheProc
        property string pendingStdin: ""
        property string errBuf: ""
        onStarted: {
            if (pendingStdin !== "") {
                cleanCacheProc.write(pendingStdin);
                cleanCacheProc.pendingStdin = "";
                cleanCacheProc.stdinEnabled = false;
            }
        }
        stderr: SplitParser {
            onRead: data => {
                cleanCacheProc.errBuf += (cleanCacheProc.errBuf !== "" ? "\n" : "") + data;
            }
        }
        onExited: function(exitCode) {
            cleanCacheProgressTimer.stop();
            root.cleaningCache = false;
            root.refreshCacheSize();
            if (exitCode === 0) {
                root.cleanCacheProgress = 100;
                root.lastError = "";
                root.triggerStatusEvent("Package cache cleaned (100%)", "ok", true);
            } else {
                root.cleanCacheProgress = 0;
                const isBadPwd = /incorrect password|sorry, try again|authentication failure/i.test(cleanCacheProc.errBuf || "");
                if (isBadPwd) {
                    root.sudoPromptError = "Incorrect sudo password. Please try again.";
                    root.sudoPromptOpen = true;
                } else {
                    root.lastError = "Authentication cancelled or cache clean failed";
                    root.triggerStatusEvent("Cache clean failed", "danger", true);
                }
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
        installingDeps = true;
        depsError = "";
        BackupService.runPrivileged(
            "Install Required Shell Packages",
            "Install mandatory Paithosh dependencies (" + missingCorePkgs + "), including Hyprcursor.",
            "Install Required",
            [
                "bash", root.shellProjectRoot + "/installer/lib/apply.sh",
                "--packages-only",
                "--packages", missingCorePkgs
            ],
            (ok, parsed, out, err) => {
                root.installingDeps = false;
                if (ok) {
                    root.depsError = "";
                    root.checkRequiredDeps(() => {
                        CursorService.checkDeps(() => {
                            if (CursorService.depsReady) CursorService.applyNow(true);
                        });
                        if (cb) cb(true);
                    });
                } else {
                    const msg = BackupService.cleanErrorMessage(parsed, err, "Authentication cancelled or package install failed");
                    root.depsError = msg;
                    root.triggerStatusEvent("Required package install failed", "danger", true);
                    if (cb) cb(false);
                }
            }
        );
    }

    Timer {
        id: shellReloadTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (typeof Quickshell.reload === "function") Quickshell.reload(true);
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
            for (let i = 0; i < lines.length; ++i) {
                const eq = lines[i].indexOf("=");
                if (eq === -1) continue;
                const k = lines[i].slice(0, eq);
                const v = lines[i].slice(eq + 1).trim();
                if (k === "ERR") err = v;
                else if (k === "BRANCH") root.shellBranch = v;
                else if (k === "LOCAL") root.shellCommit = v;
                else if (k === "CUR_TAG") root.shellCurrentTag = v;
                else if (k === "TARGET") root.shellTargetVersion = v;
                else if (k === "BEHIND") root.shellUpdateBehind = parseInt(v, 10) || 0;
                else if (k === "AHEAD") root.shellUpdateAhead = parseInt(v, 10) || 0;
                else if (k === "SUMMARY") root.shellLatestSummary = v;
                else if (k === "COMMIT" && v !== "") {
                    const sp = v.indexOf(" ");
                    if (sp !== -1) commits.push({ hash: v.slice(0, sp), subject: v.slice(sp + 1).trim() });
                    else commits.push({ hash: v, subject: "" });
                }
            }
            root.shellCommits = (_exitCode === 0 && root.shellUpdateBehind > 0) ? commits : [];
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
                "[ \"$behind\" -gt 0 ] 2>/dev/null && git -C \"$dir\" log --pretty=format:'COMMIT=%h %s' -n 30 \"HEAD..${latest_tag}\" 2>/dev/null || true; " +
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
                root.shellUpdateBehind = 0;
                root.shellUpdateAhead = 0;
                root.shellLatestSummary = "";
                root.shellCommits = [];
                root.shellUpdateError = "";
                root.checkHyprSyncStatus();
                root.checkRequiredDeps((hasMissing) => {
                    if (hasMissing) {
                        root.triggerStatusEvent("Installing required shell packages...", "info", false);
                        root.installMissingCoreDeps((ok) => {
                            root.triggerStatusEvent(ok ? "Paithosh Shell updated — reloading..." : "Updated shell (install missing deps in Updates)", ok ? "ok" : "warn", true);
                            shellReloadTimer.restart();
                        });
                    } else {
                        root.triggerStatusEvent("Paithosh Shell updated — reloading...", "ok", true);
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
            "if [ -f \"$dir/installer/lib/sync-hypr.sh\" ]; then " +
            "bash \"$dir/installer/lib/sync-hypr.sh\" --repo-root \"$dir\" --mode update; fi",
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
                const modCount = Array.isArray(data.modifiedFiles) ? data.modifiedFiles.length : 0;
                const pendCount = (Array.isArray(data.pendingFiles) ? data.pendingFiles.length : 0) + (data.rootMismatch ? 1 : 0);
                root.hyprSyncState = st;
                root.hyprModifiedCount = modCount;
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
        property var _callbacks: []
        command: ["bash", root.shellProjectRoot + "/installer/lib/audit.sh", "--json"]
        stdout: StdioCollector {
            onStreamFinished: depsAuditProc.outBuf = text || ""
        }
        stderr: StdioCollector {
            onStreamFinished: depsAuditProc.errBuf = text || ""
        }
        onExited: (code) => {
            root.checkingDeps = false;
            const cbs = depsAuditProc._callbacks.slice();
            depsAuditProc._callbacks = [];
            let hasMissing = false;
            if (code === 0) {
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
            }
            for (let k = 0; k < cbs.length; ++k) {
                cbs[k](hasMissing);
            }
        }
    }
}
