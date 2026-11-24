pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "."

Singleton {
    id: root

    readonly property string homeDir: Quickshell.env("HOME") || "/tmp"
    readonly property string scriptPath: decodeURIComponent(Qt.resolvedUrl("../scripts/paithosh-cursor-gen.py").toString().replace(/^file:\/\//, ""))
    readonly property string previewDir: homeDir + "/.cache/paithosh/cursors"

    readonly property var styleCatalog: [
        { id: "sharp", name: "Classic Sharp", subtitle: "Sharp tip • Tail" },
        { id: "soft", name: "Soft Stem", subtitle: "Rounded tip • Tail" },
        { id: "wedge", name: "Smooth Wedge", subtitle: "Rounded tip • Tailless" }
    ]
    readonly property var fixedSwatches: ["#ffffff", "#111113", "#88c0d0", "#cba6f7", "#80cbc4", "#ff9f0a", "#ff453a"]

    // Persisted settings (synced via shell.qml + PAISH1 codes)
    property string style: "sharp"        // "sharp" | "soft" | "wedge"
    property int size: 24                 // 16..64
    property string colorMode: "auto"     // "auto" | "theme" | "fixed"
    property string fixedColor: "#ffffff"
    property bool motionBlur: false
    property real motionBlurStrength: 0.65

    // Runtime & live daemon state
    property bool depsReady: true
    property string activeThemeId: ""
    property string lightThemeId: ""
    property string darkThemeId: ""
    property string activeContrastTone: "light" // "light" (for dark screens) | "dark" (for light screens)
    property real lastLuminance: 0.12
    property string resolvedFill: "#ffffff"
    property string resolvedOutline: "#0b0b0c"
    property real hotspotX: 6.5 / 32.0
    property real hotspotY: 2.5 / 32.0
    property bool applying: false
    property string lastError: ""
    property string previewTag: ""
    property bool _reapplyPending: false
    property bool _initialApplied: false

    // Motion blur live cursor telemetry (updated only when motionBlur is active)
    property real cursorX: 0
    property real cursorY: 0
    property real cursorVx: 0
    property real cursorVy: 0
    property real cursorSpeed: 0
    property bool cursorMoving: false

    readonly property string styleLabel: {
        for (let i = 0; i < styleCatalog.length; ++i) {
            if (styleCatalog[i].id === style) return styleCatalog[i].name;
        }
        return "Classic Sharp";
    }

    readonly property string colorModeLabel: {
        if (colorMode === "theme") return "Theme";
        if (colorMode === "fixed") return "Fixed";
        return "Auto";
    }

    readonly property bool daemonShouldRun: depsReady
        && CompositorService.isHyprland
        && !LockService.locked
        && (colorMode === "auto" || motionBlur)
        && activeThemeId !== ""
        && (colorMode !== "auto" || (lightThemeId !== "" && darkThemeId !== ""))

    readonly property string daemonSignature: style + "|" + size + "|" + colorMode + "|" + lightThemeId + "|" + darkThemeId + "|" + (motionBlur ? "1" : "0")

    Component.onCompleted: {
        checkDeps();
        refreshPreviews();
    }

    function normalizeStyle(s) {
        const clean = String(s || "").trim().toLowerCase();
        return (clean === "sharp" || clean === "soft" || clean === "wedge") ? clean : "sharp";
    }

    function normalizeColorMode(m) {
        const clean = String(m || "").trim().toLowerCase();
        return (clean === "auto" || clean === "theme" || clean === "fixed") ? clean : "auto";
    }

    function normalizeHex(hex) {
        const s = String(hex || "").trim();
        if (/^#[0-9a-fA-F]{6}$/.test(s)) return s.toLowerCase();
        if (/^[0-9a-fA-F]{6}$/.test(s)) return "#" + s.toLowerCase();
        return "#ffffff";
    }

    function targetFillColor() {
        if (colorMode === "theme") return normalizeHex(String(Theme.accent));
        if (colorMode === "fixed") return normalizeHex(fixedColor);
        return activeContrastTone === "dark" ? "#111113" : "#ffffff";
    }

    function setStyle(s) {
        const next = normalizeStyle(s);
        if (style === next) return;
        style = next;
        _scheduleApply(80);
    }

    function setSize(px) {
        const next = Math.max(16, Math.min(64, Math.round(Number(px) || 24)));
        if (size === next) return;
        size = next;
        _scheduleApply(140);
    }

    function setColorMode(m) {
        const next = normalizeColorMode(m);
        if (colorMode === next) return;
        colorMode = next;
        _scheduleApply(80);
    }

    function setFixedColor(hex) {
        const next = normalizeHex(hex);
        if (fixedColor === next && colorMode === "fixed") return;
        fixedColor = next;
        if (colorMode !== "fixed") colorMode = "fixed";
        _scheduleApply(130);
    }

    function setMotionBlur(enabled) {
        const next = Boolean(enabled);
        if (motionBlur === next) return;
        motionBlur = next;
        if (!next) {
            cursorMoving = false;
            cursorVx = 0;
            cursorVy = 0;
            cursorSpeed = 0;
        }
        _syncDaemon();
    }

    function setMotionBlurStrength(val) {
        const next = Math.max(0.3, Math.min(1.0, Math.round((Number(val) || 0.65) * 100) / 100));
        if (Math.abs(motionBlurStrength - next) < 0.005) return;
        motionBlurStrength = next;
    }

    function resetDefaults() {
        style = "sharp";
        size = 24;
        colorMode = "auto";
        fixedColor = "#ffffff";
        motionBlur = false;
        motionBlurStrength = 0.65;
        cursorMoving = false;
        _scheduleApply(40);
    }

    function applyNow(force) {
        applyTimer.stop();
        if (force || !_initialApplied) {
            _initialApplied = true;
            _runApply();
        } else {
            _scheduleApply(60);
        }
    }

    function refreshPreviews() {
        if (previewProc.running) return;
        previewProc.outBuf = "";
        previewProc.command = [
            "python3", root.scriptPath, "preview-svgs",
            "--style", root.style,
            "--fill", root.targetFillColor()
        ];
        previewProc.running = true;
    }

    function checkDeps(cb) {
        depCheckProc._callback = typeof cb === "function" ? cb : null;
        depCheckProc.running = false;
        depCheckProc.running = true;
    }

    function _scheduleApply(delayMs) {
        applyTimer.interval = Math.max(40, delayMs || 120);
        applyTimer.restart();
    }

    function _runApply() {
        if (applyProc.running) {
            _reapplyPending = true;
            return;
        }
        applying = true;
        lastError = "";
        const args = [
            "python3", root.scriptPath, "apply",
            "--style", root.style,
            "--size", String(root.size),
            "--color-mode", root.colorMode,
            "--fill", root.targetFillColor(),
            "--initial-tone", root.activeContrastTone
        ];
        if (!CompositorService.isHyprland) args.push("--no-live");
        applyProc.outBuf = "";
        applyProc.errBuf = "";
        applyProc.command = args;
        applyProc.running = true;
    }

    function _syncDaemon() {
        if (!daemonShouldRun) {
            if (daemonProc.running) daemonProc.running = false;
            cursorMoving = false;
            return;
        }
        if (daemonProc.running && daemonProc._activeSig === daemonSignature) return;
        daemonProc.running = false;
        daemonProc._activeSig = daemonSignature;
        daemonProc.command = [
            "python3", root.scriptPath, "daemon",
            "--style", root.style,
            "--auto-contrast", root.colorMode === "auto" ? "1" : "0",
            "--motion-blur", root.motionBlur ? "1" : "0",
            "--size", String(root.size),
            "--light-theme", root.lightThemeId,
            "--dark-theme", root.darkThemeId,
            "--initial-tone", root.activeContrastTone
        ];
        daemonProc.running = true;
    }

    onDaemonShouldRunChanged: _syncDaemon()
    onDaemonSignatureChanged: {
        if (daemonShouldRun) Qt.callLater(_syncDaemon);
    }

    Timer {
        id: applyTimer
        interval: 120
        repeat: false
        onTriggered: root._runApply()
    }

    Connections {
        target: Theme
        function onAccentChanged() {
            if (root.colorMode === "theme" && root._initialApplied) {
                root._scheduleApply(200);
            }
        }
        function onActivePresetChanged() {
            if (root.colorMode === "theme" && root._initialApplied) {
                root._scheduleApply(200);
            }
        }
    }

    Process {
        id: depCheckProc
        property var _callback: null
        command: [
            "sh", "-c",
            "command -v hyprcursor-util >/dev/null 2>&1 && python3 -c 'import cairo, gi; gi.require_version(\"Rsvg\", \"2.0\"); from gi.repository import Rsvg' >/dev/null 2>&1"
        ]
        onExited: (code) => {
            root.depsReady = (code === 0);
            const cb = _callback;
            _callback = null;
            if (cb) cb(root.depsReady);
            root._syncDaemon();
        }
    }

    Process {
        id: previewProc
        property string outBuf: ""
        stdout: StdioCollector {
            onStreamFinished: previewProc.outBuf = text || ""
        }
        onExited: (code) => {
            if (code === 0) {
                try {
                    const res = JSON.parse(previewProc.outBuf.trim());
                    if (res.previewTag) root.previewTag = res.previewTag;
                } catch (e) {}
            }
        }
    }

    Process {
        id: applyProc
        property string outBuf: ""
        property string errBuf: ""

        stdout: StdioCollector {
            onStreamFinished: applyProc.outBuf = text || ""
        }
        stderr: StdioCollector {
            onStreamFinished: applyProc.errBuf = text || ""
        }
        onExited: (code) => {
            root.applying = false;
            if (code === 0) {
                try {
                    const res = JSON.parse(applyProc.outBuf.trim());
                    root.activeThemeId = res.themeId || "";
                    root.lightThemeId = res.lightThemeId || "";
                    root.darkThemeId = res.darkThemeId || "";
                    root.resolvedFill = res.fill || "#ffffff";
                    root.resolvedOutline = res.outline || "#0b0b0c";
                    if (typeof res.hotspotX === "number") root.hotspotX = res.hotspotX;
                    if (typeof res.hotspotY === "number") root.hotspotY = res.hotspotY;
                    if (res.previewTag) root.previewTag = res.previewTag;
                    root.lastError = "";
                } catch (e) {
                    root.lastError = "Failed to parse cursor apply output";
                }
            } else {
                const err = (applyProc.errBuf || "").trim();
                root.lastError = err !== "" ? err : "Cursor build/sync failed";
            }

            if (root._reapplyPending) {
                root._reapplyPending = false;
                Qt.callLater(root._runApply);
            } else {
                root._syncDaemon();
            }
        }
    }

    Process {
        id: daemonProc
        property string _activeSig: ""
        stdout: SplitParser {
            onRead: (line) => {
                const s = (line || "").trim();
                if (!s) return;
                if (s.startsWith("POS ")) {
                    const parts = s.split(" ");
                    if (parts.length >= 6) {
                        root.cursorX = parseFloat(parts[1]) || 0;
                        root.cursorY = parseFloat(parts[2]) || 0;
                        root.cursorVx = parseFloat(parts[3]) || 0;
                        root.cursorVy = parseFloat(parts[4]) || 0;
                        root.cursorSpeed = parseFloat(parts[5]) || 0;
                        root.cursorMoving = true;
                    }
                } else if (s === "IDLE") {
                    root.cursorMoving = false;
                    root.cursorVx = 0;
                    root.cursorVy = 0;
                    root.cursorSpeed = 0;
                } else if (s.startsWith("CONTRAST ")) {
                    const parts = s.split(" ");
                    if (parts.length >= 3) {
                        const tone = parts[1] === "dark" ? "dark" : "light";
                        root.activeContrastTone = tone;
                        root.lastLuminance = parseFloat(parts[2]) || 0;
                        root.activeThemeId = (tone === "dark") ? root.darkThemeId : root.lightThemeId;
                        root.resolvedFill = (tone === "dark") ? "#111113" : "#ffffff";
                        root.resolvedOutline = (tone === "dark") ? "#ffffff" : "#0b0b0c";
                        if (parts.length >= 4 && parts[3]) root.previewTag = parts[3];
                    }
                }
            }
        }
        onExited: {
            root.cursorMoving = false;
        }
    }
}
