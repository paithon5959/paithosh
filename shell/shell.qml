import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "services"
import "components"

ShellRoot {
    id: root

    BackgroundLayer {
        id: bgLayer
    }

    Binding {
        target: DiscordRpcService
        property: "themeName"
        value: Theme.activePreset
    }

    property string profileDir: (Quickshell.env("HOME") || "/tmp") + "/.config/paithosh"
    property string settingsPath: profileDir + "/settings.json"

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
                    if (typeof obj.themePreset === "string") Theme.applyPreset(obj.themePreset);
                    if (typeof obj.accentMode === "string") Theme.accentMode = obj.accentMode;
                    if (typeof obj.hueVal === "number") Theme.hueVal = obj.hueVal;
                    if (typeof obj.satVal === "number") Theme.satVal = obj.satVal;
                    if (typeof obj.valVal === "number") Theme.valVal = obj.valVal;
                    if (typeof obj.gradientAngle === "number") Theme.gradientAngle = obj.gradientAngle;
                    if (typeof obj.masterRatio === "number") Theme.masterRatio = obj.masterRatio;
                    if (typeof obj.preserveSplit === "boolean") Theme.preserveSplit = obj.preserveSplit;
                    if (typeof obj.shadowRange === "number") Theme.shadowRange = obj.shadowRange;
                    if (obj.customAccentActive === true) {
                        Theme.applyAccentHsv(Theme.hueVal, Theme.satVal, Theme.valVal);
                    }
                    if (typeof obj.gooeyEnabled === "boolean") Theme.gooeyEnabled = obj.gooeyEnabled;
                    if (typeof obj.speedMultiplier === "number" && obj.speedMultiplier >= 0.5 && obj.speedMultiplier <= 2.5) Theme.speedMultiplier = obj.speedMultiplier;
                    if (typeof obj.transitionMode === "string") bgLayer.transitionMode = obj.transitionMode;
                    if (typeof obj.wallpaperPath === "string" && obj.wallpaperPath.length > 0) {
                        bgLayer.applyWallpaperPath(obj.wallpaperPath);
                    } else if (typeof obj.wallpaperIndex === "number") {
                        bgLayer.applyWallpaperIndex(obj.wallpaperIndex);
                    }
                }
            } catch (e) {}
            stateObj._applyingExternalState = false;
            stateObj.applyIslandMetrics();
            stateObj.settingsLoaded = true;
            stateObj.themeImportSeq += 1;
            Qt.callLater(function() {
                CompositorService.setActiveThemePresetName(stateObj.compositorKeyForPreset(Theme.activePreset));
                stateObj.refreshProfiles();
                if (!hasSettings) stateObj.loadProfile("default", true);
            });
        }
        onLoadFailed: {
            stateObj.applyIslandMetrics();
            stateObj.settingsLoaded = true;
            stateObj.themeImportSeq += 1;
            Qt.callLater(function() {
                CompositorService.setActiveThemePresetName(stateObj.compositorKeyForPreset(Theme.activePreset));
                stateObj.refreshProfiles();
                stateObj.loadProfile("default", true);
            });
        }
    }

    Process {
        id: settingsWriter
        property string payload: ""
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "sh", root.settingsPath, payload]
    }

    Process {
        id: paishWriter
        property string targetPath: ""
        property string payload: ""
        command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s\\n' \"$2\" > \"$1\"", "sh", targetPath, payload]
        onExited: stateObj.refreshProfiles()
    }

    Process {
        id: paishReader
        property string targetPath: ""
        property bool silentOnMissing: false
        property string profileName: "default"
        command: ["sh", "-c", "cat \"$1\" 2>/dev/null || true", "sh", targetPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const raw = (this.text || "").trim();
                if (raw === "") {
                    if (!paishReader.silentOnMissing) {
                        stateObj.lastProfileStatus = "Profile not found: " + paishReader.profileName + ".paish";
                        stateObj.lastProfileOk = false;
                    }
                    return;
                }
                const decoded = Theme.decodeState(raw);
                if (!decoded) {
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

    Timer {
        id: saveSettingsTimer
        interval: 80
        repeat: false
        onTriggered: stateObj.writeSettingsNow()
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
            }
        }
        function onCustomAccentActiveChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onAccentModeChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onHueValChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onSatValChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onValValChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onGradientAngleChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onMasterRatioChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onPreserveSplitChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onShadowRangeChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onGooeyEnabledChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onSpeedMultiplierChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
    }

    Connections {
        target: bgLayer
        function onCurrentIndexChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onCurrentWallpaperPathChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
        function onTransitionModeChanged() { if (!stateObj._applyingExternalState) stateObj.saveSettings(); }
    }

    QtObject {
        id: stateObj
        function compositorKeyForPreset(presetName) {
            const meta = Theme.presetMeta(presetName);
            return meta ? meta.compositorKey : "oled";
        }

        function selectPreset(name) {
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
            return true;
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
        }

        function applyCustomAccent(h, s, v) {
            Theme.applyAccentHsv(h, s, v);
            if (!_applyingExternalState) {
                markAppearanceCustomized();
            }
            saveSettings();
        }

        property var activeScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        property string openPopover: "" // "" | "launcher" | "dashboard" | "search" | "overview"
        property string islandApp: "" // "" | "settings" | "files" | "picker"
        property string detachedApp: "" // "" | "settings" | "files" | "picker"
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
        property bool manualHideBar: false
        property bool hideBarFullscreen: true
        property bool autoHideOnOverlap: true
        property bool recordAudio: true
        property bool recordMic: false
        property string recordPreset: "standard"
        property string recordResolution: "native"
        property int recordFps: 30
        property string recordSaveDir: ""
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
        onRecordSaveDirChanged: {
            ScreenRecordService.saveDir = recordSaveDir;
            if (!stateObj._applyingExternalState) saveSettings();
        }
        property string islandCornerRadius: "26px (Default)"
        property string barPosition: "top" // "top" | "bottom"
        property bool topEdgeOffset: true
        property bool activeBorderHighlight: true
        property string globalSurfaceTheme: "OLED Pure"
        property bool superPeekBar: false
        property bool superPeekWasHidden: false
        property double lastSuperComboMs: 0
        property bool settingsLoaded: false
        property bool _applyingExternalState: false
        property string activeProfile: ""
        property string _autoForkTarget: ""
        property var availableProfiles: []
        property string lastProfileStatus: ""
        property bool lastProfileOk: true
        property int themeImportSeq: 0

        function sanitizeProfileName(name) {
            const clean = String(name || "default").trim().replace(/[^a-zA-Z0-9._-]/g, "_");
            return clean !== "" ? clean : "default";
        }

        function exportThemeCode(profileName) {
            return Theme.encodeState(stateObj, CompositorService, bgLayer, profileName);
        }

        function applyDecodedTheme(d, profileName) {
            if (!d) return false;
            autoForkSaveTimer.stop();
            _autoForkTarget = "";
            _applyingExternalState = true;
            activeProfile = profileName ? sanitizeProfileName(profileName) : "";
            Theme.applyPreset(d.presetName);
            Theme.accentMode = d.accentMode;
            Theme.gradientAngle = d.gradientAngle;
            Theme.masterRatio = d.masterRatio;
            Theme.preserveSplit = d.preserveSplit;
            Theme.shadowRange = d.shadowRange;
            if (d.customAccentActive) {
                Theme.applyAccentHsv(d.hueVal, d.satVal, d.valVal);
            } else {
                Theme.hueVal = d.hueVal;
                Theme.satVal = d.satVal;
                Theme.valVal = d.valVal;
            }
            if (typeof d.gooeyEnabled === "boolean") Theme.gooeyEnabled = d.gooeyEnabled;
            if (typeof d.speedMultiplier === "number") Theme.speedMultiplier = d.speedMultiplier;

            globalSurfaceTheme = d.globalSurfaceTheme;
            islandCornerRadius = d.islandCornerRadius;
            topEdgeOffset = d.topEdgeOffset;
            hideBarFullscreen = d.hideBarFullscreen;
            autoHideOnOverlap = d.autoHideOnOverlap;
            activeBorderHighlight = d.activeBorderHighlight;

            CompositorService.setActiveThemePresetName(compositorKeyForPreset(d.presetName));
            CompositorService.setGapsAndBorder(d.gapsIn, d.gapsOut, d.borderSize);
            CompositorService.setLayout(d.layoutName);
            CompositorService.setDecoration(d.cornerRounding, d.shadowEnabled, d.inactiveOpacity);
            CompositorService.setAnimationsEnabled(d.animationsEnabled);
            CompositorService.setSpringCurve(d.springStiffness, d.springDamping);
            CompositorService.setBlurConfig(d.blurEnabled, d.blurSize, d.blurPasses, d.blurVibrancy);

            bgLayer.transitionMode = d.transitionMode;
            bgLayer.applyWallpaperIndex(d.wallpaperIndex);

            _applyingExternalState = false;
            themeImportSeq += 1;
            saveSettings();
            return true;
        }

        function importThemeCode(input) {
            const decoded = Theme.decodeState(input);
            if (!decoded) return false;
            const targetName = sanitizeProfileName(decoded.profileName || decoded.presetName || "imported");
            applyDecodedTheme(decoded, targetName);
            saveProfile(targetName);
            return true;
        }

        function saveProfile(name) {
            const prof = sanitizeProfileName(name);
            activeProfile = prof;
            const bundle = exportThemeCode(prof);
            paishWriter.targetPath = root.profileDir + "/" + prof + ".paish";
            paishWriter.payload = bundle.raw;
            paishWriter.running = false;
            paishWriter.running = true;
            lastProfileStatus = "Saved " + prof + ".paish (" + bundle.raw.length + "B)";
            lastProfileOk = true;
            return bundle;
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
        }

        function writeSettingsNow() {
            if (!settingsLoaded) return;
            const data = {
                hideBarFullscreen: hideBarFullscreen,
                autoHideOnOverlap: autoHideOnOverlap,
                recordAudio: recordAudio,
                recordMic: recordMic,
                recordPreset: recordPreset,
                recordResolution: recordResolution,
                recordFps: recordFps,
                recordSaveDir: recordSaveDir,
                islandCornerRadius: islandCornerRadius,
                barPosition: barPosition,
                topEdgeOffset: topEdgeOffset,
                activeBorderHighlight: activeBorderHighlight,
                globalSurfaceTheme: globalSurfaceTheme,
                themePreset: Theme.activePreset,
                activeProfile: activeProfile,
                customAccentActive: Theme.customAccentActive,
                accentMode: Theme.accentMode,
                hueVal: Theme.hueVal,
                satVal: Theme.satVal,
                valVal: Theme.valVal,
                gradientAngle: Theme.gradientAngle,
                masterRatio: Theme.masterRatio,
                preserveSplit: Theme.preserveSplit,
                shadowRange: Theme.shadowRange,
                gooeyEnabled: Theme.gooeyEnabled,
                speedMultiplier: Theme.speedMultiplier,
                transitionMode: bgLayer.transitionMode,
                wallpaperIndex: bgLayer.currentIndex,
                wallpaperPath: bgLayer.currentWallpaperPath
            };
            settingsWriter.payload = JSON.stringify(data, null, 2);
            settingsWriter.running = false;
            settingsWriter.running = true;
        }

        onActiveProfileChanged: saveSettings()

        onHideBarFullscreenChanged: saveSettings()
        onAutoHideOnOverlapChanged: saveSettings()
        onIslandCornerRadiusChanged: { applyIslandMetrics(); saveSettings(); }
        onBarPositionChanged: saveSettings()
        onTopEdgeOffsetChanged: { applyIslandMetrics(); saveSettings(); }
        onActiveBorderHighlightChanged: saveSettings()
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

        function closePopovers() {
            if (islandApp === "picker" && detachedApp !== "picker") {
                cancelPendingPortalPicker();
                resetFilePickerState();
            }
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
            if (superPeekWasHidden) {
                superPeekBar = false;
                superPeekWasHidden = false;
            } else {
                togglePopover("launcher", scr);
            }
        }

        function clearSuperPeek() {
            superPeekSafetyTimer.stop();
            superPeekBar = false;
            superPeekWasHidden = false;
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

    // Show the workspace slot when workspace is changed natively in Hyprland (keybinds etc.)
    Connections {
        target: Hyprland
        enabled: CompositorService.isHyprland
        function onRawEvent(event) {
            if (event.name === "workspacev2" || event.name === "openwindow" || event.name === "closewindow" || event.name === "activewindow" || event.name === "fullscreen" || event.name === "movewindow" || event.name === "changefloatingmode" || event.name === "togglegroup" || event.name === "moveintogroup" || event.name === "moveoutofgroup" || event.name === "activespecial") {
                stateObj.lastSuperComboMs = Date.now();
                if (stateObj.superPeekBar) {
                    stateObj.clearSuperPeek();
                }
            }
            if (event.name !== "workspacev2") return;
            if (stateObj.openPopover === "search") stateObj.closePopovers();
            stateObj.wsSlotOpen = true;
            wsHideTimer.restart();
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
    }

    Timer {
        id: statusHideTimer
        interval: 2500
        onTriggered: stateObj.kdeSlotOpen = false
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

    // Reusable Monochrome Modal Overlay (Confirm / Multi / Monitor+Portal / Progress)
    ModalOverlay {
        shellState: stateObj
    }

    // Independent Floating Window for Detached Settings / Files / Picker
    DetachedAppWindow {
        shellState: stateObj
    }

    Connections {
        target: LockService
        function onLockedChanged() {
            if (LockService.locked) {
                stateObj.closePopovers();
                stateObj.collapseIslandApp();
                stateObj.closeModal();
            }
        }
    }

    // Native Wayland Session Lock (Minimal Statusbar Lock Screen)
    LockScreen {
        shellState: stateObj
        wallpaperPath: bgLayer.currentWallpaperPath
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
            stateObj.kdeText = message;
            stateObj.kdeSlotOpen = true;
            statusHideTimer.restart();
            const lower = (message || "").toLowerCase();
            if (lower.indexOf("screenshot") !== -1 || lower.indexOf("region") !== -1 || lower.indexOf("window") !== -1) {
                SoundService.playShutter();
            } else {
                SoundService.playNotify();
            }
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
}
