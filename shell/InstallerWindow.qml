import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "."
import "services"
import "components"
import "components/common"

PanelWindow {
    id: root
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "paithosh-installer"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    property int step: 0 // 0: Welcome, 1: Config, 2: Preferences, 3: Install
    onStepChanged: {
        SoundService.playInstallerStep();
        if (step === 3) {
            trackCanvas.requestPaint();
            progressCanvas.requestPaint();
        }
    }
    property bool loadingAudit: true
    property string auditError: ""
    property var distroInfo: ({ id: "", family: "", pkgMgr: "", pretty: "Detecting...", coprNeeded: false, aurWarning: "", unsupportedNote: "" })
    property bool hyprExists: false
    property int hyprFiles: 0
    property string hyprConfigKind: "none"
    property bool hyprManagedByPaithosh: false
    property var hyprLuaSupported: null
    property bool paithoshExists: false
    property bool polkitAgentActive: false
    property bool sudoNotRequired: false
    property bool coprNeeded: false
    property string distroNote: ""
    property var packages: []
    property var missingCorePackages: []
    property var missingExtraPackages: []
    property var installedExtraPackages: []
    property int missingCoreCount: 0
    property var selectedPkgs: ({})
    property string activePkgPreset: "rec"
    property bool showInstalledPkgs: false

    // User preferences (pre-configured Theme presets from Theme.qml)
    property string optUpdateStream: "main" // "main" | "release"
    property bool optBackupHypr: true
    property bool optSyncHypr: true
    property string optTheme: Theme.activePreset || "OLED Pure"
    property string optBarPos: "top"
    property bool optAutostart: true
    property bool optSetupPortals: true

    // Install execution state
    property bool installing: false
    property bool installDone: false
    property int installExitCode: -1
    property real installProgress: 0.0
    property real _stepCeiling: 0.20
    property string currentLogLine: ""
    property bool showFullLog: false
    property string installLog: ""
    property bool sudoPromptOpen: false
    property string sudoPromptError: ""
    property bool _closing: false

    Behavior on installProgress { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

    readonly property string repoRoot: Quickshell.shellDir.replace(/\/shell\/?$/, "")
    readonly property bool isDryRun: Quickshell.env("PAITHOSH_INSTALLER_DRY_RUN") === "1"

    // Release metadata (synced from GitHub latest release, with local fallback)
    property bool loadingRelease: true
    property string releaseVersion: "v1.2"
    property string releaseDate: ""
    property bool releaseFromGithub: false
    property var releaseChangelogs: [
        "• Added Shell updater",
        "• Dynamic Island shell for Hyprland with Mission Control, Media, Power, Weather, and Task Manager",
        "• Redesigned File Manager, File View, and File Picker with dual layout and Wayland drag-and-drop",
        "• Built-in Settings UI, Workspace Overview, Clipboard History, Screen Recorder, and VPN/Proxy controls",
        "• One-line curl installer with auto-clone, anti-bloat distro audit, GUI overlay, and TTY CLI mode"
    ]

    // Welcome splash -> dialog expand state
    property real scrimAlpha: 0.0
    property real splashGlow: 0.0
    property real splashShaderTime: 0.0
    property real splashOpacity: 0.0
    property real splashScale: 0.55
    property real splashOrbOffsetX: 34.0
    property real splashOrbOffsetY: 30.0
    property real splashOrbScale: 0.25
    property real splashOrbOpacity: 0.0
    property bool dialogOpen: false

    Component.onCompleted: {
        Quickshell.watchFiles = false;
        auditProc.running = true;
        releaseProc.running = true;
        welcomeSeq.start();
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup(); }
        function onReloadFailed() { Quickshell.inhibitReloadPopup(); }
    }

    NumberAnimation {
        id: splashShaderClock
        target: root
        property: "splashShaderTime"
        from: 0.0
        to: Math.PI * 2
        duration: 8000
        loops: Animation.Infinite
        running: root.splashGlow > 0.002
    }

    SequentialAnimation {
        id: welcomeSeq
        NumberAnimation { target: root; property: "scrimAlpha"; from: 0.0; to: 0.78; duration: 720; easing.type: Easing.InOutCubic }
        ScriptAction { script: SoundService.playInstallerSplash() }
        ParallelAnimation {
            NumberAnimation { target: root; property: "splashGlow"; from: 0.0; to: 1.0; duration: 760; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "splashOpacity"; from: 0.0; to: 1.0; duration: 540; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "splashScale"; from: 0.68; to: 1.0; duration: 680; easing.type: Easing.OutQuint }
            SequentialAnimation {
                PauseAnimation { duration: 150 }
                ParallelAnimation {
                    NumberAnimation { target: root; property: "splashOrbOpacity"; from: 0.0; to: 1.0; duration: 240; easing.type: Easing.OutCubic }
                    NumberAnimation { target: root; property: "splashOrbOffsetX"; from: 34.0; to: 0.0; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.45 }
                    NumberAnimation { target: root; property: "splashOrbOffsetY"; from: 30.0; to: 0.0; duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.45 }
                    NumberAnimation { target: root; property: "splashOrbScale"; from: 0.25; to: 1.0; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.35 }
                }
            }
        }
        PauseAnimation { duration: 560 }
        ParallelAnimation {
            NumberAnimation { target: root; property: "splashGlow"; to: 0.0; duration: 360; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "splashOpacity"; to: 0.0; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "splashScale"; to: 1.18; duration: 300; easing.type: Easing.InCubic }
            ScriptAction { script: root.dialogOpen = true }
        }
    }

    function isCorePkg(p) {
        return Boolean(p && (p.group === "core" || p.required));
    }

    function rebuildPackageLists() {
        const coreMissingList = [];
        const missingExtra = [];
        const installedExtra = [];
        for (let i = 0; i < packages.length; ++i) {
            const p = packages[i];
            if (isCorePkg(p)) {
                if (!p.installed) coreMissingList.push(p);
                continue;
            }
            if (p.installed) installedExtra.push(p);
            else missingExtra.push(p);
        }
        missingCorePackages = coreMissingList;
        missingExtraPackages = missingExtra;
        installedExtraPackages = installedExtra;
        missingCoreCount = coreMissingList.length;
    }

    function selectedExtraCount() {
        let count = 0;
        for (let i = 0; i < missingExtraPackages.length; ++i) {
            if (selectedPkgs[missingExtraPackages[i].id]) count += 1;
        }
        return count;
    }

    function _appendPkgTokens(out, pkgStr) {
        const toks = String(pkgStr || "").trim().split(/\s+/);
        for (let j = 0; j < toks.length; ++j) {
            const t = toks[j];
            if (t !== "" && out.indexOf(t) === -1) out.push(t);
        }
    }

    function selectedPkgList() {
        const out = [];
        // Core packages are mandatory and always auto-included when missing
        for (let i = 0; i < packages.length; ++i) {
            const p = packages[i];
            if (!p.installed && isCorePkg(p)) {
                _appendPkgTokens(out, p.pkg);
            }
        }
        // User-selected additional packages
        for (let i = 0; i < missingExtraPackages.length; ++i) {
            const p = missingExtraPackages[i];
            if (selectedPkgs[p.id]) {
                _appendPkgTokens(out, p.pkg);
            }
        }
        return out;
    }

    function selectPackagePreset(mode) {
        activePkgPreset = mode;
        const next = {};
        if (mode !== "skip") {
            for (let i = 0; i < missingExtraPackages.length; ++i) {
                const p = missingExtraPackages[i];
                if (mode === "all") next[p.id] = true;
                else if (mode === "rec" && (p.group === "wayland" || p.group === "system")) next[p.id] = true;
            }
        }
        selectedPkgs = next;
    }

    function selectTheme(name) {
        optTheme = name;
        Theme.applyPreset(name);
    }

    function retryAudit() {
        loadingAudit = true;
        auditError = "";
        auditProc.outBuf = "";
        auditProc.errBuf = "";
        auditProc._stdoutDone = false;
        auditProc._stderrDone = false;
        auditProc._exited = false;
        auditProc._exitCode = -1;
        auditProc.running = false;
        auditProc.running = true;
    }

    function needsSudoPrompt() {
        if (isDryRun) return false;
        if (selectedPkgList().length === 0) return false;
        if (sudoNotRequired) return false;
        const mgr = (distroInfo && distroInfo.pkgMgr) ? distroInfo.pkgMgr : "";
        return !polkitAgentActive || mgr === "paru" || mgr === "yay";
    }

    function startInstall() {
        if (installing || loadingAudit || auditError !== "") return;
        if (needsSudoPrompt()) {
            sudoPromptError = "";
            sudoPromptOpen = true;
            return;
        }
        launchApply("");
    }

    function launchApply(sudoPassword) {
        if (installing) return;
        SoundService.playInstallerStart();
        step = 3;
        installing = true;
        installDone = false;
        installExitCode = -1;
        installProgress = 0.04;
        _stepCeiling = 0.20;
        currentLogLine = "Preparing installation...";
        showFullLog = false;
        installLog = "Starting Paithosh installation...\n";
        const pkgs = selectedPkgList().join(",");
        const cmd = [
            "bash", repoRoot + "/installer/lib/apply.sh",
            "--backup-hypr", (hyprExists && optBackupHypr) ? "true" : "false",
            "--sync-hypr", optSyncHypr ? "true" : "false",
            "--packages", pkgs,
            "--update-stream", optUpdateStream,
            "--theme", optTheme,
            "--bar-position", optBarPos,
            "--autostart", optAutostart ? "true" : "false",
            "--setup-portals", optSetupPortals ? "true" : "false",
            "--defer-release-checkout"
        ];
        if (sudoPassword !== "") {
            cmd.push("--sudo-stdin");
            applyProc.stdinEnabled = true;
            applyProc.pendingStdin = sudoPassword + "\n";
        } else {
            applyProc.stdinEnabled = false;
            applyProc.pendingStdin = "";
        }
        if (isDryRun) cmd.push("--dry-run");
        applyProc.command = cmd;
        applyProc.running = true;
    }

    function closeInstaller() {
        if (_closing) return;
        _closing = true;
        if (installDone && installExitCode === 0 && !isDryRun) {
            const shellDir = repoRoot + "/shell";
            const syncHyprFlag = optSyncHypr ? "1" : "0";
            const autostartFlag = optAutostart ? "1" : "0";
            Quickshell.execDetached([
                "setsid", "-f", "sh", "-c",
                "exec </dev/null >/dev/null 2>&1; " +
                "shell_dir=\"$1\"; sync_hypr=\"$2\"; repo_root=\"$3\"; update_stream=\"$4\"; autostart_flag=\"$5\"; uid=\"$(id -u)\"; " +
                "i=0; while [ $i -lt 40 ] && pgrep -u \"$uid\" -f '[I]nstallerWindow\\.qml' >/dev/null 2>&1; do " +
                "  sleep 0.1; i=$((i + 1)); " +
                "done; " +
                "pkill -u \"$uid\" -x qs 2>/dev/null || true; " +
                "pkill -u \"$uid\" -x quickshell 2>/dev/null || true; " +
                "i=0; while [ $i -lt 30 ] && (pgrep -u \"$uid\" -x qs >/dev/null 2>&1 || pgrep -u \"$uid\" -x quickshell >/dev/null 2>&1); do " +
                "  sleep 0.1; i=$((i + 1)); " +
                "done; " +
                "pkill -9 -u \"$uid\" -x qs 2>/dev/null || true; " +
                "pkill -9 -u \"$uid\" -x quickshell 2>/dev/null || true; " +
                "if [ \"$update_stream\" = \"release\" ] && [ -n \"$repo_root\" ] && git -C \"$repo_root\" rev-parse --is-inside-work-tree >/dev/null 2>&1; then " +
                "  if git -C \"$repo_root\" diff --quiet && git -C \"$repo_root\" diff --cached --quiet; then " +
                "    latest_tag=\"$(git -C \"$repo_root\" tag -l 'v*' --sort=-v:refname 2>/dev/null | head -n1 || true)\"; " +
                "    [ -z \"$latest_tag\" ] && latest_tag=\"$(git -C \"$repo_root\" tag -l --sort=-v:refname 2>/dev/null | head -n1 || true)\"; " +
                "    if [ -n \"$latest_tag\" ]; then " +
                "      prev_head=\"$(git -C \"$repo_root\" rev-parse HEAD 2>/dev/null || true)\"; " +
                "      if git -C \"$repo_root\" checkout --quiet \"$latest_tag\" 2>/dev/null; then " +
                "        if [ \"$sync_hypr\" = \"1\" ] && [ -n \"$prev_head\" ] && ! git -C \"$repo_root\" diff --quiet \"$prev_head\" HEAD -- defaults/hypr 2>/dev/null; then " +
                "          bash \"$repo_root/installer/lib/sync-hypr.sh\" --repo-root \"$repo_root\" --mode replace --no-backup --no-reload >/dev/null 2>&1 || true; " +
                "          autostart_lua=\"${XDG_CONFIG_HOME:-$HOME/.config}/hypr/config/autostart.lua\"; " +
                "          if [ \"$autostart_flag\" = \"0\" ] && [ -f \"$autostart_lua\" ]; then " +
                "            python3 - \"$autostart_lua\" <<'PY'\n" +
                "import re, sys\n" +
                "path = sys.argv[1]\n" +
                "txt = open(path, 'r', encoding='utf-8').read()\n" +
                "out, changed = [], False\n" +
                "for ln in txt.splitlines(keepends=True):\n" +
                "    if not ln.lstrip().startswith('--') and re.search(r'hl\\.exec_cmd\\(.*qs\\s+-p', ln):\n" +
                "        ind = ln[:len(ln) - len(ln.lstrip())]\n" +
                "        out.append(ind + '-- ' + ln.lstrip())\n" +
                "        changed = True\n" +
                "    else:\n" +
                "        out.append(ln)\n" +
                "if changed:\n" +
                "    open(path, 'w', encoding='utf-8').write(''.join(out))\n" +
                "PY\n" +
                "          fi; " +
                "        fi; " +
                "      fi; " +
                "    fi; " +
                "  fi; " +
                "fi; " +
                "if [ \"$sync_hypr\" = \"1\" ] && [ -n \"${HYPRLAND_INSTANCE_SIGNATURE:-}\" ] && command -v hyprctl >/dev/null 2>&1; then " +
                "  hyprctl reload >/dev/null 2>&1 || true; " +
                "  sleep 0.2; " +
                "fi; " +
                "if command -v qs >/dev/null 2>&1; then " +
                "  exec env QS_NO_RELOAD_POPUP=1 qs -d -p \"$shell_dir\" </dev/null >/dev/null 2>&1; " +
                "elif command -v quickshell >/dev/null 2>&1; then " +
                "  exec env QS_NO_RELOAD_POPUP=1 quickshell -d -p \"$shell_dir\" </dev/null >/dev/null 2>&1; " +
                "fi",
                "_",
                shellDir,
                syncHyprFlag,
                repoRoot,
                optUpdateStream,
                autostartFlag
            ]);
        }
        Qt.quit();
    }

    Process {
        id: auditProc
        command: ["bash", root.repoRoot + "/installer/lib/audit.sh", "--json"]
        running: false
        property string outBuf: ""
        property string errBuf: ""
        property bool _stdoutDone: false
        property bool _stderrDone: false
        property bool _exited: false
        property int _exitCode: -1

        function tryFinish() {
            if (!_stdoutDone || !_stderrDone || !_exited) return;
            _exited = false;
            root.loadingAudit = false;
            const raw = outBuf.trim();
            if (_exitCode !== 0 && !raw) {
                root.auditError = errBuf || ("Audit script failed (exit " + _exitCode + ").");
                return;
            }
            if (!raw) {
                root.auditError = errBuf || "System audit produced no output.";
                return;
            }
            try {
                const data = JSON.parse(raw);
                root.auditError = "";
                root.distroInfo = data.distro || root.distroInfo;
                root.hyprExists = Boolean(data.configs && data.configs.hyprExists);
                root.hyprFiles = (data.configs && data.configs.hyprFiles) ? data.configs.hyprFiles : 0;
                root.hyprConfigKind = (data.configs && data.configs.hyprConfigKind) ? data.configs.hyprConfigKind : "none";
                root.hyprManagedByPaithosh = Boolean(data.configs && data.configs.hyprManagedByPaithosh);
                root.hyprLuaSupported = (data.configs && data.configs.hyprLuaSupported !== undefined) ? data.configs.hyprLuaSupported : null;
                root.paithoshExists = Boolean(data.configs && data.configs.paithoshExists);
                root.polkitAgentActive = Boolean(data.configs && data.configs.polkitAgentActive);
                root.sudoNotRequired = Boolean(data.configs && data.configs.sudoNotRequired);
                root.coprNeeded = Boolean(data.distro && data.distro.coprNeeded);
                const notes = [];
                if (root.coprNeeded) notes.push("Fedora COPR lionheartp/Hyprland will be enabled automatically.");
                if (data.distro && data.distro.aurWarning) notes.push(data.distro.aurWarning);
                if (data.distro && data.distro.unsupportedNote) notes.push(data.distro.unsupportedNote);
                root.distroNote = notes.join(" ");
                root.packages = data.packages || [];
                root.rebuildPackageLists();
                root.selectPackagePreset("rec");
            } catch (e) {
                root.auditError = "Audit parse error: " + e;
                root.installLog += root.auditError + "\n";
            }
        }

        stdout: StdioCollector {
            onStreamFinished: {
                auditProc.outBuf = text || "";
                auditProc._stdoutDone = true;
                auditProc.tryFinish();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                auditProc.errBuf = (text || "").trim();
                auditProc._stderrDone = true;
                auditProc.tryFinish();
            }
        }
        onExited: (code) => {
            auditProc._exitCode = code;
            auditProc._exited = true;
            auditProc.tryFinish();
        }
    }

    Process {
        id: releaseProc
        command: [
            "python3", "-c",
            "import json, re, urllib.request\n" +
            "url = 'https://api.github.com/repos/paithon5959/paithosh/releases/latest'\n" +
            "req = urllib.request.Request(url, headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'paithosh-installer'})\n" +
            "with urllib.request.urlopen(req, timeout=5) as resp:\n" +
            "    d = json.loads(resp.read().decode('utf-8'))\n" +
            "lines = []\n" +
            "for raw in (d.get('body') or '').splitlines():\n" +
            "    s = raw.strip()\n" +
            "    if not s or s.startswith('#'):\n" +
            "        continue\n" +
            "    s = re.sub(r'^[-*•]\\s+', '', s)\n" +
            "    s = re.sub(r'`([^`]+)`', r'\\1', s)\n" +
            "    s = re.sub(r'\\*\\*([^*]+)\\*\\*', r'\\1', s)\n" +
            "    if s:\n" +
            "        lines.append('• ' + s)\n" +
            "print(json.dumps({'version': d.get('tag_name') or '', 'date': (d.get('published_at') or '')[:10], 'changelogs': lines}))\n"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.loadingRelease = false;
                const raw = text.trim();
                if (!raw) return;
                try {
                    const data = JSON.parse(raw);
                    if (data.version) root.releaseVersion = data.version;
                    if (data.date) root.releaseDate = data.date;
                    if (Array.isArray(data.changelogs) && data.changelogs.length > 0) {
                        root.releaseChangelogs = data.changelogs;
                    }
                    root.releaseFromGithub = true;
                } catch (e) {}
            }
        }
        onExited: (code) => {
            if (code !== 0) root.loadingRelease = false;
        }
    }

    Process {
        id: applyProc
        running: false
        property string pendingStdin: ""
        onStarted: {
            if (pendingStdin !== "") {
                applyProc.write(pendingStdin);
                applyProc.pendingStdin = "";
                applyProc.stdinEnabled = false;
            }
        }
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("STEP|")) {
                    const parts = line.split("|");
                    if (parts.length >= 3) {
                        const kn = parts[1].split("/");
                        const k = parseInt(kn[0], 10);
                        const n = parseInt(kn[1], 10);
                        if (n > 0 && !isNaN(k)) {
                            root.installProgress = Math.max(root.installProgress, Math.min(0.95, (k - 0.5) / n));
                            root._stepCeiling = Math.min(0.97, k / n);
                        }
                        const msg = parts.slice(2).join("|").trim();
                        if (msg !== "") {
                            root.currentLogLine = msg;
                            root.installLog += msg + "\n";
                        }
                        return;
                    }
                }
                root.installLog += line + "\n";
                if (line.trim() !== "") root.currentLogLine = line.trim();
                root.installProgress = Math.min(root._stepCeiling, root.installProgress + 0.01);
            }
        }
        stderr: SplitParser {
            onRead: (line) => {
                root.installLog += line + "\n";
                if (line.trim() !== "") root.currentLogLine = line.trim();
            }
        }
        onExited: (code) => {
            root.installExitCode = code;
            root.installing = false;
            if (code === 42) {
                root.installDone = false;
                root.sudoPromptError = "Incorrect sudo password. Please try again.";
                root.sudoPromptOpen = true;
                return;
            }
            if (code === 0) root.installProgress = 1.0;
            root.installDone = true;
            if (code === 0) SoundService.playInstallerDone();
        }
    }

    // Canonical Paithosh toggle switch (38x22 r=11, thumb 16x16 r=8, spring motion)
    component InstallerSwitch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled()

        implicitWidth: 38
        implicitHeight: 22
        radius: 11
        clip: true
        color: checked ? Theme.accent : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, swMouse.containsMouse ? 0.18 : 0.12)
        border.width: 1
        border.color: checked ? Theme.accent : Theme.borderSubtle
        scale: swMouse.pressed ? 0.94 : 1.0

        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

        Rectangle {
            width: 16; height: 16; radius: 8
            y: 3
            x: sw.checked ? (sw.width - width - 3) : 3
            color: sw.checked ? Theme.accentFg : Theme.text
            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.15 } }
            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: swMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }

    // Fullscreen dark scrim (gradual dim -> splash shader glow -> dialog)
    Rectangle {
        id: scrimRoot
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.scrimAlpha)
        focus: true
        Keys.onEscapePressed: {
            if (root.sudoPromptOpen) {
                sudoOverlay.cancelPrompt();
            } else if (!root.installing) {
                root.closeInstaller();
            }
        }

        // Default-wallpaper-style monochrome radial glow shader emerging behind the splash emblem
        ShaderEffect {
            id: splashGlowShader
            anchors.fill: parent
            visible: root.splashGlow > 0.002
            property vector2d resolution: Qt.vector2d(width, height)
            property real reveal: root.splashGlow
            property real time: root.splashShaderTime
            property color glowColor: Theme.text
            fragmentShader: Qt.resolvedUrl("assets/shaders/splash_glow.frag.qsb")
        }

        // Welcome Splash Emblem (Frameless Orbital Nucleus with detached-orb spring animation)
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 22
            visible: root.splashOpacity > 0.01
            opacity: root.splashOpacity
            scale: root.splashScale

            Item {
                Layout.alignment: Qt.AlignHCenter
                width: 148
                height: 148

                SvgIcon {
                    anchors.fill: parent
                    sourceName: "paithosh-body"
                    iconSize: 148
                    preserveColor: true
                }

                // Detached Orbital Nucleus dot (24x24 viewBox: cx=8.6, cy=9.4, r=1.65)
                Rectangle {
                    readonly property real orbSize: 148 * (3.3 / 24.0)
                    width: orbSize
                    height: orbSize
                    radius: orbSize / 2
                    gradient: Gradient {
                        orientation: Gradient.Vertical
                        GradientStop { position: 0.0; color: "#ffffff" }
                        GradientStop { position: 0.65; color: "#dce0e6" }
                        GradientStop { position: 1.0; color: "#8c93a0" }
                    }
                    x: 148 * (8.6 / 24.0) - width / 2 + root.splashOrbOffsetX
                    y: 148 * (9.4 / 24.0) - height / 2 + root.splashOrbOffsetY
                    scale: root.splashOrbScale
                    opacity: root.splashOrbOpacity
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Paithosh"
                color: Theme.text
                font.family: Theme.fontSans
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
        }

        // Subtle falling snow particles on dimmed background
        Item {
            id: snowLayer
            anchors.fill: parent
            visible: root.scrimAlpha > 0.15
            opacity: Math.min(1.0, root.scrimAlpha / 0.72)
            clip: true

            property real tick: 0.0
            NumberAnimation on tick {
                running: snowLayer.visible
                from: 0.0; to: 1.0
                duration: 9500
                loops: Animation.Infinite
            }

            Repeater {
                model: 28
                delegate: Rectangle {
                    required property int index
                    readonly property real sz: 4 + (index % 5)
                    readonly property real baseX: ((index * 137) % 100) / 100.0
                    readonly property real speed: 1.0 + (index % 3) * 0.32
                    readonly property real progress: ((snowLayer.tick * speed) + (index * 0.137)) % 1.0
                    // ~33 deg diagonal drift from right to left
                    readonly property real wrappedX: (((baseX - progress * 0.42) % 1.0) + 1.0) % 1.0
                    width: sz; height: sz; radius: sz / 2
                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.16 + (index % 4) * 0.08)
                    x: parent.width * wrappedX + Math.sin((snowLayer.tick * 6.283) + index) * 8
                    y: progress * (root.height + 28) - 14
                }
            }
        }

        // Centered Settings-style Dialog Card (expands from splash)
        ClippingRectangle {
            id: dialogCard
            anchors.centerIn: parent
            width: Math.min(parent.width - 64, 980)
            height: Math.min(parent.height - 64, 660)
            radius: 16
            color: Theme.surfaceBg
            border.width: 1
            border.color: Theme.borderSubtle
            visible: opacity > 0.01
            opacity: root.dialogOpen ? 1.0 : 0.0
            scale: root.dialogOpen ? 1.0 : 0.72

            Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.08 } }
            Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // Left Sidebar (Two-Pane Polarity: Theme.pillBg + 1px Theme.borderSubtle divider)
                Rectangle {
                    Layout.preferredWidth: 236
                    Layout.fillHeight: true
                    color: Theme.pillBg
                    clip: true

                    Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        // Brand Title
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Rectangle {
                                width: 34; height: 34; radius: 10
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                border.width: 1; border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.30)
                                SvgIcon { anchors.centerIn: parent; sourceName: "paithosh"; iconSize: 19; preserveColor: true }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                                Text {
                                    text: "Paithosh"
                                    color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 14; font.weight: Font.Bold
                                    elide: Text.ElideRight; Layout.fillWidth: true
                                }
                                Text {
                                    text: "Shell Installer"
                                    color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11
                                    elide: Text.ElideRight; Layout.fillWidth: true
                                }
                            }
                        }

                        // Distro pill
                        Rectangle {
                            Layout.fillWidth: true
                            height: 28; radius: 8; clip: true
                            color: Theme.cardBg
                            border.width: 1; border.color: Theme.borderSubtle
                            Text {
                                anchors.centerIn: parent
                                width: parent.width - 16
                                horizontalAlignment: Text.AlignHCenter
                                text: root.distroInfo.pretty
                                color: Theme.accent
                                font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                        // Sidebar Nav Steps (4 steps: Welcome, Config, Preferences, Install)
                        Repeater {
                            model: [
                                { title: "Welcome", sub: "Version & changelogs", icon: "home" },
                                { title: "Config", sub: "Stream, backup & extras", icon: "sliders" },
                                { title: "Preferences", sub: "Theme & layout", icon: "palette" },
                                { title: "Install", sub: "Apply & progress", icon: "terminal" }
                            ]
                            delegate: Rectangle {
                                required property int index
                                required property var modelData
                                Layout.fillWidth: true
                                height: 52
                                radius: 10
                                clip: true
                                readonly property bool active: root.step === index
                                readonly property bool done: root.step > index
                                color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                              : (navMouse.containsMouse ? Theme.cardHover : "transparent")
                                border.width: 1
                                border.color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42) : "transparent"
                                scale: navMouse.pressed && !root.installing && index < 3 ? 0.96 : 1.0

                                Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                // Canonical 3x15px active indicator pill
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: active ? 15 : 0
                                    radius: 2
                                    color: Theme.accent
                                    opacity: active ? 1.0 : 0.0
                                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
                                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                }

                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 10; spacing: 10
                                    SvgIcon {
                                        sourceName: done ? "check" : modelData.icon
                                        iconSize: 16
                                        color: active ? Theme.accent : (done ? Theme.ok : Theme.textSub)
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                                        Text {
                                            text: (index + 1) + ". " + modelData.title
                                            color: active ? Theme.text : Theme.textSub
                                            font.family: Theme.fontSans; font.pixelSize: 12; font.weight: active ? Font.DemiBold : Font.Medium
                                            elide: Text.ElideRight; Layout.fillWidth: true
                                        }
                                        Text {
                                            text: modelData.sub
                                            color: Theme.textMuted
                                            font.family: Theme.fontSans; font.pixelSize: 10
                                            elide: Text.ElideRight; Layout.fillWidth: true
                                        }
                                    }
                                }

                                MouseArea {
                                    id: navMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !root.installing && index < 3 && (index < 2 || (!root.loadingAudit && root.auditError === ""))
                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: root.step = index
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        // Summary Footer inside Sidebar
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: sumCol.implicitHeight + 20
                            radius: 10; clip: true
                            color: Theme.cardBg
                            border.width: 1; border.color: Theme.borderSubtle
                            ColumnLayout {
                                id: sumCol
                                anchors.fill: parent; anchors.margins: 10; spacing: 4
                                Text { text: "Summary"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 10; font.weight: Font.DemiBold }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Text { text: "Stream"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: root.optUpdateStream === "release" ? "Release" : "Main"
                                        color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Text { text: "Theme"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        Layout.maximumWidth: 132
                                        text: root.optTheme + " (" + root.optBarPos + ")"
                                        color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    visible: !root.loadingAudit && root.missingCoreCount > 0
                                    Text { text: "Core"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: root.missingCoreCount + " required"
                                        color: Theme.warn; font.family: Theme.fontMono; font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Text { text: "Extras"; color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11 }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: root.selectedExtraCount() + " selected"
                                        color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                // Vertical divider
                Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Theme.borderSubtle }

                // Right Content Column
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // Top Header Bar
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 54
                        Layout.leftMargin: 22; Layout.rightMargin: 18
                        spacing: 10

                        Text {
                            Layout.fillWidth: true; Layout.minimumWidth: 0
                            text: root.step === 0 ? "Welcome to Paithosh Shell"
                                : root.step === 1 ? "Configuration & Packages"
                                : root.step === 2 ? "Visual Preferences & Theme"
                                : "Installing Paithosh Shell"
                            color: Theme.text
                            font.family: Theme.fontSans; font.pixelSize: 16; font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        PillButton {
                            text: "Close"
                            iconName: "close"
                            enabled: !root.installing
                            onClicked: root.closeInstaller()
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                    // Animated Content Stack
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: 20
                        clip: true

                        // STEP 0: Welcome Screen (Version + Changelogs)
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 14
                            visible: opacity > 0.01
                            opacity: root.step === 0 ? 1.0 : 0.0
                            x: root.step === 0 ? 0 : -24
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            // Hero Version Card
                            Rectangle {
                                Layout.fillWidth: true
                                height: 92; radius: 14; clip: true
                                color: Theme.cardBg
                                border.width: 1; border.color: Theme.borderSubtle
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 16; spacing: 14
                                    Rectangle {
                                        width: 52; height: 52; radius: 14
                                        color: Theme.pillBg
                                        border.width: 1; border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                                        SvgIcon {
                                            anchors.centerIn: parent
                                            sourceName: "paithosh"
                                            iconSize: 30
                                            preserveColor: true
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 3
                                        RowLayout {
                                            spacing: 8
                                            Text { text: "Paithosh Shell"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 16; font.weight: Font.Bold }
                                            Rectangle {
                                                radius: 6; implicitWidth: verTxt.implicitWidth + 14; implicitHeight: 22
                                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                                Text { id: verTxt; anchors.centerIn: parent; text: root.releaseVersion; color: Theme.accent; font.family: Theme.fontMono; font.pixelSize: 11; font.weight: Font.DemiBold }
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0
                                            text: "Minimal Dynamic Island desktop shell for Hyprland & Quickshell."
                                            color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }

                            // Changelogs Card
                            Rectangle {
                                Layout.fillWidth: true; Layout.fillHeight: true
                                radius: 12; clip: true
                                color: Theme.surfaceRaised
                                border.width: 1; border.color: Theme.borderSubtle
                                ColumnLayout {
                                    anchors.fill: parent; anchors.margins: 16; spacing: 10
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Changelogs"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: root.loadingRelease
                                                ? "Syncing GitHub release..."
                                                : (root.releaseFromGithub
                                                    ? ("GitHub Release" + (root.releaseDate ? " · " + root.releaseDate : ""))
                                                    : "Local release notes")
                                            color: Theme.textMuted
                                            font.family: Theme.fontMono; font.pixelSize: 10
                                        }
                                    }
                                    Flickable {
                                        Layout.fillWidth: true; Layout.fillHeight: true
                                        clip: true
                                        contentWidth: width
                                        contentHeight: changelogCol.implicitHeight
                                        boundsBehavior: Flickable.StopAtBounds
                                        ColumnLayout {
                                            id: changelogCol
                                            width: parent.width
                                            spacing: 8
                                            Repeater {
                                                model: root.releaseChangelogs
                                                delegate: Text {
                                                    required property string modelData
                                                    Layout.fillWidth: true
                                                    text: modelData
                                                    color: Theme.textSub
                                                    font.family: Theme.fontSans; font.pixelSize: 12
                                                    wrapMode: Text.WordWrap
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Friendly DIY Notice
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: diyCol.implicitHeight + 24
                                radius: 12; clip: true
                                color: Theme.cardBg
                                border.width: 1; border.color: Theme.borderSubtle
                                ColumnLayout {
                                    id: diyCol
                                    anchors.fill: parent; anchors.margins: 12; spacing: 4
                                    RowLayout {
                                        spacing: 8
                                        SvgIcon { sourceName: "info"; iconSize: 14; color: Theme.textSub }
                                        Text { text: "DIY Project Note"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Paithosh is a personal DIY shell for Hyprland. You stay in full control of every package and config change — keeping a backup of your setup is always a good idea."
                                        color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }

                        // STEP 1: Config (Update Stream, Hyprland Backup & Defaults, Additional Packages)
                        Flickable {
                            id: step1Flick
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: s1Col.implicitHeight + 12
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            visible: opacity > 0.01
                            opacity: root.step === 1 ? 1.0 : 0.0
                            x: root.step === 1 ? 0 : (root.step > 1 ? -24 : 24)
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            ColumnLayout {
                                id: s1Col
                                width: parent.width
                                spacing: 12

                                // Audit Error Card (with Retry)
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: root.auditError !== ""
                                    implicitHeight: auditErrRow.implicitHeight + 24
                                    radius: 12; clip: true
                                    color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.12)
                                    border.width: 1; border.color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.45)
                                    RowLayout {
                                        id: auditErrRow
                                        anchors.fill: parent; anchors.margins: 12; spacing: 10
                                        SvgIcon { sourceName: "alert-triangle"; iconSize: 16; color: Theme.danger }
                                        Text {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0
                                            text: root.auditError
                                            color: Theme.dangerText; font.family: Theme.fontSans; font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                        }
                                        PillButton { text: "Retry"; iconName: "refresh"; onClicked: root.retryAudit() }
                                    }
                                }

                                // ==================== 1. UPDATE STREAM ====================
                                Text {
                                    Layout.fillWidth: true
                                    text: "Update Stream"
                                    color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2; columnSpacing: 10; rowSpacing: 10

                                    Repeater {
                                        model: [
                                            { id: "main", title: "Main (GitHub)", sub: "Latest commits directly from main branch", icon: "package-update", badge: "Rolling" },
                                            { id: "release", title: "Release (Stable)", sub: "Tagged GitHub releases for stability", icon: "shield", badge: "Stable" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            height: 68; radius: 12; clip: true
                                            readonly property bool active: root.optUpdateStream === modelData.id
                                            color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                                          : (streamMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                                            border.width: active ? 1.5 : 1
                                            border.color: active ? Theme.accent : (streamMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40) : Theme.borderSubtle)
                                            scale: streamMouse.pressed ? 0.97 : 1.0
                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                            RowLayout {
                                                anchors.fill: parent; anchors.margins: 12; spacing: 10
                                                Rectangle {
                                                    width: 30; height: 30; radius: 8
                                                    color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) : Theme.surfaceRaised
                                                    border.width: 1; border.color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                                                    SvgIcon { anchors.centerIn: parent; sourceName: modelData.icon; iconSize: 15; color: active ? Theme.accent : Theme.textSub }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                                    RowLayout {
                                                        Layout.fillWidth: true; spacing: 6
                                                        Text {
                                                            Layout.fillWidth: true; Layout.minimumWidth: 0
                                                            text: modelData.title
                                                            color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold
                                                            elide: Text.ElideRight
                                                        }
                                                        Rectangle {
                                                            radius: 5
                                                            implicitWidth: stBadge.implicitWidth + 10; implicitHeight: 18
                                                            color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20) : Theme.surfaceRaised
                                                            Text {
                                                                id: stBadge
                                                                anchors.centerIn: parent
                                                                text: modelData.badge
                                                                color: active ? Theme.accent : Theme.textMuted
                                                                font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.Medium
                                                            }
                                                        }
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true; Layout.minimumWidth: 0
                                                        text: modelData.sub
                                                        color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: streamMouse
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: root.optUpdateStream = modelData.id
                                            }
                                        }
                                    }
                                }

                                // ==================== 2. HYPRLAND CONFIG & BACKUP ====================
                                Text {
                                    Layout.fillWidth: true; Layout.topMargin: 2
                                    text: "Hyprland Configuration"
                                    color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                // Existing ~/.config/hypr: mode + backup switch inside one clean SettingGroup
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: root.hyprExists
                                    implicitHeight: hyprGroupCol.implicitHeight
                                    radius: 12; clip: true
                                    color: Theme.cardBg
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.36)

                                    ColumnLayout {
                                        id: hyprGroupCol
                                        width: parent.width
                                        spacing: 0

                                        // Header + Mode Selector
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.margins: 14
                                            spacing: 10

                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 10
                                                Rectangle {
                                                    width: 30; height: 30; radius: 8
                                                    color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.14)
                                                    border.width: 1; border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.32)
                                                    SvgIcon { anchors.centerIn: parent; sourceName: "alert-triangle"; iconSize: 15; color: Theme.warn }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                                    RowLayout {
                                                        Layout.fillWidth: true; spacing: 8
                                                        Text {
                                                            text: "Existing ~/.config/hypr detected"
                                                            color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold
                                                            elide: Text.ElideRight
                                                        }
                                                        Rectangle {
                                                            radius: 5
                                                            implicitWidth: hyprMetaTxt.implicitWidth + 10; implicitHeight: 18
                                                            color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.14)
                                                            Text {
                                                                id: hyprMetaTxt
                                                                anchors.centerIn: parent
                                                                text: root.hyprFiles + " files • " + (root.hyprConfigKind === "lua" ? "Lua" : (root.hyprConfigKind === "conf" ? "conf" : "custom"))
                                                                color: Theme.warn
                                                                font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.Medium
                                                            }
                                                        }
                                                        Item { Layout.fillWidth: true }
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true; Layout.minimumWidth: 0
                                                        text: root.optSyncHypr
                                                            ? "Replace ~/.config/hypr with Paithosh modular Lua defaults."
                                                            : (root.hyprConfigKind === "lua"
                                                                ? "Keep existing config and only add Paithosh autostart."
                                                                : "Keep existing config and append exec-once to hyprland.conf.")
                                                        color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            GridLayout {
                                                Layout.fillWidth: true
                                                columns: 2; columnSpacing: 8; rowSpacing: 8

                                                Rectangle {
                                                    Layout.fillWidth: true; height: 52; radius: 9; clip: true
                                                    color: root.optSyncHypr ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : (syncRepMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised)
                                                    border.width: root.optSyncHypr ? 1.5 : 1
                                                    border.color: root.optSyncHypr ? Theme.accent : Theme.borderSubtle
                                                    scale: syncRepMouse.pressed ? 0.97 : 1.0
                                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                                    RowLayout {
                                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                                                        SvgIcon { sourceName: "code"; iconSize: 15; color: root.optSyncHypr ? Theme.accent : Theme.textMuted }
                                                        ColumnLayout {
                                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                                                            Text { text: "Replace with Defaults"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                                            Text { text: "Clean modular Lua setup"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: syncRepMouse
                                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            root.optSyncHypr = true;
                                                            root.optBackupHypr = true;
                                                        }
                                                    }
                                                }

                                                Rectangle {
                                                    Layout.fillWidth: true; height: 52; radius: 9; clip: true
                                                    color: !root.optSyncHypr ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : (keepCfgMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised)
                                                    border.width: !root.optSyncHypr ? 1.5 : 1
                                                    border.color: !root.optSyncHypr ? Theme.accent : Theme.borderSubtle
                                                    scale: keepCfgMouse.pressed ? 0.97 : 1.0
                                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                                    RowLayout {
                                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 10
                                                        SvgIcon { sourceName: "folder"; iconSize: 15; color: !root.optSyncHypr ? Theme.accent : Theme.textMuted }
                                                        ColumnLayout {
                                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                                                            Text { text: "Keep Existing Config"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                                            Text { text: "Only inject autostart"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 10; elide: Text.ElideRight; Layout.fillWidth: true }
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: keepCfgMouse
                                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.optSyncHypr = false
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                                        // Backup Toggle Row
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 54
                                            color: bkpRowMouse.containsMouse ? Theme.cardHover : "transparent"
                                            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                            MouseArea {
                                                id: bkpRowMouse
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: root.optBackupHypr = !root.optBackupHypr
                                            }

                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                                Rectangle {
                                                    width: 30; height: 30; radius: 8
                                                    color: root.optBackupHypr ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.14) : Theme.surfaceRaised
                                                    border.width: 1; border.color: root.optBackupHypr ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.35) : Theme.borderSubtle
                                                    SvgIcon { anchors.centerIn: parent; sourceName: "archive"; iconSize: 15; color: root.optBackupHypr ? Theme.ok : Theme.textSub }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: "Backup old Hyprland config"
                                                        color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.Medium
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: root.optBackupHypr
                                                            ? "Saves snapshot to ~/.config/hypr.bak.<timestamp>"
                                                            : (root.optSyncHypr ? "Overwrite ~/.config/hypr without backup" : "Update existing config in-place")
                                                        color: Theme.textSub
                                                        font.family: root.optBackupHypr ? Theme.fontMono : Theme.fontSans
                                                        font.pixelSize: 11
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                                InstallerSwitch {
                                                    checked: root.optBackupHypr
                                                    onToggled: root.optBackupHypr = !root.optBackupHypr
                                                }
                                            }
                                        }
                                    }
                                }

                                // Clean ~/.config/hypr toggle group (when no prior hypr config exists)
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: !root.loadingAudit && !root.hyprExists && root.auditError === ""
                                    height: 58; radius: 12; clip: true
                                    color: cleanSyncMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                                    border.width: 1
                                    border.color: root.optSyncHypr ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42) : Theme.borderSubtle
                                    scale: cleanSyncMouse.pressed ? 0.99 : 1.0
                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                    MouseArea {
                                        id: cleanSyncMouse
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.optSyncHypr = !root.optSyncHypr
                                    }

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                        Rectangle {
                                            width: 30; height: 30; radius: 8
                                            color: root.optSyncHypr ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.surfaceRaised
                                            border.width: 1; border.color: root.optSyncHypr ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                                            SvgIcon { anchors.centerIn: parent; sourceName: "code"; iconSize: 15; color: root.optSyncHypr ? Theme.accent : Theme.textSub }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                            Text {
                                                Layout.fillWidth: true
                                                text: "Install Paithosh Hyprland Defaults"
                                                color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.Medium
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.optSyncHypr
                                                    ? "Copies modular Lua config (binds, monitors, theme) to ~/.config/hypr"
                                                    : "Skipped — only a minimal hyprland.conf autostart will be created"
                                                color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                        }
                                        InstallerSwitch {
                                            checked: root.optSyncHypr
                                            onToggled: root.optSyncHypr = !root.optSyncHypr
                                        }
                                    }
                                }

                                // Hyprland Lua Compatibility Warning
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: root.hyprLuaSupported === false && root.optSyncHypr
                                    implicitHeight: luaWarnRow.implicitHeight + 20
                                    radius: 10; clip: true
                                    color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.10)
                                    border.width: 1; border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.40)
                                    RowLayout {
                                        id: luaWarnRow
                                        anchors.fill: parent; anchors.margins: 10; spacing: 10
                                        SvgIcon { sourceName: "alert-triangle"; iconSize: 15; color: Theme.warn }
                                        Text {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0
                                            text: "Installed Hyprland binary does not appear to link liblua. Hyprland 0.57+ with Lua support is required for Paithosh's modular Lua configuration."
                                            color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                // Distro Note (COPR / AUR / Debian)
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: root.distroNote !== ""
                                    implicitHeight: noteRow.implicitHeight + 20
                                    radius: 10; clip: true
                                    color: Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.10)
                                    border.width: 1; border.color: Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.35)
                                    RowLayout {
                                        id: noteRow
                                        anchors.fill: parent; anchors.margins: 10; spacing: 10
                                        SvgIcon { sourceName: "info"; iconSize: 15; color: Theme.info }
                                        Text {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0
                                            text: root.distroNote
                                            color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }

                                // ==================== 3. MANDATORY CORE PACKAGES (IF MISSING) ====================
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: !root.loadingAudit && root.missingCoreCount > 0
                                    implicitHeight: coreCol.implicitHeight + 20
                                    radius: 10; clip: true
                                    color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.10)
                                    border.width: 1; border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.36)

                                    RowLayout {
                                        id: coreCol
                                        anchors.fill: parent; anchors.margins: 10; spacing: 10
                                        SvgIcon { sourceName: "shield"; iconSize: 15; color: Theme.warn }
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                            Text {
                                                Layout.fillWidth: true
                                                text: "Mandatory Core Packages (" + root.missingCoreCount + " auto-installed)"
                                                color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true; Layout.minimumWidth: 0
                                                text: root.missingCorePackages.map(p => p.pkg).join("  •  ")
                                                color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 10
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }
                                }

                                // ==================== 4. ADDITIONAL PACKAGES ====================
                                RowLayout {
                                    Layout.fillWidth: true; Layout.topMargin: 2
                                    spacing: 8

                                    Text {
                                        text: "Additional Packages"
                                        color: Theme.textMuted; font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                                    }

                                    Rectangle {
                                        visible: !root.loadingAudit
                                        radius: 5
                                        implicitWidth: pkgCountTxt.implicitWidth + 10; implicitHeight: 18
                                        color: Theme.surfaceRaised
                                        border.width: 1; border.color: Theme.borderSubtle
                                        Text {
                                            id: pkgCountTxt
                                            anchors.centerIn: parent
                                            text: root.missingExtraPackages.length > 0
                                                ? (root.selectedExtraCount() + "/" + root.missingExtraPackages.length + " selected")
                                                : (root.installedExtraPackages.length + " ready")
                                            color: Theme.textSub
                                            font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.Medium
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    PillButton {
                                        visible: !root.loadingAudit && root.missingExtraPackages.length > 0
                                        text: "Recommended"
                                        fontSize: 11; horizontalPadding: 10; verticalPadding: 4
                                        active: root.activePkgPreset === "rec"
                                        onClicked: root.selectPackagePreset("rec")
                                    }
                                    PillButton {
                                        visible: !root.loadingAudit && root.missingExtraPackages.length > 0
                                        text: "All Missing"
                                        fontSize: 11; horizontalPadding: 10; verticalPadding: 4
                                        active: root.activePkgPreset === "all"
                                        onClicked: root.selectPackagePreset("all")
                                    }
                                    PillButton {
                                        visible: !root.loadingAudit && root.missingExtraPackages.length > 0
                                        text: "Skip Extras"
                                        fontSize: 11; horizontalPadding: 10; verticalPadding: 4
                                        active: root.activePkgPreset === "skip"
                                        onClicked: root.selectPackagePreset("skip")
                                    }
                                }

                                // Scanning placeholder
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: root.loadingAudit
                                    height: 52; radius: 12; clip: true
                                    color: Theme.cardBg
                                    border.width: 1; border.color: Theme.borderSubtle
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10
                                        SvgIcon { sourceName: "clock"; iconSize: 15; color: Theme.textSub }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "Scanning optional & recommended packages for " + root.distroInfo.pretty + "..."
                                            color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                // Missing Additional Packages Group (or all-ready confirmation)
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: !root.loadingAudit
                                    implicitHeight: extraPkgCol.implicitHeight
                                    radius: 12; clip: true
                                    color: Theme.cardBg
                                    border.width: 1; border.color: Theme.borderSubtle

                                    ColumnLayout {
                                        id: extraPkgCol
                                        width: parent.width
                                        spacing: 0

                                        // Empty state when all additional packages are already installed (or unsupported distro)
                                        Item {
                                            id: emptyPkgState
                                            Layout.fillWidth: true
                                            height: 54
                                            visible: root.missingExtraPackages.length === 0
                                            readonly property bool isUnsupported: Boolean(root.distroInfo && root.distroInfo.family === "unknown")
                                            RowLayout {
                                                anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                                Rectangle {
                                                    width: 30; height: 30; radius: 8
                                                    color: emptyPkgState.isUnsupported
                                                        ? Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.14)
                                                        : Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.14)
                                                    border.width: 1
                                                    border.color: emptyPkgState.isUnsupported
                                                        ? Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.35)
                                                        : Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.35)
                                                    SvgIcon {
                                                        anchors.centerIn: parent
                                                        sourceName: emptyPkgState.isUnsupported ? "alert-triangle" : "check"
                                                        iconSize: 15
                                                        color: emptyPkgState.isUnsupported ? Theme.warn : Theme.ok
                                                    }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: emptyPkgState.isUnsupported
                                                            ? "Unsupported package manager"
                                                            : "All recommended & optional packages are installed"
                                                        color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.Medium
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: emptyPkgState.isUnsupported
                                                            ? "Install dependencies manually — see installer/packages.txt"
                                                            : (root.distroInfo.pkgMgr + " (" + root.distroInfo.family + ") • Nothing extra needed")
                                                        color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }

                                        // Interactive rows for missing non-core packages
                                        Repeater {
                                            model: root.missingExtraPackages
                                            delegate: Rectangle {
                                                required property int index
                                                required property var modelData
                                                Layout.fillWidth: true
                                                height: 52
                                                clip: true
                                                readonly property bool isChecked: Boolean(root.selectedPkgs[modelData.id])
                                                color: pkgRowMouse.containsMouse ? Theme.cardHover : "transparent"
                                                scale: pkgRowMouse.pressed ? 0.99 : 1.0
                                                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                                Rectangle {
                                                    visible: index > 0
                                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                                    height: 1; color: Theme.borderSubtle
                                                }

                                                RowLayout {
                                                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                                    Rectangle {
                                                        width: 30; height: 30; radius: 8
                                                        color: isChecked ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.surfaceRaised
                                                        border.width: 1; border.color: isChecked ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                                                        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                        SvgIcon {
                                                            anchors.centerIn: parent
                                                            sourceName: isChecked ? "check" : "download"
                                                            iconSize: 14
                                                            color: isChecked ? Theme.accent : Theme.textMuted
                                                        }
                                                    }
                                                    ColumnLayout {
                                                        Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: modelData.label
                                                            color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.Medium
                                                            elide: Text.ElideRight
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: modelData.pkg + " • " + modelData.group
                                                            color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                    Rectangle {
                                                        radius: 6
                                                        implicitWidth: stTxt.implicitWidth + 16; implicitHeight: 24
                                                        color: isChecked ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.surfaceRaised
                                                        border.width: 1; border.color: isChecked ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                                                        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                        Text {
                                                            id: stTxt
                                                            anchors.centerIn: parent
                                                            text: isChecked ? "Install" : "Skip"
                                                            color: isChecked ? Theme.accent : Theme.textMuted
                                                            font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                                                        }
                                                    }
                                                }

                                                MouseArea {
                                                    id: pkgRowMouse
                                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.activePkgPreset = "";
                                                        const next = Object.assign({}, root.selectedPkgs);
                                                        next[modelData.id] = !next[modelData.id];
                                                        root.selectedPkgs = next;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Progressive Disclosure Accordion: Already Installed Additional Packages
                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: !root.loadingAudit && root.installedExtraPackages.length > 0
                                    implicitHeight: instHeader.height + (root.showInstalledPkgs ? instBody.implicitHeight : 0)
                                    radius: 12; clip: true
                                    color: Theme.cardBg
                                    border.width: 1
                                    border.color: instHeadMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40) : Theme.borderSubtle
                                    Behavior on implicitHeight { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                    Rectangle {
                                        id: instHeader
                                        width: parent.width; height: 46
                                        color: instHeadMouse.containsMouse ? Theme.cardHover : "transparent"
                                        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                        RowLayout {
                                            anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10
                                            SvgIcon { sourceName: "check"; iconSize: 14; color: Theme.ok }
                                            Text {
                                                text: "Already Installed"
                                                color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.Medium
                                            }
                                            Rectangle {
                                                radius: 5
                                                implicitWidth: instCountTxt.implicitWidth + 10; implicitHeight: 18
                                                color: Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.14)
                                                Text {
                                                    id: instCountTxt
                                                    anchors.centerIn: parent
                                                    text: String(root.installedExtraPackages.length)
                                                    color: Theme.ok
                                                    font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.Medium
                                                }
                                            }
                                            Item { Layout.fillWidth: true }
                                            SvgIcon {
                                                sourceName: "chevron-right"
                                                iconSize: 14
                                                color: Theme.textSub
                                                rotation: root.showInstalledPkgs ? 90 : 0
                                                Behavior on rotation { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
                                            }
                                        }

                                        MouseArea {
                                            id: instHeadMouse
                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                            onClicked: root.showInstalledPkgs = !root.showInstalledPkgs
                                        }
                                    }

                                    ColumnLayout {
                                        id: instBody
                                        y: instHeader.height
                                        width: parent.width
                                        spacing: 0
                                        opacity: root.showInstalledPkgs ? 1.0 : 0.0
                                        enabled: root.showInstalledPkgs
                                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                        Repeater {
                                            model: root.installedExtraPackages
                                            delegate: Item {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                height: 42
                                                clip: true

                                                Rectangle {
                                                    anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
                                                    height: 1; color: Theme.borderSubtle
                                                }

                                                RowLayout {
                                                    anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10
                                                    SvgIcon { sourceName: "check"; iconSize: 13; color: Theme.ok }
                                                    Text {
                                                        Layout.fillWidth: true; Layout.minimumWidth: 0
                                                        text: modelData.label
                                                        color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 12
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        Layout.maximumWidth: 220
                                                        text: modelData.pkg + " • " + modelData.group
                                                        color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // STEP 2: Preferences (Large Settings-Style Cards + Pre-configured Theme Presets)
                        Flickable {
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: s2Col.implicitHeight + 16
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true
                            visible: opacity > 0.01
                            opacity: root.step === 2 ? 1.0 : 0.0
                            x: root.step === 2 ? 0 : (root.step > 2 ? -24 : 24)
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            ColumnLayout {
                                id: s2Col
                                width: parent.width
                                spacing: 14

                                Text {
                                    text: "Pre-configured Theme Presets (Live Preview)"
                                    color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2; columnSpacing: 10; rowSpacing: 10

                                    Repeater {
                                        model: Theme.presetCatalog
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            height: 76; radius: 12; clip: true
                                            readonly property bool active: root.optTheme === modelData.name
                                            color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                                          : (pMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                                            border.width: active ? 1.5 : 1
                                            border.color: active ? Theme.accent : Theme.borderSubtle
                                            scale: pMouse.pressed ? 0.97 : 1.0
                                            Behavior on color { ColorAnimation { duration: 140 } }
                                            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

                                            RowLayout {
                                                anchors.fill: parent; anchors.margins: 12; spacing: 12
                                                // Visual color swatch preview
                                                Rectangle {
                                                    width: 42; height: 42; radius: 10
                                                    color: modelData.previewBg
                                                    border.width: 1; border.color: Theme.borderSubtle
                                                    Rectangle {
                                                        anchors.centerIn: parent
                                                        width: 18; height: 18; radius: 9
                                                        color: modelData.previewAccent
                                                    }
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                                    Text { text: modelData.name; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                                    Text { text: modelData.shortDesc; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                                }
                                                SvgIcon { visible: active; sourceName: "check"; iconSize: 16; color: Theme.accent }
                                            }

                                            MouseArea {
                                                id: pMouse
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: root.selectTheme(modelData.name)
                                            }
                                        }
                                    }
                                }

                                Text {
                                    text: "Dynamic Island Position"
                                    color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 12; font.weight: Font.DemiBold
                                }

                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2; columnSpacing: 10
                                    Repeater {
                                        model: [
                                            { id: "top", title: "Top Edge (Default)", sub: "Centered Dynamic Island at top of screen" },
                                            { id: "bottom", title: "Bottom Edge", sub: "Dock-style Dynamic Island at bottom edge" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.fillWidth: true; height: 68; radius: 12; clip: true
                                            readonly property bool active: root.optBarPos === modelData.id
                                            color: active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                                          : (posMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                                            border.width: active ? 1.5 : 1
                                            border.color: active ? Theme.accent : Theme.borderSubtle
                                            scale: posMouse.pressed ? 0.97 : 1.0
                                            Behavior on color { ColorAnimation { duration: 140 } }
                                            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutBack } }

                                            RowLayout {
                                                anchors.fill: parent; anchors.margins: 12; spacing: 10
                                                ColumnLayout {
                                                    Layout.fillWidth: true; spacing: 2
                                                    Text { text: modelData.title; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                                                    Text { text: modelData.sub; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                                }
                                                SvgIcon { visible: active; sourceName: "check"; iconSize: 16; color: Theme.accent }
                                            }
                                            MouseArea {
                                                id: posMouse
                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                onClicked: root.optBarPos = modelData.id
                                            }
                                        }
                                    }
                                }

                                // Autostart Large Toggle Card
                                Rectangle {
                                    Layout.fillWidth: true; height: 60; radius: 12; clip: true
                                    color: autoMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                                    border.width: 1
                                    border.color: root.optAutostart ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42) : Theme.borderSubtle
                                    scale: autoMouse.pressed ? 0.99 : 1.0
                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                    MouseArea {
                                        id: autoMouse
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.optAutostart = !root.optAutostart
                                    }

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                        Rectangle {
                                            width: 30; height: 30; radius: 8
                                            color: root.optAutostart ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.surfaceRaised
                                            border.width: 1; border.color: root.optAutostart ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                                            SvgIcon { anchors.centerIn: parent; sourceName: "bolt"; iconSize: 15; color: root.optAutostart ? Theme.accent : Theme.textMuted }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                            Text { text: "Hyprland Autostart"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Text {
                                                text: (root.optSyncHypr || root.hyprConfigKind === "lua")
                                                    ? "Launch Paithosh automatically in Hyprland Lua config"
                                                    : "Launch Paithosh automatically in ~/.config/hypr/hyprland.conf"
                                                color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true
                                            }
                                        }
                                        InstallerSwitch {
                                            checked: root.optAutostart
                                            onToggled: root.optAutostart = !root.optAutostart
                                        }
                                    }
                                }

                                // XDG Desktop Portals Toggle Card
                                Rectangle {
                                    Layout.fillWidth: true; height: 60; radius: 12; clip: true
                                    color: portalMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                                    border.width: 1
                                    border.color: root.optSetupPortals ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42) : Theme.borderSubtle
                                    scale: portalMouse.pressed ? 0.99 : 1.0
                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                    MouseArea {
                                        id: portalMouse
                                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: root.optSetupPortals = !root.optSetupPortals
                                    }

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
                                        Rectangle {
                                            width: 30; height: 30; radius: 8
                                            color: root.optSetupPortals ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.surfaceRaised
                                            border.width: 1; border.color: root.optSetupPortals ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                                            SvgIcon { anchors.centerIn: parent; sourceName: "layers"; iconSize: 15; color: root.optSetupPortals ? Theme.accent : Theme.textMuted }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                            Text { text: "XDG Desktop Portals"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                                            Text { text: "Register Paithosh Screen Share picker & FileChooser portal"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                        }
                                        InstallerSwitch {
                                            checked: root.optSetupPortals
                                            onToggled: root.optSetupPortals = !root.optSetupPortals
                                        }
                                    }
                                }
                            }
                        }

                        // STEP 3: Progress Circle (live status + optional/error log)
                        ColumnLayout {
                            anchors.fill: parent; spacing: 14
                            visible: opacity > 0.01
                            opacity: root.step === 3 ? 1.0 : 0.0
                            x: root.step === 3 ? 0 : 24
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            Connections {
                                target: Theme
                                function onTextChanged() { trackCanvas.requestPaint(); }
                                function onAccentChanged() { progressCanvas.requestPaint(); }
                            }

                            Item { Layout.fillHeight: true; visible: !(root.showFullLog || (root.installDone && root.installExitCode !== 0)) }

                            // Centered Progress Circle + Status
                            ColumnLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 12

                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 140; height: 140

                                    // Track ring
                                    Canvas {
                                        id: trackCanvas
                                        anchors.fill: parent
                                        onPaint: {
                                            const ctx = getContext("2d");
                                            ctx.reset();
                                            ctx.lineWidth = 7;
                                            ctx.strokeStyle = Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.10);
                                            ctx.beginPath();
                                            ctx.arc(width / 2, height / 2, width / 2 - 8, 0, Math.PI * 2);
                                            ctx.stroke();
                                        }
                                    }

                                    // Determinate 0% -> 100% progress arc
                                    Canvas {
                                        id: progressCanvas
                                        anchors.fill: parent
                                        visible: root.installing
                                        property real progress: root.installProgress
                                        onProgressChanged: requestPaint()
                                        onPaint: {
                                            const ctx = getContext("2d");
                                            ctx.reset();
                                            ctx.lineWidth = 7;
                                            ctx.lineCap = "round";
                                            ctx.strokeStyle = Theme.accent;
                                            ctx.beginPath();
                                            ctx.arc(width / 2, height / 2, width / 2 - 8, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * progress);
                                            ctx.stroke();
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: root.installing
                                        text: Math.round(root.installProgress * 100) + "%"
                                        color: Theme.text
                                        font.family: Theme.fontMono
                                        font.pixelSize: 22
                                        font.weight: Font.Bold
                                    }

                                    // Completion / Error badge inside circle
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 96; height: 96; radius: 48
                                        visible: root.installDone
                                        color: root.installExitCode === 0
                                            ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.16)
                                            : Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.16)
                                        border.width: 1.5
                                        border.color: root.installExitCode === 0 ? Theme.ok : Theme.danger
                                        SvgIcon {
                                            anchors.centerIn: parent
                                            sourceName: root.installExitCode === 0 ? "check" : "close"
                                            iconSize: 38
                                            color: root.installExitCode === 0 ? Theme.ok : Theme.danger
                                        }
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: root.installing
                                        ? "Installing Paithosh..."
                                        : (root.installExitCode === 0 ? "Installation Complete!" : "Installation Failed (exit " + root.installExitCode + ")")
                                    color: root.installDone && root.installExitCode === 0 ? Theme.ok : (root.installDone && root.installExitCode !== 0 ? Theme.dangerText : Theme.text)
                                    font.family: Theme.fontSans; font.pixelSize: 16; font.weight: Font.DemiBold
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.maximumWidth: 520
                                    visible: root.currentLogLine !== ""
                                    text: root.currentLogLine
                                    color: Theme.textSub
                                    font.family: Theme.fontMono; font.pixelSize: 11
                                    elide: Text.ElideRight
                                }

                                RowLayout {
                                    Layout.alignment: Qt.AlignHCenter
                                    spacing: 10
                                    Text {
                                        visible: root.isDryRun
                                        text: "Dry-run simulation mode (no system changes)"
                                        color: Theme.textMuted
                                        font.family: Theme.fontSans; font.pixelSize: 11
                                    }
                                    PillButton {
                                        visible: root.installing || (root.installDone && root.installExitCode === 0)
                                        text: root.showFullLog ? "Hide Log" : "Show Log"
                                        fontSize: 11; horizontalPadding: 10; verticalPadding: 4
                                        onClicked: root.showFullLog = !root.showFullLog
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true; visible: !(root.showFullLog || (root.installDone && root.installExitCode !== 0)) }

                            // Live / Error Log Panel
                            Rectangle {
                                visible: root.showFullLog || (root.installDone && root.installExitCode !== 0)
                                Layout.fillWidth: true; Layout.fillHeight: true
                                radius: 12; clip: true
                                color: Theme.surfaceRaised
                                border.width: 1
                                border.color: (root.installDone && root.installExitCode !== 0)
                                    ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.45)
                                    : Theme.borderSubtle
                                Flickable {
                                    id: logFlick
                                    anchors.fill: parent; anchors.margins: 12
                                    contentWidth: width
                                    contentHeight: logText.implicitHeight; clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    Text {
                                        id: logText
                                        width: parent.width
                                        text: root.installLog
                                        color: (root.installDone && root.installExitCode !== 0) ? Theme.dangerText : Theme.textSub
                                        font.family: Theme.fontMono; font.pixelSize: 11
                                        wrapMode: Text.Wrap
                                        onImplicitHeightChanged: {
                                            if (logFlick.contentHeight > logFlick.height) {
                                                logFlick.contentY = logFlick.contentHeight - logFlick.height;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                    // Bottom Action Bar
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 60
                        Layout.leftMargin: 20; Layout.rightMargin: 20
                        spacing: 10

                        PillButton {
                            text: "Back"
                            visible: (root.step > 0 && root.step < 3) || (root.step === 3 && root.installDone && root.installExitCode !== 0)
                            onClicked: root.step = root.step === 3 ? 2 : Math.max(0, root.step - 1)
                        }

                        Item { Layout.fillWidth: true }

                        PillButton {
                            text: root.step === 2 ? "Install Now" : "Next"
                            iconName: root.step === 2 ? "download" : "chevron-right"
                            active: true
                            visible: root.step < 3
                            enabled: !root.installing && (root.step === 0 || (!root.loadingAudit && root.auditError === ""))
                            onClicked: {
                                if (root.step < 2) root.step += 1;
                                else root.startInstall();
                            }
                        }

                        PillButton {
                            text: "Retry"
                            iconName: "refresh"
                            active: true
                            visible: root.step === 3 && root.installDone && root.installExitCode !== 0
                            onClicked: root.startInstall()
                        }

                        PillButton {
                            text: root.installExitCode === 0 && !root.isDryRun ? "Finish & Launch" : "Finish"
                            iconName: "check"
                            active: root.installExitCode === 0
                            visible: root.step === 3 && root.installDone
                            onClicked: root.closeInstaller()
                        }
                    }
                }
            }
        }

        // Inline Sudo Password Dialog (used when Polkit agent is absent or AUR helper needs sudo)
        Rectangle {
            id: sudoOverlay
            anchors.fill: parent
            z: 50
            color: Qt.rgba(0, 0, 0, 0.56)
            visible: root.sudoPromptOpen || opacity > 0.01
            opacity: root.sudoPromptOpen ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

            function cancelPrompt() {
                sudoPasswordField.text = "";
                root.sudoPromptError = "";
                root.sudoPromptOpen = false;
                if (root.step === 3 && !root.installing && !root.installDone) {
                    root.step = 2;
                }
                scrimRoot.forceActiveFocus();
            }
            function submitPrompt() {
                const pwd = sudoPasswordField.text;
                if (!pwd || pwd.length === 0) {
                    root.sudoPromptError = "Password cannot be empty.";
                    return;
                }
                sudoPasswordField.text = "";
                root.sudoPromptError = "";
                root.sudoPromptOpen = false;
                scrimRoot.forceActiveFocus();
                root.launchApply(pwd);
            }

            Connections {
                target: root
                function onSudoPromptOpenChanged() {
                    if (root.sudoPromptOpen) {
                        sudoPasswordField.text = "";
                        sudoPasswordField.forceActiveFocus();
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.sudoPromptOpen
                onClicked: sudoOverlay.cancelPrompt()
            }

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 48, 400)
                implicitHeight: sudoCol.implicitHeight + 36
                radius: 14; clip: true
                color: Theme.surfaceRaised
                border.width: 1; border.color: Theme.borderSubtle
                scale: root.sudoPromptOpen ? 1.0 : 0.94
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: sudoCol
                    anchors.fill: parent; anchors.margins: 18; spacing: 12

                    Text {
                        Layout.fillWidth: true
                        text: "Administrator Authentication"
                        color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 15; font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Enter your sudo password to install " + root.selectedPkgList().length + " selected package(s) via " + root.distroInfo.pkgMgr + "."
                        color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                    Rectangle {
                        Layout.fillWidth: true; height: 38; radius: 8; clip: true
                        color: Theme.pillBg
                        border.width: 1; border.color: sudoPasswordField.activeFocus ? Theme.accent : Theme.borderSubtle

                        AnimatedTextInput {
                            id: sudoPasswordField
                            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: TextInput.Password
                            textColor: Theme.text
                            font.family: Theme.fontSans; font.pixelSize: 13
                            Keys.onReturnPressed: sudoOverlay.submitPrompt()
                            Keys.onEnterPressed: sudoOverlay.submitPrompt()
                            Keys.onEscapePressed: sudoOverlay.cancelPrompt()
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: root.sudoPromptError !== ""
                        text: root.sudoPromptError
                        color: Theme.dangerText; font.family: Theme.fontSans; font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Item { Layout.fillWidth: true }
                        PillButton { text: "Cancel"; onClicked: sudoOverlay.cancelPrompt() }
                        PillButton { text: "Authenticate & Install"; active: true; onClicked: sudoOverlay.submitPrompt() }
                    }
                }
            }
        }
    }
}
