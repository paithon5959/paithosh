import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "services"
import "components"

ShellRoot {
    id: root

    Component.onCompleted: SoundService.recoverOrphanedDuck()

    PersistentProperties {
        id: reloadState
        reloadableId: "paithoshReloadState"
        property bool pendingEntrance: false
        property bool pendingBgReveal: false
        property bool pendingOverlayReveal: false
        property string reloadReason: ""
        property string lastWallpaperPath: ""
        property bool lastWallpapersDisabled: false
        property bool lastReduceMotion: false

        onReloaded: {
            Theme.wallpapersDisabled = lastWallpapersDisabled;
            Theme.reduceMotion = lastReduceMotion;
            if (lastReduceMotion) {
                Qt.callLater(() => CompositorService.applyReduceMotion(true));
            }
            stateObj._handledReloadEntrance = true;
            const msg = pendingEntrance
                ? (reloadReason !== "" ? reloadReason : "Config Reloaded")
                : "Config Reloaded";
            const showOverlayReveal = pendingOverlayReveal;
            pendingEntrance = false;
            pendingOverlayReveal = false;
            reloadReason = "";
            if (showOverlayReveal) {
                stateObj.reloadInstantOpaque = true;
                stateObj.reloadPhase = "revealing";
                reloadRevealHoldTimer.restart();
            }
            reloadPostShowTimer.pendingMessage = msg;
            reloadPostShowTimer.interval = showOverlayReveal ? 820 : 120;
            reloadPostShowTimer.restart();
        }
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() {
            Quickshell.inhibitReloadPopup();
            if (!stateObj._handledReloadEntrance) {
                stateObj._handledReloadEntrance = true;
                reloadPostShowTimer.pendingMessage = "Config Reloaded";
                reloadPostShowTimer.restart();
            }
        }
        function onReloadFailed(errorString) {
            Quickshell.inhibitReloadPopup();
            reloadCollapseTimer.stop();
            reloadCommitTimer.stop();
            reloadExecuteTimer.stop();
            reloadSafetyTimer.stop();
            reloadState.pendingEntrance = false;
            reloadState.pendingBgReveal = false;
            reloadState.pendingOverlayReveal = false;
            reloadState.reloadReason = "";
            stateObj.reloadPhase = "idle";
            stateObj.showReloadResult(false, "Reload Failed");
            console.warn("[paithosh] Shell reload failed:", errorString);
        }
    }

    BackgroundLayer {
        id: bgLayer
        initialWallpaperPath: reloadState.lastWallpaperPath
        initialVeilOpacity: reloadState.pendingBgReveal ? 1.0 : 0.0
        targetVeilOpacity: (stateObj.sessionPhase === "fading" || stateObj.sessionPhase === "executing")
            ? 1.0
            : ((stateObj.reloadPhase === "exiting" || stateObj.reloadPhase === "committing" || stateObj.reloadPhase === "revealing") ? 1.0 : 0.0)
        targetStageScale: (stateObj.sessionPhase === "fading" || stateObj.sessionPhase === "executing")
            ? 0.98
            : ((stateObj.reloadPhase === "exiting" || stateObj.reloadPhase === "committing" || stateObj.reloadPhase === "revealing") ? 1.02 : 1.0)
    }

    Binding {
        target: DiscordRpcService
        property: "themeName"
        value: Theme.wallpaperColorEnabled ? ("Wallpaper (" + Theme.wallpaperColorMode + ")") : Theme.activePreset
    }

    property string profileDir: (Quickshell.env("HOME") || "/tmp") + "/.config/paithosh"
    property string settingsPath: profileDir + "/settings.json"
    readonly property string paishScript: Quickshell.shellDir + "/scripts/paithosh-paish.py"
    readonly property string wallpaperColorScript: Quickshell.shellDir + "/scripts/paithosh-wallpaper-color.py"
    readonly property string themeSyncScript: Quickshell.shellDir + "/scripts/paithosh-theme-sync.py"

    FileView {
        id: settingsFile
        path: root.settingsPath
        preload: true
        onLoaded: {
            let hasSettings = false;
            stateObj._applyingExternalState = true;
            try {
                const raw = text();
                if (raw && raw.trim() !== "") {
                    hasSettings = true;
                    const obj = JSON.parse(raw);
                    if (typeof obj.hideBarFullscreen === "boolean") stateObj.hideBarFullscreen = obj.hideBarFullscreen;
                    if (typeof obj.autoHideOnOverlap === "boolean") stateObj.autoHideOnOverlap = obj.autoHideOnOverlap;
                    if (typeof obj.dodgeCursor === "boolean") stateObj.dodgeCursor = obj.dodgeCursor;
                    if (typeof obj.recordAudio === "boolean") {
                        stateObj.recordAudio = obj.recordAudio;
                        ScreenRecordService.recordAudio = obj.recordAudio;
                    }
                    if (typeof obj.recordMic === "boolean") {
                        stateObj.recordMic = obj.recordMic;
                        ScreenRecordService.recordMic = obj.recordMic;
                    }
                    if (typeof obj.recordPreset === "string") {
                        stateObj.recordPreset = obj.recordPreset;
                        ScreenRecordService.preset = obj.recordPreset;
                    }
                    if (typeof obj.recordResolution === "string") {
                        stateObj.recordResolution = obj.recordResolution;
                        ScreenRecordService.resolution = obj.recordResolution;
                    }
                    if (typeof obj.recordFps === "number") {
                        stateObj.recordFps = obj.recordFps;
                        ScreenRecordService.fps = obj.recordFps;
                    }
                    if (typeof obj.recordCodec === "string") {
                        stateObj.recordCodec = obj.recordCodec;
                        ScreenRecordService.codec = obj.recordCodec;
                    }
                    if (typeof obj.inputIndicatorEnabled === "boolean") {
                        stateObj.inputIndicatorEnabled = obj.inputIndicatorEnabled;
                        InputIndicatorService.enabled = obj.inputIndicatorEnabled;
                    }
                    if (typeof obj.capsLockIndicatorEnabled === "boolean") {
                        stateObj.capsLockIndicatorEnabled = obj.capsLockIndicatorEnabled;
                        InputIndicatorService.capsLockEnabled = obj.capsLockIndicatorEnabled;
                    }
                    if (typeof obj.fcitxIndicatorEnabled === "boolean") {
                        stateObj.fcitxIndicatorEnabled = obj.fcitxIndicatorEnabled;
                        InputIndicatorService.fcitxEnabled = obj.fcitxIndicatorEnabled;
                    }
                    if (typeof obj.recordSaveDir === "string") {
                        stateObj.recordSaveDir = obj.recordSaveDir;
                        ScreenRecordService.saveDir = obj.recordSaveDir;
                    }
                    if (typeof obj.islandCornerRadius === "string") stateObj.islandCornerRadius = obj.islandCornerRadius;
                    if (typeof obj.barPosition === "string") stateObj.barPosition = obj.barPosition === "bottom" ? "bottom" : "top";
                    if (typeof obj.topEdgeOffset === "boolean") stateObj.topEdgeOffset = obj.topEdgeOffset;
                    if (typeof obj.activeBorderHighlight === "boolean") stateObj.activeBorderHighlight = obj.activeBorderHighlight;
                    if (typeof obj.globalSurfaceTheme === "string") stateObj.globalSurfaceTheme = obj.globalSurfaceTheme;
                    if (typeof obj.activeProfile === "string") stateObj.activeProfile = obj.activeProfile;
                    const wpDisabled = Boolean(obj.wallpapersDisabled);
                    const wpColorOn = !wpDisabled && Boolean(obj.wallpaperColorEnabled);
                    reloadState.lastWallpapersDisabled = wpDisabled;
                    Theme.wallpapersDisabled = wpDisabled;
                    if (typeof obj.themePreset === "string") Theme.applyPreset(obj.themePreset, wpColorOn);
                    if (!wpColorOn) Theme.applySurfaceTheme(stateObj.globalSurfaceTheme);
                    else Theme.surfaceTheme = stateObj.globalSurfaceTheme;
                    Theme.applyPaletteState(obj, false);
                    if (typeof obj.masterRatio === "number") Theme.masterRatio = obj.masterRatio;
                    if (typeof obj.preserveSplit === "boolean") Theme.preserveSplit = obj.preserveSplit;
                    if (typeof obj.shadowRange === "number") Theme.shadowRange = obj.shadowRange;
                    if (typeof obj.gooeyEnabled === "boolean") Theme.gooeyEnabled = obj.gooeyEnabled;
                    if (typeof obj.reduceMotion === "boolean") Theme.reduceMotion = obj.reduceMotion;
                    reloadState.lastReduceMotion = Theme.reduceMotion;
                    if (typeof obj.speedMultiplier === "number" && obj.speedMultiplier >= 0.5 && obj.speedMultiplier <= 2.5) Theme.speedMultiplier = obj.speedMultiplier;
                    if (typeof obj.transitionMode === "string") bgLayer.transitionMode = obj.transitionMode;
                    if (typeof obj.wallpaperPath === "string" && obj.wallpaperPath.length > 0) {
                        bgLayer.applyWallpaperPath(obj.wallpaperPath);
                    } else if (typeof obj.wallpaperIndex === "number") {
                        bgLayer.applyWallpaperIndex(obj.wallpaperIndex);
                    }
                    if (typeof obj.lockEffectPreset === "string" && ["none", "snow", "rain", "wind"].indexOf(obj.lockEffectPreset) !== -1) {
                        LockService.effectPreset = obj.lockEffectPreset;
                    }
                    if (typeof obj.lockAmbientSound === "string" && ["none", "wind", "rain", "snow"].indexOf(obj.lockAmbientSound) !== -1) {
                        LockService.ambientSound = obj.lockAmbientSound;
                    }
                    if (typeof obj.lockSilentMode === "boolean") LockService.silentMode = obj.lockSilentMode;
                    if (typeof obj.lockSfxEnabled === "boolean") LockService.sfxEnabled = obj.lockSfxEnabled;
                    if (typeof obj.lockShowNotifications === "boolean") LockService.showNotifications = obj.lockShowNotifications;
                    if (typeof obj.lockHideNotifContent === "boolean") LockService.hideNotifContent = obj.lockHideNotifContent;
                    if (typeof obj.lockShowMedia === "boolean") LockService.showMedia = obj.lockShowMedia;
                    if (typeof obj.lockShowSystemAlerts === "boolean") LockService.showSystemAlerts = obj.lockShowSystemAlerts;
                    if (typeof obj.lockEffectIntensity === "number") LockService.effectIntensity = Math.max(50, Math.min(150, Math.round(obj.lockEffectIntensity)));
                    if (typeof obj.lockAmbientVolume === "number") LockService.ambientVolume = Math.max(5, Math.min(100, Math.round(obj.lockAmbientVolume)));
                    if (typeof obj.lockDimOpacity === "number") LockService.dimOpacity = Math.max(15, Math.min(75, Math.round(obj.lockDimOpacity)));
                    if (typeof obj.systemSoundEnabled === "boolean") SoundService.enabled = obj.systemSoundEnabled;
                    if (typeof obj.systemSoundVolume === "number") SoundService.setVolumePct(obj.systemSoundVolume);
                    if (typeof obj.cursorStyle === "string") CursorService.style = CursorService.normalizeStyle(obj.cursorStyle);
                    if (typeof obj.cursorSize === "number") CursorService.size = Math.max(16, Math.min(64, Math.round(obj.cursorSize)));
                    if (typeof obj.cursorColorMode === "string") CursorService.colorMode = CursorService.normalizeColorMode(obj.cursorColorMode);
                    if (typeof obj.cursorFixedColor === "string") CursorService.fixedColor = CursorService.normalizeHex(obj.cursorFixedColor);
                    if (typeof obj.cursorMotionBlur === "boolean") CursorService.motionBlur = obj.cursorMotionBlur;
                    if (typeof obj.cursorMotionBlurStrength === "number") CursorService.motionBlurStrength = Math.max(0.3, Math.min(1.0, obj.cursorMotionBlurStrength));
                    if (typeof obj.cursorMotionBlurThreshold === "number") CursorService.motionBlurThreshold = Math.max(0, Math.min(2400, Math.round(obj.cursorMotionBlurThreshold)));
                }
            } catch (e) {}
            stateObj._applyingExternalState = false;
            stateObj.applyIslandMetrics();
            stateObj.settingsLoaded = true;
            stateObj.themeImportSeq += 1;
            Qt.callLater(function() {
                CompositorService.setActiveThemePresetName(stateObj.compositorKeyForPreset(Theme.activePreset));
                CompositorService.applyReduceMotion(Theme.reduceMotion);
                stateObj.syncHyprThemeColors();
                stateObj.refreshProfiles();
                if (!hasSettings) stateObj.loadProfile("default", true);
                if (Theme.wallpaperColorEnabled && !Theme.wallpapersDisabled && bgLayer.currentWallpaperPath !== "") {
                    stateObj.syncWallpaperColors(false, false);
                }
                cursorBootApplyTimer.restart();
            });
        }
        onLoadFailed: {
            stateObj.applyIslandMetrics();
            stateObj.settingsLoaded = true;
            stateObj.themeImportSeq += 1;
            Qt.callLater(function() {
                CompositorService.setActiveThemePresetName(stateObj.compositorKeyForPreset(Theme.activePreset));
                CompositorService.applyReduceMotion(Theme.reduceMotion);
                stateObj.syncHyprThemeColors();
                stateObj.refreshProfiles();
                stateObj.loadProfile("default", true);
                cursorBootApplyTimer.restart();
            });
        }
    }

    Timer {
        id: cursorBootApplyTimer
        interval: 1600
        repeat: false
        onTriggered: CursorService.applyNow(false)
    }

    // Background QML bytecode pre-warmer (compiles lazy views off-thread after boot; zero object instantiation)
    property var _prewarmCache: []
    property int _prewarmIdx: 0
    readonly property var _prewarmUrls: [
        "components/LauncherView.qml",
        "components/DashboardView.qml",
        "components/FilesView.qml",
        "components/MusicView.qml",
        "components/MusicSettingsPage.qml",
        "components/SettingsView.qml",
        "components/ClipboardView.qml",
        "components/SearchResultsView.qml",
        "components/WorkspaceOverview.qml",
        "components/PickerView.qml",
        "components/PortalView.qml",
        "components/AppChooserView.qml",
        "components/ModalOverlay.qml",
        "components/DetachedAppWindow.qml",
        "components/LockScreen.qml"
    ]

    function _prewarmNext() {
        if (_prewarmIdx >= _prewarmUrls.length) return;
        const url = _prewarmUrls[_prewarmIdx++];
        const comp = Qt.createComponent(url, Component.Asynchronous);
        _prewarmCache.push(comp);
        if (comp.status === Component.Loading) {
            comp.statusChanged.connect(function() {
                if (comp.status !== Component.Loading) prewarmStepTimer.restart();
            });
        } else {
            prewarmStepTimer.restart();
        }
    }

    Timer {
        id: prewarmStartTimer
        interval: 1800
        running: true
        repeat: false
        onTriggered: root._prewarmNext()
    }

    Timer {
        id: prewarmStepTimer
        interval: Theme.reduceMotion ? 220 : 80
        repeat: false
        onTriggered: root._prewarmNext()
    }

    Process {
        id: settingsWriter
        property string payload: ""
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "sh", root.settingsPath, payload]
    }

    Process {
        id: paishEncoder
        property string jsonPayload: "{}"
        property bool copyOnFinish: false
        command: ["python3", root.paishScript, "encode", "--json", jsonPayload]
        stdout: StdioCollector {
            onStreamFinished: {
                const code = (this.text || "").trim();
                if (code.indexOf("paish:") === 0) {
                    stateObj.currentShareCode = code;
                    if (paishEncoder.copyOnFinish) {
                        paishEncoder.copyOnFinish = false;
                        FileService.copyToClipboard(code);
                        stateObj.shareCodeCopied(code);
                    }
                } else {
                    paishEncoder.copyOnFinish = false;
                }
            }
        }
    }

    Process {
        id: paishWriter
        property string targetPath: ""
        property string profileName: "default"
        property string jsonPayload: "{}"
        command: ["python3", root.paishScript, "encode", "--json", jsonPayload, "--out", targetPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const code = (this.text || "").trim();
                if (code.indexOf("paish:") === 0) {
                    stateObj.currentShareCode = code;
                    stateObj.lastProfileStatus = "Saved " + paishWriter.profileName + ".paish (" + code.length + "B)";
                    stateObj.lastProfileOk = true;
                } else {
                    stateObj.lastProfileStatus = "Failed to save " + paishWriter.profileName + ".paish";
                    stateObj.lastProfileOk = false;
                }
            }
        }
        onExited: stateObj.refreshProfiles()
    }

    Process {
        id: paishReader
        property string targetPath: ""
        property bool silentOnMissing: false
        property string profileName: "default"
        command: ["python3", root.paishScript, "decode-file", targetPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (this.text || "").trim();
                if (raw === "") {
                    if (!paishReader.silentOnMissing) {
                        stateObj.lastProfileStatus = "Invalid or missing " + paishReader.profileName + ".paish";
                        stateObj.lastProfileOk = false;
                    }
                    return;
                }
                let decoded = null;
                try {
                    decoded = JSON.parse(raw);
                } catch (e) {
                    decoded = null;
                }
                if (!decoded || (decoded.version !== 2 && decoded.version !== 3 && decoded.version !== 4)) {
                    if (!paishReader.silentOnMissing) {
                        stateObj.lastProfileStatus = "Invalid .paish format in " + paishReader.profileName + ".paish";
                        stateObj.lastProfileOk = false;
                    }
                    return;
                }
                stateObj.applyDecodedTheme(decoded, paishReader.profileName);
                if (!paishReader.silentOnMissing) {
                    stateObj.lastProfileStatus = "Loaded " + paishReader.profileName + ".paish";
                    stateObj.lastProfileOk = true;
                }
            }
        }
    }

    Process {
        id: paishImporter
        property string codeInput: ""
        command: ["python3", root.paishScript, "decode", codeInput]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (this.text || "").trim();
                let decoded = null;
                try {
                    if (raw !== "") decoded = JSON.parse(raw);
                } catch (e) {
                    decoded = null;
                }
                if (!decoded || (decoded.version !== 2 && decoded.version !== 3 && decoded.version !== 4)) {
                    stateObj.themeCodeImported(false, "Invalid paish: code or format");
                    return;
                }
                const targetName = stateObj.sanitizeProfileName(decoded.profileName || decoded.presetName || "imported");
                stateObj.applyDecodedTheme(decoded, targetName);
                stateObj.saveProfile(targetName);
                stateObj.themeCodeImported(true, "Applied paish: code & synced!");
            }
        }
    }

    Timer {
        id: shareCodeTimer
        interval: 380
        repeat: false
        onTriggered: {
            const payload = Theme.buildPaishState(stateObj, CompositorService, stateObj.activeProfile, CursorService, LockService);
            paishEncoder.copyOnFinish = false;
            paishEncoder.jsonPayload = JSON.stringify(payload);
            paishEncoder.running = false;
            paishEncoder.running = true;
        }
    }

    Process {
        id: paishListProc
        command: ["sh", "-c", "ls -1 \"$1\"/*.paish 2>/dev/null | xargs -r -n1 basename | sed 's/\\.paish$//' || true", "sh", root.profileDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").split("\n").map(s => s.trim()).filter(s => s.length > 0);
                stateObj.availableProfiles = lines;
                if (stateObj.activeProfile !== "" && lines.indexOf(stateObj.activeProfile) === -1) {
                    stateObj.activeProfile = "";
                    stateObj.saveSettings();
                }
            }
        }
    }

    Process {
        id: wallpaperColorProc
        property string requestedPath: ""
        property string requestedMode: "Solid"
        property int requestSeq: 0
        property bool animateOnApply: true
        property string errBuf: ""
        command: ["python3", root.wallpaperColorScript, requestedPath, "--mode", requestedMode.toLowerCase()]
        stdout: StdioCollector {
            onStreamFinished: {
                const seq = wallpaperColorProc.requestSeq;
                const reqPath = wallpaperColorProc.requestedPath;
                const reqMode = wallpaperColorProc.requestedMode;
                const anim = wallpaperColorProc.animateOnApply;
                if (seq !== stateObj._wpColorSeq || !Theme.wallpaperColorEnabled || Theme.wallpapersDisabled) {
                    if (seq === stateObj._wpColorSeq) Theme.wallpaperColorBusy = false;
                    return;
                }
                const raw = (this.text || "").trim();
                let parsed = null;
                try {
                    if (raw !== "") parsed = JSON.parse(raw);
                } catch (e) {
                    parsed = null;
                }
                if (!parsed || !parsed.ok) {
                    Theme.wallpaperColorBusy = false;
                    if (raw !== "" || wallpaperColorProc.errBuf !== "") {
                        console.warn("[paithosh] Wallpaper color analysis failed:", raw || wallpaperColorProc.errBuf);
                    }
                    return;
                }
                stateObj.cacheWallpaperColors(reqPath, reqMode, parsed);
                const effectiveWpMode = (Theme.wallpaperColorMode === "Gradient" && !Theme.reduceMotion) ? "Gradient" : "Solid";
                if (reqPath === bgLayer.currentWallpaperPath && reqMode === effectiveWpMode) {
                    Theme.applyWallpaperPalette(parsed, reqPath, anim);
                } else {
                    Theme.wallpaperColorBusy = false;
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: wallpaperColorProc.errBuf = (this.text || "").trim()
        }
        onExited: function(code) {
            if (code !== 0 && !wallpaperColorProc.running && wallpaperColorProc.requestSeq === stateObj._wpColorSeq) {
                Theme.wallpaperColorBusy = false;
            }
        }
    }

    Timer {
        id: saveSettingsTimer
        interval: 320
        repeat: false
        onTriggered: stateObj.writeSettingsNow()
    }

    Timer {
        id: toolkitThemeSyncTimer
        interval: 180
        repeat: false
        onTriggered: {
            const payload = toolkitThemeSyncProc._pendingJson;
            if (!payload || payload === toolkitThemeSyncProc._lastAppliedJson) return;
            if (toolkitThemeSyncProc.running) {
                toolkitThemeSyncProc._queuedJson = payload;
                return;
            }
            toolkitThemeSyncProc._inFlightJson = payload;
            toolkitThemeSyncProc.errBuf = "";
            toolkitThemeSyncProc.command = ["python3", root.themeSyncScript, "--json", payload];
            toolkitThemeSyncProc.running = true;
        }
    }

    Process {
        id: toolkitThemeSyncProc
        property string _lastAppliedJson: ""
        property string _pendingJson: ""
        property string _inFlightJson: ""
        property string _queuedJson: ""
        property string errBuf: ""
        stderr: StdioCollector {
            onStreamFinished: toolkitThemeSyncProc.errBuf = (this.text || "").trim()
        }
        onExited: (code) => {
            if (code === 0) {
                toolkitThemeSyncProc._lastAppliedJson = toolkitThemeSyncProc._inFlightJson;
            } else if (toolkitThemeSyncProc.errBuf !== "") {
                console.warn("[paithosh] Toolkit theme sync failed:", toolkitThemeSyncProc.errBuf);
            }
            if (toolkitThemeSyncProc._queuedJson !== "") {
                const nxt = toolkitThemeSyncProc._queuedJson;
                toolkitThemeSyncProc._queuedJson = "";
                toolkitThemeSyncProc._pendingJson = nxt;
                Qt.callLater(() => toolkitThemeSyncTimer.restart());
            }
        }
    }

    Timer {
        id: autoForkSaveTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (stateObj._autoForkTarget !== "" && stateObj.activeProfile === stateObj._autoForkTarget) {
                stateObj.saveProfile(stateObj._autoForkTarget);
            }
            stateObj._autoForkTarget = "";
        }
    }

    Connections {
        target: Theme
        function onActivePresetChanged() {
            if (!stateObj._applyingExternalState) stateObj.saveSettings();
        }
        function onPresetApplied(name) {
            if (!stateObj._applyingExternalState && stateObj.settingsLoaded) {
                stateObj.activeProfile = "";
                stateObj.lastProfileStatus = "";
                CompositorService.applyThemePreset(stateObj.compositorKeyForPreset(name));
                stateObj.themeImportSeq += 1;
                stateObj.saveSettings();
                stateObj.syncHyprThemeColors();
            }
        }
        function onThemeColorsChanged() {
            if (!stateObj._applyingExternalState && stateObj.settingsLoaded) {
                stateObj.saveSettings();
                stateObj.syncHyprThemeColors();
            }
        }
        function onMasterRatioChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onPreserveSplitChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onShadowRangeChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onGooeyEnabledChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onSpeedMultiplierChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
    }

    Connections {
        target: bgLayer
        function onCurrentIndexChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onCurrentWallpaperPathChanged() {
            if (bgLayer.currentWallpaperPath !== "") {
                reloadState.lastWallpaperPath = bgLayer.currentWallpaperPath;
            }
            if (!stateObj._applyingExternalState) stateObj.saveSettings();
            if (stateObj.settingsLoaded && Theme.wallpaperColorEnabled && !Theme.wallpapersDisabled && bgLayer.currentWallpaperPath !== "") {
                stateObj.syncWallpaperColors(true, false);
            }
        }
        function onTransitionModeChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
    }

    QtObject {
        id: stateObj
        function compositorKeyForPreset(presetName) {
            const meta = Theme.presetMeta(presetName);
            return meta ? meta.compositorKey : "oled";
        }

        property var _wpColorCache: ({})
        property var _wpColorCacheOrder: []
        property int _wpColorSeq: 0

        function cacheWallpaperColors(path, mode, parsed) {
            const key = String(path || "") + "|" + String(mode || "Solid");
            const next = Object.assign({}, _wpColorCache);
            if (next[key] === undefined) {
                const order = _wpColorCacheOrder.slice();
                order.push(key);
                if (order.length > 32) {
                    const drop = order.shift();
                    delete next[drop];
                }
                _wpColorCacheOrder = order;
            }
            next[key] = parsed;
            _wpColorCache = next;
        }

        function syncWallpaperColors(animate, force) {
            if (!Theme.wallpaperColorEnabled || Theme.wallpapersDisabled) return;
            const path = bgLayer.currentWallpaperPath;
            if (!path || path === "") return;
            const mode = (Theme.wallpaperColorMode === "Gradient" && !Theme.reduceMotion) ? "Gradient" : "Solid";
            const key = path + "|" + mode;
            const anim = (animate !== false);

            if (!force && _wpColorCache[key] !== undefined) {
                _wpColorSeq += 1;
                Theme.applyWallpaperPalette(_wpColorCache[key], path, anim);
                return;
            }

            const nextSeq = ++_wpColorSeq;
            Theme.wallpaperColorBusy = true;
            wallpaperColorProc.running = false;
            wallpaperColorProc.errBuf = "";
            wallpaperColorProc.requestedPath = path;
            wallpaperColorProc.requestedMode = mode;
            wallpaperColorProc.animateOnApply = anim;
            wallpaperColorProc.requestSeq = nextSeq;
            wallpaperColorProc.running = true;
        }

        function setWallpapersDisabled(disabled) {
            const next = Boolean(disabled);
            if (Theme.wallpapersDisabled === next) return;
            reloadState.lastWallpapersDisabled = next;
            if (next) {
                _wpColorSeq += 1;
                wallpaperColorProc.running = false;
                Theme.wallpaperColorBusy = false;
            }
            Theme.setWallpapersDisabled(next);
            syncHyprThemeColors();
            if (!_applyingExternalState) markAppearanceCustomized();
            saveSettings();
        }

        function setReduceMotion(enabled) {
            const next = Boolean(enabled);
            if (Theme.reduceMotion === next) return;
            Theme.reduceMotion = next;
            reloadState.lastReduceMotion = next;
            CompositorService.applyReduceMotion(next);
            if (Theme.wallpaperColorEnabled && !Theme.wallpapersDisabled && Theme.wallpaperColorMode === "Gradient") {
                syncWallpaperColors(false, false);
            } else {
                syncHyprThemeColors();
            }
            saveSettings();
        }

        function setWallpaperColorEnabled(enabled) {
            const next = Boolean(enabled) && !Theme.wallpapersDisabled;
            if (Theme.wallpaperColorEnabled === next) return;
            if (!next) {
                _wpColorSeq += 1;
                wallpaperColorProc.running = false;
                Theme.wallpaperColorBusy = false;
            }
            const hasWp = Boolean(bgLayer.currentWallpaperPath && bgLayer.currentWallpaperPath !== "");
            Theme.setWallpaperColorEnabled(next, next && hasWp);
            if (Theme.wallpaperColorEnabled && !Theme.wallpapersDisabled) {
                syncWallpaperColors(true, false);
            } else {
                syncHyprThemeColors();
            }
            if (!_applyingExternalState) markAppearanceCustomized();
            saveSettings();
        }

        function setWallpaperColorMode(mode) {
            if (Theme.reduceMotion && String(mode || "").trim().toLowerCase() === "gradient") return;
            const next = (String(mode || "").trim().toLowerCase() === "gradient") ? "Gradient" : "Solid";
            if (Theme.wallpaperColorMode === next) return;
            Theme.setWallpaperColorMode(next);
            if (Theme.wallpaperColorEnabled && !Theme.wallpapersDisabled) {
                syncWallpaperColors(true, false);
            }
            if (!_applyingExternalState) markAppearanceCustomized();
            saveSettings();
        }

        function selectPreset(name) {
            if (Theme.wallpaperColorEnabled) return false;
            const meta = Theme.presetMeta(name);
            if (!meta) return false;
            autoForkSaveTimer.stop();
            _autoForkTarget = "";
            _applyingExternalState = true;
            Theme.applyPreset(name);
            globalSurfaceTheme = meta.surfaceTheme;
            activeProfile = "";
            lastProfileStatus = "";
            CompositorService.applyThemePreset(meta.compositorKey);
            _applyingExternalState = false;
            themeImportSeq += 1;
            saveSettings();
            syncHyprThemeColors();
            return true;
        }

        function syncHyprThemeColors() {
            const t = Theme.exportTargetRenderColors();
            CompositorService.syncThemeColors({
                pillBg: t.pillBg,
                surfaceBg: t.surfaceBg,
                surfaceRaised: t.surfaceRaised,
                text: t.text,
                accent: t.accent,
                accent2: t.accent2,
                borderColor: t.borderColor,
                borderAlpha: t.borderAlpha,
                accentGradientEnabled: Theme.effectiveAccentGradient,
                gradientAngle: t.gradientAngle,
                activeBorderHighlight: activeBorderHighlight
            });
            const tgt = Theme._targetPalette;
            const toolkitJson = JSON.stringify({
                pillBg: t.pillBg,
                surfaceBg: t.surfaceBg,
                surfaceRaised: t.surfaceRaised,
                text: t.text,
                borderColor: t.borderColor,
                borderAlpha: t.borderAlpha,
                cardAlpha: tgt ? tgt.cardAlpha : Theme._liveCardAlpha,
                hoverAlpha: tgt ? tgt.hoverAlpha : Theme._liveHoverAlpha,
                accent: t.accent,
                accent2: t.accent2,
                accentFg: t.accentFg,
                ok: Theme.colorToHex(Theme.ok),
                info: Theme.colorToHex(Theme.info),
                warn: Theme.colorToHex(Theme.warn),
                danger: Theme.colorToHex(Theme.danger),
                dangerText: Theme.colorToHex(Theme.dangerText)
            });
            if (toolkitJson !== toolkitThemeSyncProc._lastAppliedJson || toolkitThemeSyncProc.running) {
                toolkitThemeSyncProc._pendingJson = toolkitJson;
                toolkitThemeSyncTimer.restart();
            }
        }

        function setThemeColor(slot, hex) {
            if (Theme.wallpaperColorEnabled) return false;
            if (!Theme.setPaletteColor(slot, hex)) return false;
            if (!_applyingExternalState) markAppearanceCustomized();
            return true;
        }

        function clearThemeColorOverride(slot) {
            if (Theme.wallpaperColorEnabled) return false;
            if (!Theme.clearPaletteOverride(slot)) return false;
            if (!_applyingExternalState) markAppearanceCustomized();
            return true;
        }

        function setThemeGradients(shellOn, surfaceOn, accentOn) {
            if (Theme.wallpaperColorEnabled) return;
            Theme.setGradientFlags(shellOn, surfaceOn, accentOn);
            if (!_applyingExternalState) markAppearanceCustomized();
        }

        function setThemeGradientAngle(deg) {
            if (Theme.wallpaperColorEnabled) return;
            Theme.setGradientAngle(deg);
            if (!_applyingExternalState) markAppearanceCustomized();
        }

        function applyGlobalSurfaceTheme(mode) {
            if (Theme.wallpaperColorEnabled) return;
            Theme.applySurfaceTheme(mode);
            globalSurfaceTheme = Theme.surfaceTheme;
            if (!_applyingExternalState) markAppearanceCustomized();
        }

        function nextLocalThemeName(basePreset) {
            const slug = String(basePreset || "theme").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "theme";
            const base = slug + "-custom";
            const list = availableProfiles || [];
            if (list.indexOf(base) === -1) return base;
            let idx = 2;
            while (list.indexOf(base + "-" + idx) !== -1) idx++;
            return base + "-" + idx;
        }

        function notifyStatus(message) {
            kdeText = message;
            kdeSlotOpen = true;
            statusHideTimer.restart();
            const lower = (message || "").toLowerCase();
            if (lower.indexOf("screenshot") !== -1 || lower.indexOf("region") !== -1 || lower.indexOf("window") !== -1) {
                SoundService.playShutter();
            } else {
                SoundService.playNotify();
            }
        }

        function markAppearanceCustomized() {
            if (!settingsLoaded || _applyingExternalState) return;
            if (activeProfile === "") {
                const prof = nextLocalThemeName(Theme.activePreset);
                activeProfile = prof;
                _autoForkTarget = prof;
                lastProfileStatus = "Auto-created " + prof + ".paish";
                lastProfileOk = true;
                autoForkSaveTimer.restart();
                notifyStatus("Local theme: " + prof + ".paish");
            } else if (_autoForkTarget === activeProfile && autoForkSaveTimer.running) {
                autoForkSaveTimer.restart();
            }
            shareCodeTimer.restart();
        }

        function applyCustomAccent(h, s, v) {
            if (Theme.wallpaperColorEnabled) return;
            Theme.applyAccentHsv(h, s, v);
            if (!_applyingExternalState) {
                markAppearanceCustomized();
            }
            saveSettings();
        }

        property var activeScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        property string openPopover: "" // "" | "launcher" | "dashboard" | "search" | "overview"
        property string islandApp: "" // "" | "settings" | "files" | "music" | "picker" | "portal" | "appchooser"
        property string detachedApp: "" // "" | "settings" | "files" | "music" | "picker"
        property string dashboardTab: "mission" // "mission" | "tasks" | "kde" | "power"
        property string settingsPage: "home"
        property string settingsSpotlight: ""
        property string pickerMode: "upload"
        property string pickerResultPath: ""
        property var onPickerSelected: null
        property string pickerTitle: ""
        property string pickerAcceptLabel: ""
        property bool pickerMultiple: false
        property bool pickerDirectory: false
        property string pickerInitialFolder: ""
        property string pickerInitialName: ""
        property string pickerAppId: ""
        property var pickerFilters: []
        property int pickerRequestId: 0
        property string pickerReturnSettingsPage: ""
        property bool pickerReturnDetached: false
        property string appChooserResultPath: ""
        property string appChooserUri: ""
        property string appChooserScheme: ""
        property string appChooserContentType: ""
        property string appChooserFilename: ""
        property string appChooserCallerApp: ""
        property bool appChooserNoMatch: false
        property string appChooserLastChoice: ""
        property var appChooserApps: []
        property int appChooserRequestId: 0
        property bool manualHideBar: false
        property bool hideBarFullscreen: true
        property bool autoHideOnOverlap: true
        property bool dodgeCursor: false
        property bool recordAudio: true
        property bool recordMic: false
        property string recordPreset: "standard"
        property string recordResolution: "native"
        property int recordFps: 30
        property string recordCodec: "auto"
        property string recordSaveDir: ""
        property bool inputIndicatorEnabled: true
        property bool capsLockIndicatorEnabled: true
        property bool fcitxIndicatorEnabled: true
        onInputIndicatorEnabledChanged: {
            InputIndicatorService.enabled = inputIndicatorEnabled;
            if (!inputIndicatorEnabled) inputSlotOpen = false;
            if (!stateObj._applyingExternalState) saveSettings();
        }
        onCapsLockIndicatorEnabledChanged: {
            InputIndicatorService.capsLockEnabled = capsLockIndicatorEnabled;
            if (!stateObj._applyingExternalState) saveSettings();
        }
        onFcitxIndicatorEnabledChanged: {
            InputIndicatorService.fcitxEnabled = fcitxIndicatorEnabled;
            if (!stateObj._applyingExternalState) saveSettings();
        }
        onRecordAudioChanged: {
            ScreenRecordService.recordAudio = recordAudio;
            if (!stateObj._applyingExternalState) saveSettings();
        }
        onRecordMicChanged: {
            ScreenRecordService.recordMic = recordMic;
            if (!stateObj._applyingExternalState) saveSettings();
        }
        onRecordPresetChanged: {
            ScreenRecordService.preset = recordPreset;
            if (!stateObj._applyingExternalState) saveSettings();
        }
        onRecordResolutionChanged: {
            ScreenRecordService.resolution = recordResolution;
            if (!stateObj._applyingExternalState) saveSettings();
        }
        onRecordFpsChanged: {
            ScreenRecordService.fps = recordFps;
            if (!stateObj._applyingExternalState) saveSettings();
        }
        onRecordCodecChanged: {
            ScreenRecordService.codec = recordCodec;
            if (!stateObj._applyingExternalState) saveSettings();
        }
        onRecordSaveDirChanged: {
            ScreenRecordService.saveDir = recordSaveDir;
            if (!stateObj._applyingExternalState) saveSettings();
        }
        property string islandCornerRadius: "26px (Default)"
        property string barPosition: "top" // "top" | "bottom"
        property bool activeIslandHidden: false
        property real activeIslandEdgeOffset: Theme.topOffsetRest
        property bool topEdgeOffset: true
        property bool activeBorderHighlight: true
        property string globalSurfaceTheme: "OLED Pure"
        property bool superPeekBar: false
        property bool superPeekWasHidden: false
        property bool superHeld: false
        property bool superUsedWithIsland: false
        property double lastSuperComboMs: 0
        property bool settingsLoaded: false
        property bool _applyingExternalState: false
        property string activeProfile: ""
        property string _autoForkTarget: ""
        property var availableProfiles: []
        property string lastProfileStatus: ""
        property bool lastProfileOk: true
        property int themeImportSeq: 0
        property string currentShareCode: ""
        property string reloadPhase: "idle" // "idle" | "collapsing" | "exiting" | "committing" | "revealing" | "clearing"
        property bool reloadInstantOpaque: false
        readonly property bool reloadOverlayActive: reloadPhase === "exiting" || reloadPhase === "committing" || reloadPhase === "revealing" || reloadPhase === "clearing"
        property bool reloadSlotOpen: false
        property string reloadSlotText: ""
        property string reloadSlotState: "ok" // "loading" | "ok" | "error"
        property bool _handledReloadEntrance: false
        property bool _pendingReloadHyprland: false
        property bool _pendingReloadHard: false
        property bool _pendingReloadRestart: false
        property string _pendingReloadReason: "Config Reloaded"

        property string sessionAction: "" // "" | "logout" | "reboot" | "shutdown"
        property string sessionPhase: "idle" // "idle" | "fading" | "executing" | "cancelling"
        property bool sessionDryRun: false
        property int sessionGraceMs: 650
        readonly property bool sessionTransitionActive: sessionPhase !== "idle"

        function requestSessionAction(action, dryRun) {
            if (sessionPhase !== "idle" || reloadPhase !== "idle") return;
            const raw = String(action || "").trim().toLowerCase();
            let norm = "";
            if (raw === "logout" || raw === "exit") norm = "logout";
            else if (raw === "reboot" || raw === "restart") norm = "reboot";
            else if (raw === "shutdown" || raw === "poweroff") norm = "shutdown";
            if (norm === "") return;

            closePopovers();
            closeModal();
            if (islandApp !== "") collapseIslandApp();
            if (detachedApp !== "") detachedApp = "";
            SoundService.stopLockAmbient();
            if (norm === "logout") SoundService.playSessionLogout();
            else if (norm === "reboot") SoundService.playSessionRestart();
            else if (norm === "shutdown") SoundService.playSessionShutdown();

            const speed = Math.max(0.5, Theme.speedMultiplier || 1.0);
            sessionGraceMs = Math.max(380, Math.round((norm === "shutdown" ? 720 : 620) / speed));
            sessionAction = norm;
            sessionDryRun = Boolean(dryRun);
            sessionPhase = "fading";
            sessionCleanupTimer.stop();
            sessionCommitTimer.stop();
            sessionExecuteTimer.interval = sessionGraceMs;
            sessionExecuteTimer.restart();
        }

        function cancelSessionAction() {
            if (sessionPhase !== "fading") return;
            sessionExecuteTimer.stop();
            sessionCommitTimer.stop();
            sessionPhase = "cancelling";
            const speed = Math.max(0.5, Theme.speedMultiplier || 1.0);
            sessionCleanupTimer.interval = Math.max(160, Math.round(300 / speed));
            sessionCleanupTimer.restart();
            showReloadResult(true, "Action Cancelled");
        }

        function showReloadResult(ok, message) {
            reloadSlotState = ok ? "ok" : "error";
            reloadSlotText = message || (ok ? "Config Reloaded" : "Reload Failed");
            reloadSlotOpen = true;
            reloadHideTimer.interval = ok ? 1900 : 3200;
            reloadHideTimer.restart();
            SoundService.playNotify();
        }

        function requestShellReload(opts) {
            if (reloadPhase !== "idle") return;
            const cfg = opts || ({});
            const hadExpandedSurface = (islandApp !== "" || openPopover !== "" || modalKind !== "" || detachedApp !== "");

            _pendingReloadHyprland = cfg.reloadHyprland !== false;
            _pendingReloadHard = Boolean(cfg.hard);
            _pendingReloadRestart = Boolean(cfg.restartProcess);
            _pendingReloadReason = (typeof cfg.reason === "string" && cfg.reason !== "")
                ? cfg.reason
                : (_pendingReloadHyprland ? "Shell Reloaded" : "Config Reloaded");

            closePopovers();
            closeModal();
            if (islandApp !== "") collapseIslandApp();
            if (detachedApp !== "") detachedApp = "";

            reloadState.lastWallpaperPath = bgLayer.currentWallpaperPath || reloadState.lastWallpaperPath;
            reloadState.pendingEntrance = true;
            reloadState.pendingBgReveal = true;
            reloadState.pendingOverlayReveal = true;
            reloadState.reloadReason = _pendingReloadReason;

            reloadHideTimer.stop();
            reloadSlotState = "loading";
            reloadSlotText = "Reloading…";
            reloadSlotOpen = true;
            reloadPhase = "collapsing";

            const speed = Math.max(0.5, Theme.speedMultiplier || 1.0);
            reloadCollapseTimer.interval = Math.max(90, Math.round((hadExpandedSurface ? 200 : 130) / speed));
            reloadCollapseTimer.restart();
            reloadSafetyTimer.restart();
        }

        function _executeShellReloadNow() {
            const shellDir = Quickshell.shellDir;
            if (_pendingReloadRestart || typeof Quickshell.reload !== "function") {
                Quickshell.execDetached([
                    "setsid", "-f", "sh", "-c",
                    "shell_dir=\"$1\"; " +
                    "pkill -x qs 2>/dev/null || true; " +
                    "pkill -x quickshell 2>/dev/null || true; " +
                    "i=0; while [ $i -lt 30 ] && (pgrep -x qs >/dev/null 2>&1 || pgrep -x quickshell >/dev/null 2>&1); do " +
                    "  sleep 0.1; i=$((i + 1)); " +
                    "done; " +
                    "pkill -9 -x qs 2>/dev/null || true; " +
                    "pkill -9 -x quickshell 2>/dev/null || true; " +
                    "if command -v qs >/dev/null 2>&1; then " +
                    "  exec env QS_NO_RELOAD_POPUP=1 qs -d -p \"$shell_dir\" </dev/null >/dev/null 2>&1; " +
                    "else " +
                    "  exec env QS_NO_RELOAD_POPUP=1 quickshell -d -p \"$shell_dir\" </dev/null >/dev/null 2>&1; " +
                    "fi",
                    "_",
                    shellDir
                ]);
                return;
            }
            Quickshell.reload(_pendingReloadHard);
        }

        signal shareCodeCopied(string code)
        signal themeCodeImported(bool ok, string message)

        function sanitizeProfileName(name) {
            const clean = String(name || "default").trim().toLowerCase().replace(/[^a-z0-9._-]/g, "_").replace(/^_+|_+$/g, "");
            return clean !== "" ? clean.slice(0, 31) : "default";
        }

        function refreshShareCode() {
            shareCodeTimer.restart();
        }

        function copyShareCode() {
            const payload = Theme.buildPaishState(stateObj, CompositorService, activeProfile, CursorService, LockService);
            paishEncoder.copyOnFinish = true;
            paishEncoder.jsonPayload = JSON.stringify(payload);
            paishEncoder.running = false;
            paishEncoder.running = true;
        }

        function applyDecodedTheme(d, profileName) {
            if (!d) return false;
            autoForkSaveTimer.stop();
            _autoForkTarget = "";
            const prevWpEnabled = Theme.wallpaperColorEnabled;
            const wpDisabled = Boolean(d.wallpapersDisabled);
            const wpOn = !wpDisabled && Boolean(d.wallpaperColorEnabled);
            _applyingExternalState = true;
            activeProfile = profileName ? sanitizeProfileName(profileName) : "";
            reloadState.lastWallpapersDisabled = wpDisabled;
            Theme.wallpapersDisabled = wpDisabled;
            Theme.applyPreset(d.presetName, wpOn);
            globalSurfaceTheme = d.globalSurfaceTheme || "OLED Pure";
            if (!wpOn) Theme.applySurfaceTheme(globalSurfaceTheme);
            else Theme.surfaceTheme = globalSurfaceTheme;
            Theme.applyPaletteState(d, wpOn);
            if (!wpOn && prevWpEnabled) {
                Theme.rebuildPalette(false, true);
            }
            Theme.masterRatio = d.masterRatio;
            Theme.preserveSplit = d.preserveSplit;
            Theme.shadowRange = d.shadowRange;
            if (typeof d.gooeyEnabled === "boolean") Theme.gooeyEnabled = d.gooeyEnabled;
            if (typeof d.speedMultiplier === "number") Theme.speedMultiplier = d.speedMultiplier;

            islandCornerRadius = d.islandCornerRadius;
            topEdgeOffset = d.topEdgeOffset;
            hideBarFullscreen = d.hideBarFullscreen;
            autoHideOnOverlap = d.autoHideOnOverlap;
            if (typeof d.dodgeCursor === "boolean") dodgeCursor = d.dodgeCursor;
            activeBorderHighlight = d.activeBorderHighlight;

            CompositorService.setActiveThemePresetName(compositorKeyForPreset(d.presetName));
            CompositorService.setGapsAndBorder(d.gapsIn, d.gapsOut, d.borderSize);
            CompositorService.setLayout(d.layoutName);
            CompositorService.setDecoration(d.cornerRounding, d.shadowEnabled, d.inactiveOpacity);
            CompositorService.setAnimationsEnabled(d.animationsEnabled);
            CompositorService.setSpringCurve(d.springStiffness, d.springDamping);
            CompositorService.setBlurConfig(d.blurEnabled, d.blurSize, d.blurPasses, d.blurVibrancy);

            if (d.barPosition !== null && d.barPosition !== undefined) barPosition = d.barPosition;

            if (d.cursorStyle !== null) CursorService.style = CursorService.normalizeStyle(d.cursorStyle);
            if (d.cursorSize !== null) CursorService.size = Math.max(16, Math.min(64, Math.round(d.cursorSize)));
            if (d.cursorColorMode !== null) CursorService.colorMode = CursorService.normalizeColorMode(d.cursorColorMode);
            if (d.cursorFixedColor !== null) CursorService.fixedColor = CursorService.normalizeHex(d.cursorFixedColor);
            if (d.cursorMotionBlur !== null) CursorService.motionBlur = Boolean(d.cursorMotionBlur);

            if (d.lockEffectPreset !== null && d.lockEffectPreset !== undefined) LockService.effectPreset = d.lockEffectPreset;
            if (d.lockAmbientSound !== null && d.lockAmbientSound !== undefined) LockService.ambientSound = d.lockAmbientSound;
            if (d.lockSilentMode !== null && d.lockSilentMode !== undefined) LockService.silentMode = Boolean(d.lockSilentMode);
            if (d.lockSfxEnabled !== null && d.lockSfxEnabled !== undefined) LockService.sfxEnabled = Boolean(d.lockSfxEnabled);
            if (d.lockShowNotifications !== null && d.lockShowNotifications !== undefined) LockService.showNotifications = Boolean(d.lockShowNotifications);
            if (d.lockHideNotifContent !== null && d.lockHideNotifContent !== undefined) LockService.hideNotifContent = Boolean(d.lockHideNotifContent);
            if (d.lockShowMedia !== null && d.lockShowMedia !== undefined) LockService.showMedia = Boolean(d.lockShowMedia);
            if (d.lockShowSystemAlerts !== null && d.lockShowSystemAlerts !== undefined) LockService.showSystemAlerts = Boolean(d.lockShowSystemAlerts);
            if (d.lockEffectIntensity !== null && d.lockEffectIntensity !== undefined) LockService.effectIntensity = d.lockEffectIntensity;
            if (d.lockAmbientVolume !== null && d.lockAmbientVolume !== undefined) LockService.ambientVolume = d.lockAmbientVolume;
            if (d.lockDimOpacity !== null && d.lockDimOpacity !== undefined) LockService.dimOpacity = d.lockDimOpacity;

            _applyingExternalState = false;
            themeImportSeq += 1;
            if (Theme.wallpaperColorEnabled && !Theme.wallpapersDisabled) {
                syncWallpaperColors(true, false);
            }
            saveSettings();
            syncHyprThemeColors();
            CursorService.applyNow(true);
            return true;
        }

        function importThemeCode(input) {
            const trimmed = String(input || "").trim();
            if (trimmed.indexOf("paish:") !== 0) {
                themeCodeImported(false, "Invalid paish: code or format");
                return false;
            }
            paishImporter.codeInput = trimmed;
            paishImporter.running = false;
            paishImporter.running = true;
            return true;
        }

        function saveProfile(name) {
            const prof = sanitizeProfileName(name);
            activeProfile = prof;
            const payload = Theme.buildPaishState(stateObj, CompositorService, prof, CursorService, LockService);
            paishWriter.profileName = prof;
            paishWriter.targetPath = root.profileDir + "/" + prof + ".paish";
            paishWriter.jsonPayload = JSON.stringify(payload);
            paishWriter.running = false;
            paishWriter.running = true;
            return true;
        }

        function loadProfile(name, silent) {
            autoForkSaveTimer.stop();
            _autoForkTarget = "";
            const prof = sanitizeProfileName(name);
            paishReader.profileName = prof;
            paishReader.silentOnMissing = !!silent;
            paishReader.targetPath = root.profileDir + "/" + prof + ".paish";
            paishReader.running = false;
            paishReader.running = true;
        }

        function refreshProfiles() {
            paishListProc.running = false;
            paishListProc.running = true;
        }

        function applyIslandMetrics() {
            Theme.islandRadius = islandCornerRadius.indexOf("12") !== -1 ? 12 : (islandCornerRadius.indexOf("18") !== -1 ? 18 : 26);
            Theme.topOffsetRest = topEdgeOffset ? 12 : 4;
            Theme.topOffsetHover = topEdgeOffset ? 16 : 8;
        }

        function saveSettings() {
            if (!settingsLoaded) return;
            saveSettingsTimer.restart();
            shareCodeTimer.restart();
        }

        function writeSettingsNow() {
            if (!settingsLoaded) return;
            const pal = Theme.exportPaletteState();
            const data = {
                hideBarFullscreen: hideBarFullscreen,
                autoHideOnOverlap: autoHideOnOverlap,
                dodgeCursor: dodgeCursor,
                recordAudio: recordAudio,
                recordMic: recordMic,
                recordPreset: recordPreset,
                recordResolution: recordResolution,
                recordFps: recordFps,
                recordCodec: recordCodec,
                recordSaveDir: recordSaveDir,
                inputIndicatorEnabled: inputIndicatorEnabled,
                capsLockIndicatorEnabled: capsLockIndicatorEnabled,
                fcitxIndicatorEnabled: fcitxIndicatorEnabled,
                islandCornerRadius: islandCornerRadius,
                barPosition: barPosition,
                topEdgeOffset: topEdgeOffset,
                activeBorderHighlight: activeBorderHighlight,
                globalSurfaceTheme: globalSurfaceTheme,
                themePreset: Theme.activePreset,
                activeProfile: activeProfile,
                masterRatio: Theme.masterRatio,
                preserveSplit: Theme.preserveSplit,
                shadowRange: Theme.shadowRange,
                gooeyEnabled: Theme.gooeyEnabled,
                reduceMotion: Theme.reduceMotion,
                speedMultiplier: Theme.speedMultiplier,
                transitionMode: bgLayer.transitionMode,
                wallpaperIndex: bgLayer.currentIndex,
                wallpaperPath: bgLayer.currentWallpaperPath,
                lockEffectPreset: LockService.effectPreset,
                lockAmbientSound: LockService.ambientSound,
                lockSilentMode: LockService.silentMode,
                lockSfxEnabled: LockService.sfxEnabled,
                lockShowNotifications: LockService.showNotifications,
                lockHideNotifContent: LockService.hideNotifContent,
                lockShowMedia: LockService.showMedia,
                lockShowSystemAlerts: LockService.showSystemAlerts,
                lockEffectIntensity: LockService.effectIntensity,
                lockAmbientVolume: LockService.ambientVolume,
                lockDimOpacity: LockService.dimOpacity,
                systemSoundEnabled: SoundService.enabled,
                systemSoundVolume: SoundService.volumePct,
                cursorStyle: CursorService.style,
                cursorSize: CursorService.size,
                cursorColorMode: CursorService.colorMode,
                cursorFixedColor: CursorService.fixedColor,
                cursorMotionBlur: CursorService.motionBlur,
                cursorMotionBlurStrength: CursorService.motionBlurStrength,
                cursorMotionBlurThreshold: CursorService.motionBlurThreshold
            };
            for (const k in pal) data[k] = pal[k];
            settingsWriter.payload = JSON.stringify(data, null, 2);
            settingsWriter.running = false;
            settingsWriter.running = true;
        }

        onActiveProfileChanged: saveSettings()

        onHideBarFullscreenChanged: saveSettings()
        onAutoHideOnOverlapChanged: saveSettings()
        onDodgeCursorChanged: saveSettings()
        onIslandCornerRadiusChanged: { applyIslandMetrics(); saveSettings(); }
        onBarPositionChanged: saveSettings()
        onTopEdgeOffsetChanged: { applyIslandMetrics(); saveSettings(); }
        onActiveBorderHighlightChanged: {
            saveSettings();
            if (!stateObj._applyingExternalState && stateObj.settingsLoaded) syncHyprThemeColors();
        }
        onGlobalSurfaceThemeChanged: saveSettings()

        property bool osdOpen: false
        property string osdKind: "vol"
        property int osdValue: 72

        property bool wsSlotOpen: false
        property bool chargeSlotOpen: false
        property bool chargeIsCharging: true
        property string chargeText: "Charging • 84% (65W PD)"

        property bool kdeSlotOpen: false
        property string kdeText: ""

        property bool inputSlotOpen: false
        property string inputSlotKind: "capslock" // "capslock" | "fcitx"
        property string inputSlotLabel: "Caps Lock"
        property string inputSlotBadge: "ON"
        property bool inputSlotActive: false

        property string searchQuery: ""
        property int searchSel: 0
        onSearchQueryChanged: searchSel = 0
        property int previewAlertMode: 0 // 0=auto/off, 1=overheat, 2=low-battery

        property string modalKind: "" // "" | "confirm" | "multi" | "monitor" | "progress"

        function ensureScreen(scr) {
            if (scr) {
                activeScreen = scr;
            } else if (!activeScreen && Quickshell.screens.length > 0) {
                activeScreen = Quickshell.screens[0];
            }
        }

        function cancelPendingPortalPicker() {
            const resPath = pickerResultPath;
            if (!resPath || resPath === "") return;
            pickerResultPath = "";
            Quickshell.execDetached(["sh", "-c", "printf '%s\\n' '{\"status\":\"cancel\"}' > \"$1\"", "_", resPath]);
        }

        function cancelPendingAppChooser() {
            const resPath = appChooserResultPath;
            if (!resPath || resPath === "") return;
            appChooserResultPath = "";
            Quickshell.execDetached(["sh", "-c", "printf '%s\\n' '{\"status\":\"cancel\"}' > \"$1\"", "_", resPath]);
        }

        function _cleanupAppChooserOnLeave(nextApp) {
            if (islandApp === "appchooser" && nextApp !== "appchooser") {
                cancelPendingAppChooser();
                resetAppChooserState();
            }
        }

        function closePopovers() {
            if (islandApp === "picker" && detachedApp !== "picker") {
                cancelPendingPortalPicker();
                resetFilePickerState();
            }
            _cleanupAppChooserOnLeave("");
            openPopover = "";
            searchQuery = "";
            islandApp = "";
        }

        function togglePopover(kind, scr) {
            if (LockService.locked) return;
            clearSuperPeek();
            ensureScreen(scr);
            if (islandApp === "picker" && detachedApp !== "picker") {
                cancelPendingPortalPicker();
                resetFilePickerState();
            }
            _cleanupAppChooserOnLeave("");
            islandApp = "";
            if (openPopover === kind && (!scr || activeScreen === scr)) {
                closePopovers();
            } else {
                openPopover = kind;
                if (kind === "search") searchQuery = "";
            }
        }

        function _openPicker(opts) {
            const o = opts || {};
            const fromSettings = (islandApp === "settings" || detachedApp === "settings");
            const retPage = o.returnSettingsPage !== undefined
                ? String(o.returnSettingsPage)
                : (fromSettings ? (settingsPage !== "" ? settingsPage : "home") : "");
            const wasDetached = (detachedApp === "settings" && islandApp !== "settings");

            cancelPendingPortalPicker();
            resetFilePickerState();
            onPickerSelected = typeof o.onSelected === "function" ? o.onSelected : null;
            pickerMode = o.mode === "download" ? "download" : "upload";
            pickerDirectory = Boolean(o.directory);
            pickerMultiple = Boolean(o.multiple);
            pickerTitle = o.title || (pickerDirectory ? "Select Folder" : "Select File");
            pickerAcceptLabel = o.acceptLabel || (pickerDirectory ? "Select Folder" : "Select File");
            pickerInitialFolder = o.initialFolder || "";
            pickerInitialName = o.initialName || "";
            pickerAppId = o.sourceLabel || "";
            pickerFilters = Array.isArray(o.filters) ? o.filters : [];
            pickerResultPath = "";
            pickerReturnSettingsPage = retPage;
            pickerReturnDetached = wasDetached;
            pickerRequestId += 1;
            showIslandApp("picker", null);
        }

        function openFolderPicker(opts) {
            const o = Object.assign({}, opts || {}, { directory: true });
            _openPicker(o);
        }

        function openFilePicker(opts) {
            const o = Object.assign({}, opts || {}, { directory: false });
            _openPicker(o);
        }

        function openBackupRestorePak(pakPath) {
            if (!pakPath) return;
            settingsPage = "backup";
            showIslandApp("settings", null);
            BackupService.inspectPak(pakPath);
        }

        function openFilesAt(dirPath, selectPath) {
            const target = (dirPath && dirPath !== "") ? dirPath : FileService.homeDir;
            FileService.pendingSelectPath = (selectPath && selectPath !== "") ? selectPath : "";
            FileService.runCmd(["mkdir", "-p", target], () => {
                FileService.lastPath = target;
                showIslandApp("files", null);
            });
        }

        function openWallpaperPicker() {
            openFilePicker({
                title: "Add Wallpaper",
                acceptLabel: "Add & Apply",
                sourceLabel: "Appearance",
                initialFolder: FileService.homeDir + "/Pictures",
                returnSettingsPage: "appearance",
                filters: [{
                    label: "Images (*.png, *.jpg, *.jpeg, *.webp)",
                    patterns: [
                        { kind: 0, pattern: "*.png" },
                        { kind: 0, pattern: "*.jpg" },
                        { kind: 0, pattern: "*.jpeg" },
                        { kind: 0, pattern: "*.webp" }
                    ]
                }],
                onSelected: function(path) {
                    if (path && path !== "") {
                        bgLayer.addAndApplyWallpaper(path);
                    }
                }
            });
        }

        function openScreenRecordDirPicker() {
            openFolderPicker({
                title: "Select Save Location",
                acceptLabel: "Select Folder",
                sourceLabel: "Screen Recording",
                initialFolder: (recordSaveDir && recordSaveDir !== "") ? recordSaveDir : (FileService.homeDir + "/Videos"),
                returnSettingsPage: "accessibility",
                onSelected: function(path) {
                    if (path && path !== "") {
                        recordSaveDir = path;
                    }
                }
            });
        }

        function showIslandApp(appKind, scr) {
            clearSuperPeek();
            ensureScreen(scr);
            openPopover = "";
            searchQuery = "";
            if (islandApp === "picker" && appKind !== "picker" && detachedApp !== "picker") {
                cancelPendingPortalPicker();
                resetFilePickerState();
            }
            _cleanupAppChooserOnLeave(appKind);
            if (detachedApp === appKind) detachedApp = "";
            islandApp = appKind;
        }

        function openIslandApp(appKind, scr) {
            if (LockService.locked) return;
            clearSuperPeek();
            ensureScreen(scr);
            openPopover = "";
            searchQuery = "";
            if (islandApp === appKind && (!scr || activeScreen === scr)) {
                collapseIslandApp();
            } else {
                if (islandApp === "picker" && appKind !== "picker" && detachedApp !== "picker") {
                    cancelPendingPortalPicker();
                    resetFilePickerState();
                }
                _cleanupAppChooserOnLeave(appKind);
                if (detachedApp === appKind) detachedApp = "";
                islandApp = appKind;
            }
        }

        function isBarHiddenOn(scr) {
            if (!scr) return false;
            if (openPopover !== "" || islandApp !== "") return false;
            return manualHideBar
                || (hideBarFullscreen && CompositorService.isFullscreenFor(scr))
                || (autoHideOnOverlap && CompositorService.isOverlappedFor(scr, barPosition));
        }

        function superPressed() {
            const scr = CompositorService.focusedScreen();
            ensureScreen(scr);
            superHeld = true;
            superUsedWithIsland = false;
            if (Date.now() - lastSuperComboMs < 350) {
                superPeekBar = false;
                superPeekWasHidden = false;
                superPeekSafetyTimer.stop();
                return;
            }
            const hidden = isBarHiddenOn(scr);
            superPeekWasHidden = hidden;
            if (hidden) {
                superPeekBar = true;
                superPeekSafetyTimer.restart();
            }
        }

        function superReleased() {
            const scr = CompositorService.focusedScreen();
            superPeekSafetyTimer.stop();
            const usedWithIsland = superUsedWithIsland;
            superHeld = false;
            superUsedWithIsland = false;
            if (superPeekWasHidden) {
                superPeekBar = false;
                superPeekWasHidden = false;
            } else if (!usedWithIsland) {
                togglePopover("launcher", scr);
            }
        }

        function clearSuperPeek() {
            superPeekSafetyTimer.stop();
            superPeekBar = false;
            superPeekWasHidden = false;
            superHeld = false;
            superUsedWithIsland = false;
        }

        function collapseIslandApp() {
            if (islandApp === "picker" && detachedApp !== "picker") {
                cancelPendingPortalPicker();
                const retPage = pickerReturnSettingsPage;
                const retDetached = pickerReturnDetached;
                resetFilePickerState();
                if (retPage !== "") {
                    settingsPage = retPage;
                    if (retDetached) {
                        islandApp = "";
                        detachedApp = "settings";
                    } else {
                        islandApp = "settings";
                    }
                    return;
                }
            }
            _cleanupAppChooserOnLeave("");
            islandApp = "";
        }

        function detachIslandApp(appKind) {
            if (!appKind || appKind === "") return;
            detachedApp = appKind;
            islandApp = "";
        }

        function reattachIslandApp(appKind) {
            if (appKind && appKind !== "") {
                openPopover = "";
                islandApp = appKind;
            }
            detachedApp = "";
        }

        function closeDetachedApp() {
            if (detachedApp === "picker" && islandApp !== "picker") {
                cancelPendingPortalPicker();
                const retPage = pickerReturnSettingsPage;
                const retDetached = pickerReturnDetached;
                resetFilePickerState();
                detachedApp = "";
                if (retPage !== "") {
                    settingsPage = retPage;
                    if (retDetached) {
                        detachedApp = "settings";
                    } else {
                        openPopover = "";
                        islandApp = "settings";
                    }
                }
                return;
            }
            detachedApp = "";
        }

        function showOsd(kind, val) {
            if (openPopover === "search") closePopovers();
            osdKind = kind;
            osdValue = val;
            osdOpen = true;
            osdHideTimer.restart();
        }

        function showInputIndicator(kind, label, badge, active) {
            if (!inputIndicatorEnabled || LockService.locked) return;
            if (openPopover === "search") closePopovers();
            inputSlotKind = kind;
            inputSlotLabel = label;
            inputSlotBadge = badge;
            inputSlotActive = active;
            inputSlotOpen = true;
            inputIndicatorHideTimer.restart();
        }

        function showWorkspace(id) {
            if (openPopover === "search") closePopovers();
            CompositorService.switchWorkspace(id);
            wsSlotOpen = true;
            wsHideTimer.restart();
        }

        function cycleAlert() {
            previewAlertMode = (previewAlertMode + 1) % 3;
        }

        property string portalResultPath: ""
        property string portalWindowsPath: ""
        property string portalInitialTab: "display"

        function openModal(kind) {
            if (LockService.locked) return;
            closePopovers();
            portalInitialTab = "display";
            modalKind = kind;
        }

        function openPortalPicker(resultPath, windowsPath) {
            portalResultPath = resultPath || "";
            portalWindowsPath = windowsPath || "";
            openIslandApp("portal", null);
        }

        function openFilePickerFromPortal(requestPath) {
            if (!requestPath) return;
            FileService.runCmd(["cat", requestPath], (ok, out) => {
                if (!ok || !out) return;
                try {
                    const req = JSON.parse(out);
                    cancelPendingPortalPicker();
                    pickerMode = req.mode === "download" ? "download" : "upload";
                    pickerTitle = req.title || "";
                    pickerAcceptLabel = req.acceptLabel || "";
                    pickerMultiple = Boolean(req.multiple);
                    pickerDirectory = Boolean(req.directory);
                    pickerInitialFolder = req.currentFolder || "";
                    pickerInitialName = req.currentName || "";
                    pickerAppId = req.appId || "";
                    pickerFilters = Array.isArray(req.filters) ? req.filters : [];
                    pickerResultPath = req.resultPath || "";
                    pickerRequestId += 1;
                    showIslandApp("picker", null);
                } catch (e) {
                    console.warn("Failed to parse file picker request:", e);
                }
            });
        }

        function resetFilePickerState() {
            pickerResultPath = "";
            onPickerSelected = null;
            pickerTitle = "";
            pickerAcceptLabel = "";
            pickerMultiple = false;
            pickerDirectory = false;
            pickerInitialFolder = "";
            pickerInitialName = "";
            pickerAppId = "";
            pickerFilters = [];
            pickerReturnSettingsPage = "";
            pickerReturnDetached = false;
        }

        function resetAppChooserState() {
            appChooserResultPath = "";
            appChooserUri = "";
            appChooserScheme = "";
            appChooserContentType = "";
            appChooserFilename = "";
            appChooserCallerApp = "";
            appChooserNoMatch = false;
            appChooserLastChoice = "";
            appChooserApps = [];
        }

        function openAppChooserFromPortal(requestPath) {
            if (!requestPath) return;
            FileService.runCmd(["cat", requestPath], (ok, out) => {
                if (!ok || !out) return;
                try {
                    const req = JSON.parse(out);
                    cancelPendingAppChooser();
                    appChooserUri = String(req.uri || "");
                    appChooserScheme = String(req.scheme || "");
                    appChooserContentType = String(req.contentType || "");
                    appChooserFilename = String(req.filename || "");
                    appChooserCallerApp = String(req.callerApp || "Application");
                    appChooserNoMatch = Boolean(req.noMatch);
                    appChooserLastChoice = String(req.lastChoice || "");
                    appChooserApps = Array.isArray(req.apps) ? req.apps : [];
                    appChooserResultPath = String(req.resultPath || "");
                    appChooserRequestId += 1;
                    showIslandApp("appchooser", null);
                } catch (e) {
                    console.warn("Failed to parse app chooser request:", e);
                }
            });
        }

        function updateAppChooserFromPortal(payloadPath) {
            if (!payloadPath || islandApp !== "appchooser") return;
            FileService.runCmd(["cat", payloadPath], (ok, out) => {
                if (!ok || !out || islandApp !== "appchooser") return;
                try {
                    const req = JSON.parse(out);
                    if (typeof req.noMatch === "boolean") appChooserNoMatch = req.noMatch;
                    if (Array.isArray(req.apps)) appChooserApps = req.apps;
                } catch (e) {
                    console.warn("Failed to parse updated app chooser payload:", e);
                }
            });
        }

        function openAppChooserPreview(mode) {
            cancelPendingAppChooser();
            const isNoMatch = (String(mode || "").toLowerCase() !== "multi");
            const sysApps = AppService.searchApps("", "All");
            const tls = (CompositorService.isHyprland && Hyprland.toplevels && Hyprland.toplevels.values)
                ? Hyprland.toplevels.values
                : [];
            const items = [];
            for (let i = 0; i < sysApps.length; ++i) {
                const a = sysApps[i];
                const aid = String(a.id || "").replace(/\.desktop$/i, "");
                const aidLower = aid.toLowerCase();
                const tail = aidLower.indexOf(".") !== -1 ? aidLower.split(".").pop() : aidLower;
                let winAddr = "";
                let winCls = "";
                let winTitle = "";
                let winWs = 0;
                for (let j = 0; j < tls.length; ++j) {
                    const tl = tls[j];
                    if (!tl) continue;
                    const ipc = tl.lastIpcObject || {};
                    const cls = String(ipc.class || (tl.wayland && tl.wayland.appId) || "").toLowerCase();
                    if (cls && (cls === aidLower || cls === tail || aidLower.indexOf(cls) !== -1)) {
                        winAddr = tl.address ? String(tl.address) : String(ipc.address || "");
                        winCls = cls;
                        winTitle = String(tl.title || "");
                        winWs = (tl.workspace && tl.workspace.id) ? tl.workspace.id : 1;
                        break;
                    }
                }
                items.push({
                    id: aid,
                    name: a.name || aid,
                    genericName: (a.entry && a.entry.genericName) ? String(a.entry.genericName) : "",
                    comment: (a.entry && a.entry.comment) ? String(a.entry.comment) : "",
                    icon: a.iconName || "",
                    category: a.category || "System",
                    fallbackSvg: a.fallbackSvg || "external-link",
                    recommended: !isNoMatch && i < 2,
                    running: winAddr !== "",
                    windowAddress: winAddr,
                    windowClass: winCls,
                    windowTitle: winTitle,
                    windowWorkspace: winWs
                });
            }
            items.sort((x, y) => {
                if (x.recommended !== y.recommended) return x.recommended ? -1 : 1;
                if (x.running !== y.running) return x.running ? -1 : 1;
                return String(x.name || "").localeCompare(String(y.name || ""));
            });
            appChooserResultPath = "";
            appChooserCallerApp = "Brave";
            appChooserUri = isNoMatch
                ? "acme-studio://oauth/callback?code=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9_paithosh_preview_token_2026&state=verify"
                : "myapp://oauth/callback?code=paithosh_session_token&workspace=default";
            appChooserScheme = isNoMatch ? "acme-studio" : "myapp";
            appChooserContentType = isNoMatch ? "x-scheme-handler/acme-studio" : "x-scheme-handler/myapp";
            appChooserFilename = "";
            appChooserNoMatch = isNoMatch;
            appChooserLastChoice = "";
            appChooserApps = items;
            appChooserRequestId += 1;
            showIslandApp("appchooser", null);
        }

        function closeModal() {
            modalKind = "";
        }
    }

    Timer {
        id: osdHideTimer
        interval: 1600
        repeat: false
        onTriggered: stateObj.osdOpen = false
    }

    Timer {
        id: inputIndicatorHideTimer
        interval: 1500
        repeat: false
        onTriggered: stateObj.inputSlotOpen = false
    }

    Connections {
        target: InputIndicatorService
        function onIndicatorTriggered(kind, label, badge, active) {
            stateObj.showInputIndicator(kind, label, badge, active);
        }
    }

    // Show the workspace slot when workspace is changed natively in Hyprland (keybinds etc.)
    Connections {
        target: Hyprland
        enabled: CompositorService.isHyprland
        function onRawEvent(event) {
            if (event.name === "workspacev2" || event.name === "openwindow" || event.name === "closewindow" || event.name === "activewindow" || event.name === "fullscreen" || event.name === "movewindow" || event.name === "changefloatingmode" || event.name === "togglegroup" || event.name === "moveintogroup" || event.name === "moveoutofgroup" || event.name === "activespecial") {
                stateObj.lastSuperComboMs = Date.now();
                if (stateObj.superPeekBar) {
                    stateObj.clearSuperPeek();
                } else if (stateObj.superHeld && !superHeldSyncProc.running) {
                    superHeldSyncProc.running = true;
                }
            }
            if (event.name !== "workspacev2") return;
            if (stateObj.openPopover === "search") stateObj.closePopovers();
            stateObj.wsSlotOpen = true;
            wsHideTimer.restart();
        }
    }

    Timer {
        id: superHeldSyncTimer
        interval: 250
        repeat: true
        running: stateObj.superHeld && CompositorService.isHyprland
        onTriggered: {
            if (!superHeldSyncProc.running) superHeldSyncProc.running = true;
        }
    }

    Process {
        id: superHeldSyncProc
        command: ["hyprctl", "repl", "return tostring(hl.is_key_down(\"Super_L\") or hl.is_key_down(\"Super_R\"))"]
        stdout: StdioCollector {
            onStreamFinished: {
                if ((text || "").trim() === "false") {
                    stateObj.superHeld = false;
                    stateObj.superUsedWithIsland = false;
                }
            }
        }
    }

    Timer {
        id: superPeekSafetyTimer
        interval: 2500
        repeat: false
        onTriggered: stateObj.clearSuperPeek()
    }

    Timer {
        id: wsHideTimer
        interval: 1400
        repeat: false
        onTriggered: stateObj.wsSlotOpen = false
    }

    Timer {
        id: chargeHideTimer
        interval: 2400
        repeat: false
        onTriggered: stateObj.chargeSlotOpen = false
    }

    Connections {
        target: AudioService
        function onOsdTriggered(kind, value) {
            stateObj.showOsd(kind, value);
        }
    }

    Connections {
        target: BrightnessService
        function onOsdTriggered(kind, value) {
            stateObj.showOsd(kind, value);
        }
    }

    Connections {
        target: PowerService
        function onChargerChanged(charging, pct, watts) {
            stateObj.chargeIsCharging = charging;
            const wattSuffix = (charging && watts > 0) ? (" (" + watts + "W)") : "";
            stateObj.chargeText = charging ? ("Charging • " + pct + "%" + wattSuffix) : ("Unplugged • " + pct + "%");
            stateObj.chargeSlotOpen = true;
            chargeHideTimer.restart();
        }
        function onSessionActionRequested(action) {
            stateObj.requestSessionAction(action, false);
        }
    }

    Timer {
        id: statusHideTimer
        interval: 2500
        onTriggered: stateObj.kdeSlotOpen = false
    }

    Timer {
        id: reloadCollapseTimer
        interval: 180
        repeat: false
        onTriggered: {
            stateObj.reloadPhase = "exiting";
            // Let the OLED curtain + "Reloading Shell..." dialog fade in and sweep smoothly
            const speed = Math.max(0.5, Theme.speedMultiplier || 1.0);
            reloadCommitTimer.interval = bgLayer.exitFadeMs + Math.max(120, Math.round(180 / speed));
            reloadCommitTimer.restart();
        }
    }

    Timer {
        id: reloadCommitTimer
        interval: 460
        repeat: false
        onTriggered: {
            if (stateObj.reloadPhase !== "exiting") return;
            // Fade the moving dialog capsule out into pure still OLED black BEFORE calling Quickshell.reload()
            // so zero spinners or progress bars freeze during QML recompilation
            stateObj.reloadPhase = "committing";
            const speed = Math.max(0.5, Theme.speedMultiplier || 1.0);
            reloadExecuteTimer.interval = Math.max(150, Math.round(220 / speed));
            reloadExecuteTimer.restart();
        }
    }

    Timer {
        id: reloadExecuteTimer
        interval: 220
        repeat: false
        onTriggered: {
            if (stateObj._pendingReloadHyprland && CompositorService.isHyprland) {
                Quickshell.execDetached(["hyprctl", "reload"]);
            }
            stateObj._executeShellReloadNow();
        }
    }

    Timer {
        id: reloadRevealHoldTimer
        interval: 720
        repeat: false
        onTriggered: {
            if (stateObj.reloadPhase !== "revealing") return;
            // Re-enable smooth opacity Behavior right before fading curtain 1.0 -> 0.0
            stateObj.reloadInstantOpaque = false;
            stateObj.reloadPhase = "clearing";
            const speed = Math.max(0.5, Theme.speedMultiplier || 1.0);
            reloadClearTimer.interval = Math.max(260, Math.round(520 / speed));
            reloadClearTimer.restart();
        }
    }

    Timer {
        id: reloadClearTimer
        interval: 520
        repeat: false
        onTriggered: {
            if (stateObj.reloadPhase === "clearing") {
                stateObj.reloadInstantOpaque = false;
                stateObj.reloadPhase = "idle";
            }
        }
    }

    Timer {
        id: reloadPostShowTimer
        property string pendingMessage: "Config Reloaded"
        interval: 120
        repeat: false
        onTriggered: {
            reloadState.pendingBgReveal = false;
            stateObj.showReloadResult(true, pendingMessage);
        }
    }

    Timer {
        id: sessionExecuteTimer
        interval: 650
        repeat: false
        onTriggered: {
            if (stateObj.sessionPhase !== "fading") return;
            stateObj.sessionPhase = "executing";
            const speed = Math.max(0.5, Theme.speedMultiplier || 1.0);
            sessionCommitTimer.interval = Math.max(120, Math.round((stateObj.sessionDryRun ? 320 : 200) / speed));
            sessionCommitTimer.restart();
        }
    }

    Timer {
        id: sessionCommitTimer
        interval: 200
        repeat: false
        onTriggered: {
            if (stateObj.sessionPhase !== "executing") return;
            if (stateObj.sessionDryRun) {
                stateObj.sessionPhase = "cancelling";
                sessionCleanupTimer.interval = 300;
                sessionCleanupTimer.restart();
                return;
            }
            PowerService.runSessionCommand(stateObj.sessionAction);
        }
    }

    Timer {
        id: sessionCleanupTimer
        interval: 300
        repeat: false
        onTriggered: {
            stateObj.sessionPhase = "idle";
            stateObj.sessionAction = "";
            stateObj.sessionDryRun = false;
        }
    }

    Timer {
        id: reloadHideTimer
        interval: 1900
        repeat: false
        onTriggered: stateObj.reloadSlotOpen = false
    }

    Timer {
        id: reloadSafetyTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (stateObj.reloadPhase !== "idle") {
                stateObj.reloadPhase = "idle";
                stateObj.reloadSlotOpen = false;
            }
        }
    }

    Connections {
        target: PackageService
        function onShellReloadRequested(hard, reason) {
            stateObj.requestShellReload({
                reloadHyprland: false,
                hard: hard,
                reason: reason || "Shell Updated"
            });
        }
    }

    Connections {
        target: KdeConnectService
        function onDropStatusChanged(active, message, done) {
            if (active) statusHideTimer.stop();
            stateObj.kdeSlotOpen = active;
            stateObj.kdeText = message;
        }
    }

    Connections {
        target: ScreenRecordService
        function onFinished(action, path, sizeText) {
            if (action === "SAVED") {
                stateObj.kdeText = "Saved ~/Videos (" + sizeText + ")";
            } else {
                stateObj.kdeText = "Recording copied (" + sizeText + ")";
            }
            stateObj.kdeSlotOpen = true;
            statusHideTimer.restart();
        }
        function onFailed(reason) {
            stateObj.kdeText = reason || "Recording failed";
            stateObj.kdeSlotOpen = true;
            statusHideTimer.restart();
        }
    }

    // Hyprland GlobalShortcuts (loaded only when running under Hyprland)
    Loader {
        active: CompositorService.isHyprland
        sourceComponent: Component {
            Scope {
                GlobalShortcut {
                    name: "paithosh-search"
                    description: "Toggle Paithosh Global Search"
                    onPressed: stateObj.togglePopover("search", null)
                }
                GlobalShortcut {
                    name: "paithosh-launcher"
                    description: "Toggle Paithosh App Launcher"
                    onPressed: stateObj.togglePopover("launcher", null)
                }
                GlobalShortcut {
                    name: "paithosh-dashboard"
                    description: "Toggle Paithosh Control Center"
                    onPressed: stateObj.togglePopover("dashboard", null)
                }
                GlobalShortcut {
                    name: "paithosh-overview"
                    description: "Toggle Paithosh Workspace Overview"
                    onPressed: stateObj.togglePopover("overview", CompositorService.focusedScreen())
                }
            }
        }
    }

    // Multi-Monitor Dynamic Island Instances
    Variants {
        model: Quickshell.screens
        DynamicIsland {
            shellState: stateObj
        }
    }

    // Anchored Popover Host (Launcher / Dashboard / Search Results / Notification Toast)
    PopoverHost {
        shellState: stateObj
    }

    // Reusable Monochrome Modal Overlay (lazy-loaded on first use)
    Loader {
        id: modalOverlayLoader
        active: false
        function open() {
            active = true;
            if (source.toString() === "") setSource("components/ModalOverlay.qml", { shellState: stateObj });
        }
        Component.onCompleted: if (stateObj.modalKind !== "") open()
    }

    // Independent Floating Window for Detached Settings / Files / Picker (lazy-loaded on first detach)
    Loader {
        id: detachedAppLoader
        active: false
        function open() {
            active = true;
            if (source.toString() === "") setSource("components/DetachedAppWindow.qml", { shellState: stateObj });
        }
        Component.onCompleted: if (stateObj.detachedApp !== "") open()
    }

    Connections {
        target: stateObj
        function onModalKindChanged() { if (stateObj.modalKind !== "") modalOverlayLoader.open(); }
        function onDetachedAppChanged() { if (stateObj.detachedApp !== "") detachedAppLoader.open(); }
    }

    Connections {
        target: LockService
        function onLockedChanged() {
            if (LockService.locked) {
                lockScreenLoader.open();
                stateObj.closePopovers();
                stateObj.collapseIslandApp();
                stateObj.closeModal();
            }
        }
        function onTransitionVisibleChanged() {
            if (LockService.transitionVisible) lockScreenLoader.open();
        }
        function onEffectPresetChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onAmbientSoundChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onSilentModeChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onSfxEnabledChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onShowNotificationsChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onHideNotifContentChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onShowMediaChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onShowSystemAlertsChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onEffectIntensityChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onAmbientVolumeChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onDimOpacityChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
    }

    Connections {
        target: CursorService
        function onStyleChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onSizeChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onColorModeChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onFixedColorChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onMotionBlurChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onMotionBlurStrengthChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onMotionBlurThresholdChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
    }

    Connections {
        target: SoundService
        function onEnabledChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onVolumeChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
    }

    // Experimental Motion Blur Cursor Overlay (lazy-loaded & completely click-through)
    Loader {
        active: CursorService.motionBlur && !Theme.reduceMotion && CompositorService.isHyprland && !LockService.locked
        source: "components/CursorMotionOverlay.qml"
    }

    // Native Wayland Session Lock (lazy-loaded on first lock)
    Loader {
        id: lockScreenLoader
        active: false
        function open() {
            active = true;
            if (source.toString() === "") {
                setSource("components/LockScreen.qml", {
                    shellState: stateObj,
                    wallpaperPath: bgLayer.currentWallpaperPath
                });
            }
        }
        Component.onCompleted: if (LockService.locked || LockService.transitionVisible) open()
    }
    Binding {
        target: lockScreenLoader.item
        property: "wallpaperPath"
        value: bgLayer.currentWallpaperPath
        when: lockScreenLoader.status === Loader.Ready
    }

    // Persistent Reloadable Fullscreen Transition Curtain (Reload / Logout / Restart / Shutdown)
    // Kept always-mapped with 0x0 click-through mask when idle so Wayland surface survives soft reload with zero blink
    Variants {
        reloadableId: "paithoshTransitionVariants"
        model: Quickshell.screens
        SessionTransitionOverlay {
            shellState: stateObj
        }
    }

    // IPC API for Hyprland keybindings & KDE preview verification
    IpcHandler {
        target: "paithosh"

        function lock(): void {
            LockService.lock();
        }

        function toggleLauncher(): void {
            stateObj.togglePopover("launcher", null);
        }

        function toggleClipboard(): void {
            stateObj.togglePopover("clipboard", null);
        }

        function superPressed(): void {
            stateObj.superPressed();
        }

        function superReleased(): void {
            stateObj.superReleased();
        }

        function toggleDashboard(tab: string): void {
            if (tab !== "") stateObj.dashboardTab = tab;
            stateObj.togglePopover("dashboard", null);
        }

        function toggleSearch(): void {
            stateObj.togglePopover("search", null);
        }

        function toggleOverview(): void {
            stateObj.togglePopover("overview", CompositorService.focusedScreen());
        }

        function openSettings(page: string): void {
            stateObj.settingsPage = page !== "" ? page : "home";
            stateObj.openIslandApp("settings", null);
        }

        function openFiles(): void {
            stateObj.openIslandApp("files", null);
        }

        function openMusic(): void {
            stateObj.openIslandApp("music", null);
        }

        function openMusicSettings(tab: string): void {
            if (LockService.locked) return;
            if (tab !== "") MixcloudService.settingsTab = tab;
            MixcloudService.activeSection = "settings";
            stateObj.showIslandApp("music", null);
        }

        function openPicker(mode: string): void {
            stateObj.cancelPendingPortalPicker();
            stateObj.resetFilePickerState();
            if (mode === "directory" || mode === "folder") {
                stateObj.pickerMode = "upload";
                stateObj.pickerDirectory = true;
                stateObj.pickerTitle = "Select Folder";
                stateObj.pickerAcceptLabel = "Select Folder";
            } else {
                stateObj.pickerMode = mode === "download" ? "download" : "upload";
            }
            stateObj.pickerRequestId += 1;
            stateObj.showIslandApp("picker", null);
        }

        function nextWallpaper(): void {
            bgLayer.nextWallpaper();
        }

        function setWallpaper(path: string): void {
            bgLayer.setWallpaper(path);
        }

        function setWallpaperColor(enabled: bool, mode: string): void {
            if (mode === "Solid" || mode === "Gradient") stateObj.setWallpaperColorMode(mode);
            stateObj.setWallpaperColorEnabled(enabled);
        }

        function setWallpapersDisabled(disabled: bool): void {
            stateObj.setWallpapersDisabled(disabled);
        }

        function setReduceMotion(enabled: bool): void {
            stateObj.setReduceMotion(enabled);
        }

        function detachApp(appKind: string): void {
            stateObj.detachIslandApp(appKind !== "" ? appKind : stateObj.islandApp);
        }

        function reattachApp(appKind: string): void {
            stateObj.reattachIslandApp(appKind !== "" ? appKind : stateObj.detachedApp);
        }

        function toggleHideBar(): void {
            stateObj.manualHideBar = !stateObj.manualHideBar;
            if (stateObj.manualHideBar) stateObj.closePopovers();
        }

        function setBarPosition(pos: string): void {
            stateObj.barPosition = (pos === "bottom") ? "bottom" : "top";
        }

        function toggleBarPosition(): void {
            stateObj.barPosition = (stateObj.barPosition === "bottom") ? "top" : "bottom";
        }

        function adjustVolume(delta: int): void {
            AudioService.adjustVolume(delta);
        }

        function toggleMute(): void {
            AudioService.toggleMute();
        }

        function adjustBrightness(delta: int): void {
            BrightnessService.adjustBrightness(delta);
        }

        function switchWorkspace(id: int): void {
            stateObj.showWorkspace(id);
        }

        function cycleAlert(): void {
            stateObj.cycleAlert();
        }

        function triggerCharger(): void {
            PowerService.triggerPreviewCharger();
        }

        function triggerKdeDrop(fileName: string): void {
            KdeConnectService.sendFile(fileName);
        }

        function triggerPackageUpdate(count: int): void {
            PackageService.triggerPreviewUpdates(count);
        }

        function checkPackageUpdates(): void {
            PackageService.checkUpdates(true);
        }

        function triggerSystemBackup(reason: string): void {
            BackupService.createSystemBackup(reason !== "" ? reason : "Pre-update snapshot", !BackupService.useBtrfsSnapshot, null);
        }

        function triggerQuickDataBackup(folderName: string): void {
            if (folderName !== "") BackupService.selectOnlyFolder(folderName);
            BackupService.createDataBackup();
        }

        function triggerNotif(app: string, title: string, body: string): void {
            NotificationService.pushPreviewNotification(app, title, body);
        }

        function notifyStatus(message: string): void {
            stateObj.notifyStatus(message);
        }

        function toggleScreenRecord(): void {
            ScreenRecordService.toggle();
        }

        function setPreviewFocus(title: string): void {
            CompositorService.previewTitle = title;
        }

        function togglePreviewMedia(): void {
            MediaService.togglePreviewMedia();
        }

        function togglePreviewNotif(): void {
            NotificationService.togglePreviewNotif();
        }

        function applyState(stateName: string): void {
            stateObj.closePopovers();
            stateObj.osdOpen = false;
            stateObj.wsSlotOpen = false;
            stateObj.chargeSlotOpen = false;
            stateObj.kdeSlotOpen = false;
            PackageService.dismissStatusEvent();

            const hasFocus = stateName.indexOf("focus") !== -1 || stateName === "all";
            const hasMedia = stateName.indexOf("media") !== -1 || stateName === "all";
            const hasNotif = stateName.indexOf("notif") !== -1 || stateName === "all";

            CompositorService.previewTitle = hasFocus ? "kitty — ~/Projects/paithosh" : "";
            MediaService.previewMediaActive = hasMedia;
            NotificationService.previewNotifActive = hasNotif;
        }

        function openModal(kind: string): void {
            stateObj.openModal(kind);
        }

        function closeModal(): void {
            stateObj.closeModal();
        }

        function reloadShell(mode: string): void {
            const m = (mode || "").toLowerCase();
            stateObj.requestShellReload({
                reloadHyprland: m !== "qml-only",
                hard: m === "hard",
                restartProcess: m === "restart",
                reason: m === "qml-only" ? "Config Reloaded" : "Shell Reloaded"
            });
        }

        function sessionAction(action: string): void {
            stateObj.requestSessionAction(action, false);
        }

        function previewSessionTransition(action: string): void {
            stateObj.requestSessionAction(action !== "" ? action : "shutdown", true);
        }
    }

    IpcHandler {
        target: "portal"

        function open(resultPath: string, windowsPath: string): void {
            stateObj.openPortalPicker(resultPath, windowsPath);
        }
    }

    IpcHandler {
        target: "picker"

        function openFromPortal(requestPath: string): void {
            stateObj.openFilePickerFromPortal(requestPath);
        }

        function closeFromPortal(): void {
            if (stateObj.islandApp === "picker") {
                stateObj.pickerResultPath = "";
                stateObj.collapseIslandApp();
            }
        }
    }

    IpcHandler {
        target: "appchooser"

        function openFromPortal(requestPath: string): void {
            stateObj.openAppChooserFromPortal(requestPath);
        }

        function updateChoices(payloadPath: string): void {
            stateObj.updateAppChooserFromPortal(payloadPath);
        }

        function closeFromPortal(): void {
            if (stateObj.islandApp === "appchooser") {
                stateObj.appChooserResultPath = "";
                stateObj.collapseIslandApp();
            }
        }

        function focusAndNotify(address: string, message: string): void {
            if (address !== "") CompositorService.focusWindow(address);
            if (message !== "") stateObj.notifyStatus(message);
        }

        function preview(mode: string): void {
            stateObj.openAppChooserPreview(mode);
        }
    }
}
