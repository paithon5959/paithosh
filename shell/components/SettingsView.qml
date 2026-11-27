import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import ".."
import "../services"
import "common"

Item {
    id: root
    implicitWidth: 860
    implicitHeight: 540

    property var shellState: null
    property string currentPage: ""
    property var loadedPages: ({})
    property bool _cursorPagePrimed: false
    property string pendingHyprMode: ""
    property string searchQuery: ""
    readonly property string activeSearchQuery: searchQuery.trim()
    property bool systemOpen: true
    property bool networkOpen: false
    property bool personalizationOpen: false

    // Shared UI state matching settings.html
    property int quickVolume: 72
    property bool nightLight: false
    property string powerMode: "Balanced"
    property bool dndEnabled: false

    // Display (live applied state)
    property string activeMonitorName: "eDP-1"
    property string displayScale: "100%"
    property string displayRes: "1920 × 1080"
    property string displayRefreshRate: "60 Hz"
    property string displayOrient: "Landscape"
    property bool rotationLock: true

    // Display (staged draft state for preview before Apply)
    property string draftDisplayScale: "100%"
    property string draftDisplayRes: "1920 × 1080"
    property string draftDisplayRefreshRate: "60 Hz"
    property string draftDisplayOrient: "Landscape"
    readonly property bool hasPendingDisplayChanges:
        draftDisplayScale !== displayScale ||
        draftDisplayRes !== displayRes ||
        draftDisplayRefreshRate !== displayRefreshRate ||
        draftDisplayOrient !== displayOrient

    property var displayResOptions: ["1920 × 1080"]
    property var displayRefreshOptions: ["60 Hz"]
    property var displayRatesByRes: ({})
    property var displayModeMap: ({})
    property int maxDisplayWidth: 1920
    property int maxDisplayHeight: 1080
    property string maxDisplayRes: "1920 × 1080"

    function isPresetActive(name) {
        if (Theme.wallpaperColorEnabled) return false;
        const meta = Theme.presetMeta(name);
        return Theme.activePreset === name
            && !Theme.customAccentActive
            && !Theme.customAccent2Active
            && !Theme.customPaletteActive
            && Boolean(meta && meta.shellGradient) === Theme.shellGradientEnabled
            && Boolean(meta && meta.surfaceGradient) === Theme.surfaceGradientEnabled
            && Boolean(meta && meta.accentGradient) === Theme.accentGradientEnabled
            && (!root.shellState || root.shellState.activeProfile === "");
    }

    function selectThemePreset(name) {
        if (Theme.wallpaperColorEnabled) return;
        if (root.shellState) root.shellState.selectPreset(name);
        else Theme.applyPreset(name);
    }

    function markAppearanceChanged() {
        if (root.shellState) root.shellState.markAppearanceCustomized();
    }

    function loadStudioSlot(slot) {
        const target = slot || root.colorStudioSlot || "accent";
        root.colorStudioSlot = target;
        root.studioHexError = "";
        const hex = Theme.getSlotHex(target);
        root.studioHexInput = hex;
        if (target === "accent" && Theme.customAccentActive) {
            root.studioHue = Theme.hueVal;
            root.studioSat = Theme.satVal;
            root.studioVal = Theme.valVal;
        } else {
            const c = Qt.color(hex);
            root.studioHue = c.hsvHue >= 0 ? c.hsvHue : 0;
            root.studioSat = Math.max(0, Math.min(1, c.hsvSaturation));
            root.studioVal = Math.max(0, Math.min(1, c.hsvValue));
        }
    }

    function applyStudioHsv(h, s, v) {
        const nh = Math.max(0, Math.min(1, Number(h) || 0));
        const ns = Math.max(0, Math.min(1, Number(s) || 0));
        const nv = Math.max(0, Math.min(1, Number(v) || 0));
        root.studioHue = nh;
        root.studioSat = ns;
        root.studioVal = nv;
        root.studioHexError = "";
        const hex = Theme.colorToHex(Qt.hsva(nh, ns, nv, 1.0));
        root.studioHexInput = hex;
        if (root.colorStudioSlot === "accent") {
            root.hueVal = nh;
            root.satVal = ns;
            root.valVal = nv;
            if (root.shellState) root.shellState.applyCustomAccent(nh, ns, nv);
            else Theme.applyAccentHsv(nh, ns, nv);
        } else if (root.shellState) {
            root.shellState.setThemeColor(root.colorStudioSlot, hex);
        } else {
            Theme.setPaletteColor(root.colorStudioSlot, hex);
        }
    }

    function applyStudioHex(raw, shakeAnim) {
        const norm = Theme.normalizeHex(raw, "");
        if (norm === "") {
            root.studioHexError = "Invalid hex (use #RRGGBB)";
            if (shakeAnim) shakeAnim.restart();
            return false;
        }
        root.studioHexError = "";
        root.studioHexInput = norm;
        if (root.shellState) root.shellState.setThemeColor(root.colorStudioSlot, norm);
        else Theme.setPaletteColor(root.colorStudioSlot, norm);
        root.loadStudioSlot(root.colorStudioSlot);
        return true;
    }

    function isSlotCustomized(slot) {
        if (slot === "pillBg") return Theme.hasCustomPillBg;
        if (slot === "surfaceBg") return Theme.hasCustomSurfaceBg;
        if (slot === "surfaceRaised") return Theme.hasCustomSurfaceRaised;
        if (slot === "text") return Theme.hasCustomText;
        if (slot === "borderColor") return Theme.hasCustomBorderColor;
        if (slot === "accent") return Theme.customAccentActive;
        if (slot === "accent2") return Theme.customAccent2Active;
        return slot === "pillBg2" || slot === "surfaceBg2";
    }

    function syncPersonalizationFromShellState() {
        root.accentMode = Theme.accentMode;
        root.hueVal = Theme.hueVal;
        root.satVal = Theme.satVal;
        root.valVal = Theme.valVal;
        root.gradientAngle = Theme.gradientAngle;
        root.masterRatio = Theme.masterRatio;
        root.preserveSplit = Theme.preserveSplit;
        root.shadowRange = Theme.shadowRange;
        root.globalSurfaceTheme = Theme.surfaceTheme;
        if (root.shellState) {
            root.hideBarFullscreen = root.shellState.hideBarFullscreen;
            root.islandAutoHide = root.shellState.autoHideOnOverlap || root.shellState.hideBarFullscreen;
            root.islandCornerRadius = root.shellState.islandCornerRadius;
            root.barPosition = root.shellState.barPosition;
            root.topEdgeOffset = root.shellState.topEdgeOffset;
            root.activeBorderHighlight = root.shellState.activeBorderHighlight;
            if (root.shellState.activeProfile !== "") {
                root.profileNameInput = root.shellState.activeProfile;
            } else if (root.profileNameInput === "") {
                root.profileNameInput = "default";
            }
        }
        root.loadStudioSlot(root.colorStudioSlot);
    }

    function applyExternalSearch(query) {
        const q = (query || "").trim();
        if (searchInput && searchInput.text !== q) {
            searchInput.text = q;
        }
        root.searchQuery = q;
    }

    Connections {
        target: root.shellState
        function onThemeImportSeqChanged() {
            root.syncPersonalizationFromShellState();
        }
        function onLastProfileStatusChanged() {
            if (!root.shellState) return;
            root.themeExportStatus = root.shellState.lastProfileStatus;
            root.themeExportOk = root.shellState.lastProfileOk;
        }
        function onSettingsSpotlightChanged() {
            if (!root.shellState) return;
            root.applyExternalSearch(root.shellState.settingsSpotlight || "");
        }
    }

    Connections {
        target: Theme
        function onWallpaperColorEnabledChanged() {
            root.loadStudioSlot(root.colorStudioSlot);
        }
    }

    Component.onCompleted: {
        root.syncDisplayFromCompositor();
        root.syncPersonalizationFromShellState();
        if (root.currentPage === "") {
            root.openPage(root.shellState ? (root.shellState.settingsPage || "home") : "home");
        }
        if (root.shellState && root.shellState.settingsSpotlight) {
            root.applyExternalSearch(root.shellState.settingsSpotlight);
        }
    }

    Component.onDestruction: SoundService.stopPreviewAmbient()
    onVisibleChanged: {
        if (!visible) {
            SoundService.stopPreviewAmbient();
            if (hasPendingDisplayChanges) resetDisplayDraft();
        }
    }

    Connections {
        target: CompositorService
        function onMonitorDetailsChanged() {
            root.syncDisplayFromCompositor();
        }
    }

    function syncDisplayFromCompositor() {
        const details = CompositorService.monitorDetails;
        if (!details || details.length === 0) return;
        const hadPending = hasPendingDisplayChanges;
        let mon = details[0];
        for (let i = 0; i < details.length; ++i) {
            if (details[i].focused) { mon = details[i]; break; }
        }
        activeMonitorName = mon.name || "eDP-1";

        const opts = [];
        const modeMap = {};
        const ratesByRes = {};
        const modes = mon.availableModes || [];
        let maxW = Number(mon.width || 0);
        let maxH = Number(mon.height || 0);
        for (let i = 0; i < modes.length; ++i) {
            const raw = modes[i]; // e.g. "1920x1080@60.05Hz"
            const m = raw.match(/^(\d+)x(\d+)@([\d.]+)Hz$/);
            if (!m) continue;
            const w = parseInt(m[1], 10);
            const h = parseInt(m[2], 10);
            if (w * h > maxW * maxH) {
                maxW = w;
                maxH = h;
            }
            const label = m[1] + " × " + m[2];
            const hz = Math.round(parseFloat(m[3]));
            if (!ratesByRes[label]) ratesByRes[label] = [];
            if (ratesByRes[label].indexOf(hz) === -1) ratesByRes[label].push(hz);
            if (!modeMap[label]) {
                modeMap[label] = m[1] + "x" + m[2] + "@" + hz;
                opts.push(label);
            }
        }
        if (maxW > 0 && maxH > 0) {
            maxDisplayWidth = maxW;
            maxDisplayHeight = maxH;
            maxDisplayRes = maxW + " × " + maxH;
        }
        const standardRes = [
            "2560 × 1600",
            "2560 × 1440",
            "1920 × 1200",
            "1920 × 1080",
            "1600 × 900",
            "1366 × 768",
            "1280 × 720"
        ];
        for (let i = 0; i < standardRes.length; ++i) {
            const label = standardRes[i];
            const parts = label.split(" × ");
            const w = parseInt(parts[0], 10);
            const h = parseInt(parts[1], 10);
            if (maxW > 0 && maxH > 0 && (w > maxW || h > maxH)) continue;
            if (opts.indexOf(label) === -1) {
                opts.push(label);
                modeMap[label] = label.replace(" × ", "x") + "@60";
                ratesByRes[label] = [60];
            }
        }
        displayResOptions = opts;
        displayModeMap = modeMap;
        displayRatesByRes = ratesByRes;
        if (mon.width && mon.height) {
            const curLabel = mon.width + " × " + mon.height;
            if (opts.indexOf(curLabel) === -1) opts.unshift(curLabel);
            displayRes = curLabel;
        }
        const curHz = mon.refreshRate ? Math.round(Number(mon.refreshRate)) : 60;
        updateRefreshOptionsForRes(displayRes, curHz, false);
        const s = Number(mon.scale || 1);
        if (Math.abs(s - 1.0) < 0.05) displayScale = "100%";
        else if (Math.abs(s - 1.25) < 0.05) displayScale = "125% (Recommended)";
        else if (Math.abs(s - 1.5) < 0.05) displayScale = "150%";
        else if (Math.abs(s - 2.0) < 0.05) displayScale = "200%";
        else displayScale = Math.round(s * 100) + "%";

        const tr = Number(mon.transform || 0);
        displayOrient = (tr === 1 || tr === 3) ? "Portrait" : "Landscape";

        if (!hadPending) {
            resetDisplayDraft();
        }
    }

    function resetDisplayDraft() {
        draftDisplayScale = displayScale;
        draftDisplayRes = displayRes;
        draftDisplayOrient = displayOrient;
        updateRefreshOptionsForRes(displayRes, 0, true);
        draftDisplayRefreshRate = displayRefreshRate;
    }

    function updateRefreshOptionsForRes(resLabel, preferredHz, isDraft) {
        const rawRates = displayRatesByRes[resLabel];
        const rates = rawRates && rawRates.length > 0 ? rawRates.slice() : [60];
        if (preferredHz > 0 && rates.indexOf(preferredHz) === -1) {
            rates.push(preferredHz);
        }
        rates.sort((a, b) => b - a);
        const formatted = [];
        for (let i = 0; i < rates.length; ++i) {
            formatted.push(rates[i] + " Hz");
        }
        displayRefreshOptions = formatted;
        if (isDraft) {
            if (preferredHz > 0) {
                draftDisplayRefreshRate = preferredHz + " Hz";
            } else if (formatted.indexOf(draftDisplayRefreshRate) === -1 && formatted.length > 0) {
                draftDisplayRefreshRate = formatted[0];
            }
        } else {
            if (preferredHz > 0) {
                displayRefreshRate = preferredHz + " Hz";
            } else if (formatted.indexOf(displayRefreshRate) === -1 && formatted.length > 0) {
                displayRefreshRate = formatted[0];
            }
        }
    }

    function focusedMonitorSummary() {
        const details = CompositorService.monitorDetails;
        if (!details || details.length === 0) return root.displayRes + " (Wayland DRM)";
        let mon = details[0];
        for (let i = 0; i < details.length; ++i) {
            if (details[i].focused) { mon = details[i]; break; }
        }
        const res = (mon.width && mon.height) ? (mon.width + " × " + mon.height) : root.displayRes;
        const hz = mon.refreshRate ? (" @ " + Math.round(Number(mon.refreshRate)) + "Hz") : "";
        return res + hz + " (Wayland DRM)";
    }

    function formatPowerProfile(prof) {
        if (prof === "power-saver") return "Power Saver";
        if (prof === "performance") return "Performance";
        return "Balanced";
    }

    function powerProfileKey(label) {
        if (label === "Power Saver") return "power-saver";
        if (label === "Performance") return "performance";
        return "balanced";
    }

    function cyclePowerProfile() {
        const cur = PowerService.powerProfile;
        if (cur === "power-saver") PowerService.setPowerProfile("balanced");
        else if (cur === "balanced") PowerService.setPowerProfile("performance");
        else PowerService.setPowerProfile("power-saver");
    }

    function applyDisplayChange() {
        let targetRes = draftDisplayRes;
        const parts = targetRes.split(" × ");
        const reqW = parseInt(parts[0], 10);
        const reqH = parseInt(parts[1], 10);
        if (maxDisplayWidth > 0 && maxDisplayHeight > 0 && (reqW > maxDisplayWidth || reqH > maxDisplayHeight)) {
            targetRes = maxDisplayRes;
            draftDisplayRes = maxDisplayRes;
        }
        displayRes = targetRes;
        displayRefreshRate = draftDisplayRefreshRate;
        displayScale = draftDisplayScale;
        displayOrient = draftDisplayOrient;

        const hzNum = parseInt(displayRefreshRate, 10) || 60;
        const mode = displayRes.replace(" × ", "x") + "@" + hzNum;
        const scaleNum = parseFloat(displayScale) / 100.0;
        const scale = isNaN(scaleNum) ? 1 : scaleNum;
        const transform = (displayOrient === "Portrait") ? 1 : 0;
        CompositorService.applyDisplaySettings(activeMonitorName, mode, scale, transform);
    }

    // Sound
    property bool soundMute: true

    // Network / Wi-Fi / VPN
    property bool wifiShowPrompt: false
    property bool wifiPromptHidden: false
    property string wifiPromptSsid: ""
    property string wifiPromptPassword: ""
    property bool airplaneMode: false
    property string dnsProvider: "Cloudflare (1.1.1.1)"
    property bool meteredConn: false
    property bool vpnActive: false
    property string vpnEndpoint: "wg.paithon.dev:51820"
    property string vpnDns: "1.1.1.1"
    property bool vpnAutostart: true
    property bool vpnKillSwitch: false

    // Personalization / Island / Hyprland / Layouts / Decoration / Fonts / Animations
    property bool islandAutoHide: false
    property bool kawaseBlur: true
    property string globalSurfaceTheme: "OLED Pure"
    property bool activeBorderHighlight: true
    property string islandCornerRadius: "26px (Default)"
    property string barPosition: "top"
    property bool topEdgeOffset: true
    property bool hideBarFullscreen: false
    property string windowGapsPreset: "Balanced (6 / 12)"
    property bool blurBezierGlobal: true
    property string activeLayout: "dwindle"
    property int masterRatio: 55
    property bool preserveSplit: true
    property int cornerRounding: 14
    property int borderSize: 2
    property int activeOpacity: 100
    property int shadowRange: 24
    property string activeBorderHex: "#e8e8e8"
    property bool dropShadow: true
    property bool dimInactive: false
    property bool blurBehindIsland: true
    property bool zeroDeadAnims: true

    // Colors & Fonts
    property string accentMode: "Solid"
    property real hueVal: 0.0
    property real satVal: 0.0
    property real valVal: 0.92
    property int gradientAngle: 135
    property string colorStudioSlot: "accent"
    property real studioHue: 0.0
    property real studioSat: 0.0
    property real studioVal: 0.92
    property string studioHexInput: "#ffffff"
    property string studioHexError: ""
    property bool studioExpanded: false
    readonly property var studioGroups: [
        { id: "shell", label: "Shell Chrome", desc: "Dynamic Island, Popover, Context Menu & Sidebars", slot1: "pillBg", slot2: "pillBg2" },
        { id: "surface", label: "Surface Canvas", desc: "Expanded App Workspace, Detached Window & Modals", slot1: "surfaceBg", slot2: "surfaceBg2" },
        { id: "accent", label: "Accent & Focus", desc: "Active buttons, switches, sliders & Hyprland border", slot1: "accent", slot2: "accent2" },
        { id: "raised", label: "Raised Chrome", desc: "Input wells, ghost buttons, drag strips & chips", slot1: "surfaceRaised", slot2: "" },
        { id: "text", label: "Primary Text", desc: "Headings, labels & derived secondary/muted ink", slot1: "text", slot2: "" },
        { id: "border", label: "Border Tint", desc: "Subtle 1px hairlines & inactive window borders", slot1: "borderColor", slot2: "" }
    ]

    function studioGroupForSlot(slot) {
        for (let i = 0; i < studioGroups.length; ++i) {
            if (studioGroups[i].slot1 === slot || studioGroups[i].slot2 === slot) {
                return studioGroups[i];
            }
        }
        return studioGroups[2];
    }

    // Themes
    property bool exportIncHypr: true
    property bool exportIncPalette: true
    property string themeExportStatus: ""
    property bool themeExportOk: true
    property string themeImportInput: ""
    property string profileNameInput: "default"

    readonly property var navItems: [
        { key: "home", label: "Home", icon: "home", group: "", sub: false },
        { key: "system", label: "System", icon: "settings", group: "system", sub: false, hasChildren: true },
        { key: "display", label: "Display", icon: "", group: "system", sub: true },
        { key: "sound", label: "Sound & Audio", icon: "", group: "system", sub: true },
        { key: "performance", label: "Performance", icon: "", group: "system", sub: true },
        { key: "updates", label: "Updates", icon: "", group: "system", sub: true },
        { key: "backup", label: "Backup & Restore", icon: "", group: "system", sub: true },
        { key: "storage", label: "Storage", icon: "", group: "system", sub: true },
        { key: "accessibility", label: "Accessibility", icon: "", group: "system", sub: true },
        { key: "network", label: "Network & internet", icon: "wifi", group: "network", sub: false, hasChildren: true },
        { key: "wifi", label: "Wi-Fi", icon: "", group: "network", sub: true },
        { key: "vpn", label: "VPN & Proxy", icon: "", group: "network", sub: true },
        { key: "discord_rpc", label: "Discord RPC", icon: "", group: "network", sub: true },
        { key: "personalization", label: "Personalization", icon: "palette", group: "personalization", sub: false, hasChildren: true },
        { key: "appearance", label: "Appearance", icon: "", group: "personalization", sub: true },
        { key: "keybind", label: "Binding", icon: "", group: "personalization", sub: true },
        { key: "layout", label: "Layout", icon: "", group: "personalization", sub: true },
        { key: "lockscreen", label: "Lock Screen", icon: "", group: "personalization", sub: true },
        { key: "about", label: "About", icon: "info", group: "", sub: false }
    ]

    function isGroupOpen(group) {
        if (group === "system") return systemOpen;
        if (group === "network") return networkOpen;
        if (group === "personalization") return personalizationOpen;
        return true;
    }

    function toggleGroup(group) {
        if (group === "system") systemOpen = !systemOpen;
        else if (group === "network") networkOpen = !networkOpen;
        else if (group === "personalization") personalizationOpen = !personalizationOpen;
    }

    function resolvePageKey(pageKey) {
        const legacyMap = {
            "power": "performance",
            "fonts": "appearance",
            "decoration": "appearance",
            "animations": "appearance",
            "wallpaper": "appearance",
            "themes": "appearance",
            "cursors": "cursor",
            "pointer": "cursor",
            "hyprland": "layout",
            "layouts": "layout",
            "island": "layout",
            "binding": "keybind",
            "lock": "lockscreen",
            "lock_screen": "lockscreen"
        };
        return legacyMap[pageKey] || pageKey || "home";
    }

    function openPage(pageKey) {
        const resolved = resolvePageKey(pageKey);
        if (currentPage === resolved) return;
        if (resolved !== "lockscreen") SoundService.stopPreviewAmbient();
        if (resolved !== "display" && hasPendingDisplayChanges) resetDisplayDraft();
        if (!root.loadedPages[resolved]) {
            const next = Object.assign({}, root.loadedPages);
            next[resolved] = true;
            root.loadedPages = next;
        }
        if (resolved === "updates") {
            if (!PackageService.shellCheckedOnce) PackageService.checkShellUpdate();
            PackageService.checkHyprSyncStatus();
            PackageService.checkRequiredDeps();
            BackupService.refreshSystemBackups();
        }
        if (resolved === "cursor") {
            if (!Theme.reduceMotion || !root._cursorPagePrimed) {
                root._cursorPagePrimed = true;
                CursorService.checkDeps();
                CursorService.refreshPreviews();
                PackageService.checkRequiredDeps();
            }
        }
        if (resolved === "backup") BackupService.refreshAll();
        if (resolved === "storage") StorageService.scanIfStale();
        if (resolved === "about") TelemetryService.refreshSpecs();
        if (resolved === "keybind") KeybindService.refresh();
        else if (keybindEditorLoader.item && keybindEditorLoader.item.open) keybindEditorLoader.item.close();
        currentPage = resolved;
        if (root.shellState && root.shellState.settingsPage !== resolved) root.shellState.settingsPage = resolved;
        if (["display", "sound", "performance", "updates", "backup", "storage", "accessibility"].indexOf(resolved) !== -1) systemOpen = true;
        if (["wifi", "vpn", "discord_rpc"].indexOf(resolved) !== -1) networkOpen = true;
        if (["appearance", "cursor", "keybind", "layout", "lockscreen"].indexOf(resolved) !== -1) personalizationOpen = true;
        pageFlick.contentY = 0;
        pageInAnim.restart();
    }

    function isSpotlightActive() {
        return root.activeSearchQuery !== "";
    }

    function matchesSpotlight(title, subtitle, extraKeywords) {
        if (!root.isSpotlightActive()) return true;
        return SettingsSearchService.matchesText(root.activeSearchQuery, title, subtitle, extraKeywords);
    }

    onSearchQueryChanged: {
        const q = searchQuery.trim();
        if (q !== "") {
            if (!SettingsSearchService.pageHasMatch(currentPage, q)) {
                const hits = SettingsSearchService.search(q);
                if (hits.length > 0) {
                    openPage(hits[0].page);
                }
            }
        }
    }

    function matchesSearch(item) {
        const q = searchQuery.trim();
        if (q === "") return true;
        if (item.label.toLowerCase().indexOf(q.toLowerCase()) !== -1) return true;
        if (SettingsSearchService.pageHasMatch(item.key, q)) return true;
        if (item.key === "appearance" && SettingsSearchService.pageHasMatch("cursor", q)) return true;
        if (item.hasChildren && item.group !== "") {
            for (let i = 0; i < navItems.length; ++i) {
                const child = navItems[i];
                if (child.sub && child.group === item.group) {
                    if (child.label.toLowerCase().indexOf(q.toLowerCase()) !== -1 || SettingsSearchService.pageHasMatch(child.key, q)) {
                        return true;
                    }
                    if (child.key === "appearance" && SettingsSearchService.pageHasMatch("cursor", q)) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    // Inline reusable components matching settings.html CSS
    component SectionLabel: Text {
        Layout.fillWidth: true
        Layout.topMargin: 4
        font.family: Theme.fontSans
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: Theme.textMuted
        elide: Text.ElideRight
        opacity: root.isSpotlightActive() ? 0.55 : 1.0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }

    component SettingGroup: Rectangle {
        default property alias rows: groupCol.data
        property bool animateHeight: true
        Layout.fillWidth: true
        implicitHeight: groupCol.implicitHeight
        radius: 12
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle
        clip: true
        Behavior on implicitHeight { enabled: animateHeight; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: groupCol
            width: parent.width
            spacing: 0
        }
    }

    component PresetCard: Rectangle {
        id: pCard
        property string title: ""
        property string subtitle: ""
        property string badge: ""
        property string iconName: ""
        property string searchKeywords: ""
        property bool active: false
        readonly property bool spotActive: root.isSpotlightActive()
        readonly property bool spotMatched: !spotActive || root.matchesSpotlight(title, subtitle, searchKeywords)
        signal triggered()

        Layout.fillWidth: true
        implicitHeight: 74
        radius: 11
        clip: true
        opacity: spotMatched ? 1.0 : 0.28
        color: (spotActive && spotMatched)
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
            : (active ? Theme.cardHover : ((pCard.enabled && pMouse.containsMouse) ? Theme.cardHover : Theme.cardBg))
        border.width: (active || (spotActive && spotMatched)) ? 2 : 1
        border.color: (active || (spotActive && spotMatched)) ? Theme.accent : ((pCard.enabled && pMouse.containsMouse) ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
        scale: (pCard.enabled && pMouse.pressed) ? 0.98 : 1.0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 11
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                SvgIcon {
                    visible: pCard.iconName !== ""
                    sourceName: pCard.iconName
                    iconSize: 15
                    color: pCard.active ? Theme.accent : Theme.textSub
                }
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: pCard.title
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Rectangle {
                    visible: pCard.active || pCard.badge !== ""
                    implicitWidth: badgeLbl.implicitWidth + 10
                    height: 18
                    radius: 9
                    clip: true
                    color: pCard.active ? Theme.accent : Theme.pillBg
                    ThemeGradientFill {
                        anchors.fill: parent
                        enabled: pCard.active && Theme.accentGradientEnabled
                        color1: Theme.accent
                        colorMid: Theme.accentMid
                        color2: Theme.accent2
                        cornerRadius: 9
                    }
                    Text {
                        id: badgeLbl
                        anchors.centerIn: parent
                        text: pCard.active ? "Active" : pCard.badge
                        color: pCard.active ? Theme.accentFg : Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: pCard.subtitle
                color: Theme.textSub
                font.family: Theme.fontSans
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: pMouse
            anchors.fill: parent
            enabled: pCard.enabled
            hoverEnabled: pCard.enabled
            cursorShape: pCard.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: pCard.triggered()
        }
    }

    component AdvancedSection: Rectangle {
        id: advRoot
        property bool expanded: false
        property string title: "Advanced Settings"
        property string subtitle: "Fine-tune raw parameters & custom overrides"
        default property alias content: advCol.data

        Layout.fillWidth: true
        implicitHeight: advHeader.height + (expanded ? advBody.implicitHeight : 0)
        radius: 12
        color: Theme.cardBg
        border.width: 1
        border.color: (advRoot.enabled && advMouse.containsMouse) ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40) : Theme.borderSubtle
        scale: (advRoot.enabled && advMouse.pressed) ? 0.99 : 1.0
        clip: true
        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Rectangle {
            id: advHeader
            width: parent.width
            height: 50
            color: (advRoot.enabled && advMouse.containsMouse) ? Theme.cardHover : "transparent"
            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10
                SvgIcon {
                    sourceName: "settings"
                    iconSize: 15
                    color: (advRoot.enabled && advMouse.containsMouse) ? Theme.text : Theme.textMuted
                    Behavior on color { ColorAnimation { duration: 140 } }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: advRoot.title; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text { text: advRoot.subtitle; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                Rectangle {
                    implicitWidth: advToggleLbl.implicitWidth + 16
                    height: 24
                    radius: 12
                    color: (advRoot.enabled && advMouse.containsMouse) ? Theme.surfaceRaised : Theme.pillBg
                    border.width: 1
                    border.color: (advRoot.enabled && advMouse.containsMouse) ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Behavior on border.color { ColorAnimation { duration: 140 } }
                    Text {
                        id: advToggleLbl
                        anchors.centerIn: parent
                        text: advRoot.expanded ? "Hide ▴" : "Show ▾"
                        color: (advRoot.enabled && advMouse.containsMouse) ? Theme.text : Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }
                }
            }

            MouseArea {
                id: advMouse
                anchors.fill: parent
                enabled: advRoot.enabled
                hoverEnabled: advRoot.enabled
                cursorShape: advRoot.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: advRoot.expanded = !advRoot.expanded
            }
        }

        Item {
            id: advBody
            y: advHeader.height
            width: parent.width
            implicitHeight: advCol.implicitHeight
            visible: advRoot.expanded
            Rectangle { width: parent.width; height: 1; color: Theme.borderSubtle }
            ColumnLayout {
                id: advCol
                width: parent.width
                spacing: 0
            }
        }
    }

    component SettingRow: Item {
        id: sRow
        property string iconName: ""
        property color iconColor: Theme.textSub
        property string title: ""
        property string subtitle: ""
        property string searchKeywords: ""
        property bool showDivider: true
        readonly property bool spotActive: root.isSpotlightActive()
        readonly property bool spotMatched: !spotActive || root.matchesSpotlight(title, subtitle, searchKeywords)
        default property alias control: ctrlSlot.data

        Layout.fillWidth: true
        implicitHeight: Math.max(54, rowLayout.implicitHeight + 20)
        clip: true
        opacity: spotMatched ? 1.0 : 0.28
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 10
            color: (sRow.spotActive && sRow.spotMatched) ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : "transparent"
            border.width: (sRow.spotActive && sRow.spotMatched) ? 1 : 0
            border.color: (sRow.spotActive && sRow.spotMatched) ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) : "transparent"
            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            visible: sRow.showDivider
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Theme.borderSubtle
        }

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 12

            Rectangle {
                visible: sRow.iconName !== ""
                width: 30; height: 30; radius: 8
                color: Theme.surfaceRaised
                border.width: 1; border.color: Theme.borderSubtle
                SvgIcon {
                    anchors.centerIn: parent
                    sourceName: sRow.iconName
                    iconSize: 15
                    color: sRow.iconColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: sRow.title
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Text {
                    visible: sRow.subtitle !== ""
                    Layout.fillWidth: true
                    text: sRow.subtitle
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                id: ctrlSlot
                spacing: 8
            }
        }
    }

    component HubCard: Rectangle {
        id: hCard
        property string iconName: ""
        property string title: ""
        property string subtitle: ""
        property string pillText: ""
        property string searchKeywords: ""
        readonly property bool spotActive: root.isSpotlightActive()
        readonly property bool spotMatched: !spotActive || root.matchesSpotlight(title, subtitle, searchKeywords)
        signal triggered()

        Layout.fillWidth: true
        height: 62
        radius: 12
        clip: true
        opacity: spotMatched ? 1.0 : 0.28
        color: (spotActive && spotMatched)
            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
            : (hMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
        border.width: (spotActive && spotMatched) ? 1.5 : 1
        border.color: (spotActive && spotMatched)
            ? Theme.accent
            : (hMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
        scale: hMouse.pressed ? 0.988 : 1.0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            spacing: 12

            Rectangle {
                width: 32; height: 32; radius: 8
                color: Theme.surfaceRaised
                border.width: 1; border.color: hMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                Behavior on border.color { ColorAnimation { duration: 140 } }
                SvgIcon {
                    visible: hCard.iconName !== ""
                    anchors.centerIn: parent
                    sourceName: hCard.iconName
                    iconSize: 16
                    color: Theme.text
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2
                Text { Layout.fillWidth: true; text: hCard.title; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: hCard.subtitle; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; elide: Text.ElideRight }
            }

            Rectangle {
                visible: hCard.pillText !== ""
                height: 24
                implicitWidth: pillLbl.implicitWidth + 18
                radius: 12
                color: Theme.surfaceRaised
                border.width: 1; border.color: hMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                Behavior on border.color { ColorAnimation { duration: 140 } }
                Text { id: pillLbl; anchors.centerIn: parent; text: hCard.pillText; color: hMouse.containsMouse ? Theme.text : Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 10; Behavior on color { ColorAnimation { duration: 140 } } }
            }

            SvgIcon {
                sourceName: "chevron-right"
                iconSize: 14
                color: hMouse.containsMouse ? Theme.text : Theme.textMuted
                transform: Translate {
                    x: hMouse.containsMouse ? 2 : 0
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
                Behavior on color { ColorAnimation { duration: 140 } }
            }
        }

        MouseArea {
            id: hMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hCard.triggered()
        }
    }

    component CtrlSwitch: Rectangle {
        id: sw
        property bool checked: false
        signal toggled(bool nextVal)

        width: 38
        height: 22
        radius: 11
        clip: true
        color: checked ? Theme.accent : ((sw.enabled && swMouse.containsMouse) ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.22) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.14))
        border.width: 1
        border.color: checked ? Theme.accent : ((sw.enabled && swMouse.containsMouse) ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
        scale: (sw.enabled && swMouse.pressed) ? 0.94 : 1.0
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        ThemeGradientFill {
            anchors.fill: parent
            anchors.margins: 1
            enabled: sw.checked && Theme.accentGradientEnabled
            color1: Theme.accent
            colorMid: Theme.accentMid
            color2: Theme.accent2
            cornerRadius: 10
        }

        Rectangle {
            width: 16; height: 16; radius: 8
            y: 3
            x: sw.checked ? 19 : 3
            color: sw.checked ? Theme.accentFg : Theme.text
            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: swMouse
            anchors.fill: parent
            enabled: sw.enabled
            hoverEnabled: sw.enabled
            cursorShape: sw.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: sw.toggled(!sw.checked)
        }
    }

    component CtrlTickBox: Rectangle {
        id: tb
        property bool checked: false
        signal toggled(bool nextVal)

        width: 18
        height: 18
        radius: 5
        color: checked ? Theme.accent : (tbMouse.containsMouse ? Theme.cardHover : "transparent")
        border.width: 1
        border.color: checked ? Theme.accent : (tbMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5) : Theme.textMuted)
        scale: tbMouse.pressed ? 0.92 : 1.0
        Behavior on color { ColorAnimation { duration: 130 } }
        Behavior on border.color { ColorAnimation { duration: 130 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        SvgIcon {
            anchors.centerIn: parent
            visible: tb.checked
            sourceName: "check"
            iconSize: 11
            color: Theme.accentFg
        }

        MouseArea {
            id: tbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.toggled(!tb.checked)
        }
    }

    component CtrlSlider: RowLayout {
        id: cSlider
        property real from: 0
        property real to: 100
        property real value: 50
        property string unit: "%"
        property bool showValue: true
        property int sliderWidth: 136
        property bool fillSlider: false
        property real stepSize: 0
        signal moved(real newVal)

        spacing: 10
        Slider {
            id: sl
            Layout.preferredWidth: cSlider.fillSlider ? -1 : cSlider.sliderWidth
            Layout.fillWidth: cSlider.fillSlider
            implicitHeight: 22
            padding: 0
            from: cSlider.from
            to: cSlider.to
            value: cSlider.value
            stepSize: cSlider.stepSize
            onMoved: cSlider.moved(cSlider.stepSize > 0 && cSlider.stepSize < 1 ? value : Math.round(value))

            HoverHandler {
                cursorShape: cSlider.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            }

            background: Rectangle {
                x: sl.leftPadding
                y: sl.topPadding + sl.availableHeight / 2 - height / 2
                implicitWidth: cSlider.sliderWidth
                implicitHeight: 6
                width: sl.availableWidth
                height: 6
                radius: 3
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.14)
                clip: true

                Rectangle {
                    width: Math.max(0, Math.min(parent.width, sl.visualPosition * parent.width))
                    height: parent.height
                    radius: 3
                    clip: true
                    color: Theme.accent
                    ThemeGradientFill {
                        anchors.fill: parent
                        enabled: Theme.accentGradientEnabled
                        color1: Theme.accent
                        colorMid: Theme.accentMid
                        color2: Theme.accent2
                        cornerRadius: 3
                    }
                }
            }

            handle: Rectangle {
                x: sl.leftPadding + sl.visualPosition * (sl.availableWidth - width)
                y: sl.topPadding + sl.availableHeight / 2 - height / 2
                implicitWidth: 14
                implicitHeight: 14
                width: 14
                height: 14
                radius: 7
                color: Theme.accent
                border.width: 1
                border.color: Qt.rgba(0, 0, 0, 0.45)
                scale: sl.pressed ? 1.18 : (sl.hovered ? 1.08 : 1.0)
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
            }
        }
        Text {
            visible: cSlider.showValue
            Layout.preferredWidth: 42
            horizontalAlignment: Text.AlignRight
            text: Math.round(cSlider.value) + cSlider.unit
            color: Theme.textSub
            font.family: Theme.fontMono
            font.pixelSize: 11
        }
    }

    component HueSlider: Slider {
        id: hsl
        from: 0
        to: 1
        implicitHeight: 22
        padding: 0

        HoverHandler {
            cursorShape: hsl.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        background: Rectangle {
            x: hsl.leftPadding
            y: hsl.topPadding + hsl.availableHeight / 2 - height / 2
            implicitWidth: 180
            implicitHeight: 12
            width: hsl.availableWidth
            height: 12
            radius: 6
            clip: true
            border.width: 1
            border.color: Theme.borderSubtle
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.00; color: "#ff0000" }
                GradientStop { position: 0.17; color: "#ffff00" }
                GradientStop { position: 0.33; color: "#00ff00" }
                GradientStop { position: 0.50; color: "#00ffff" }
                GradientStop { position: 0.67; color: "#0000ff" }
                GradientStop { position: 0.83; color: "#ff00ff" }
                GradientStop { position: 1.00; color: "#ff0000" }
            }
        }

        handle: Rectangle {
            x: hsl.leftPadding + hsl.visualPosition * (hsl.availableWidth - width)
            y: hsl.topPadding + hsl.availableHeight / 2 - height / 2
            implicitWidth: 16
            implicitHeight: 16
            width: 16
            height: 16
            radius: 8
            color: "#ffffff"
            border.width: 2
            border.color: "#000000"
            scale: hsl.pressed ? 1.18 : (hsl.hovered ? 1.08 : 1.0)
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
        }
    }

    component CtrlSelect: Rectangle {
        id: cSel
        property var options: []
        property string currentText: ""
        signal selected(string val)

        height: 30
        implicitWidth: Math.max(126, selLbl.implicitWidth + 32)
        radius: 8
        clip: true
        color: (cSel.enabled && selMouse.containsMouse) ? Theme.cardHover : Theme.surfaceRaised
        border.width: 1
        border.color: (cSel.enabled && selMouse.containsMouse) ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42) : Theme.borderSubtle
        scale: (cSel.enabled && selMouse.pressed) ? 0.96 : 1.0
        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 8
            spacing: 6
            Text {
                id: selLbl
                Layout.fillWidth: true
                text: cSel.currentText
                color: Theme.text
                font.family: Theme.fontSans
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            SvgIcon { sourceName: "chevron-right"; iconSize: 12; color: Theme.textMuted; rotation: 90 }
        }

        MouseArea {
            id: selMouse
            anchors.fill: parent
            enabled: cSel.enabled
            hoverEnabled: cSel.enabled
            cursorShape: cSel.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                const mw = Math.max(196, cSel.width);
                const pt = cSel.mapToItem(root, cSel.width - mw, cSel.height + 4);
                const opts = [];
                for (let i = 0; i < cSel.options.length; ++i) {
                    const optVal = cSel.options[i];
                    opts.push({
                        text: optVal,
                        checked: optVal === cSel.currentText,
                        action: () => cSel.selected(optVal)
                    });
                }
                settingsSelectMenu.menuWidth = mw;
                settingsSelectMenu.openAt(pt.x, pt.y, opts);
            }
        }
    }

    ContextMenu {
        id: settingsSelectMenu
        z: 250
    }

    component WallpaperLockBanner: Item {
        id: lockBanner
        property bool active: Theme.wallpaperColorEnabled
        property string message: ""
        property real collapseSpacing: 12

        Layout.fillWidth: true
        Layout.topMargin: active ? 0 : -collapseSpacing
        implicitHeight: active ? lockBox.implicitHeight : 0
        opacity: active ? 1.0 : 0.0
        clip: true

        Behavior on Layout.topMargin { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        Rectangle {
            id: lockBox
            width: parent.width
            implicitHeight: lockRow.implicitHeight + 20
            radius: 10
            color: Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.12)
            border.width: 1
            border.color: Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.38)
            clip: true

            RowLayout {
                id: lockRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 10
                spacing: 8

                SvgIcon {
                    sourceName: "lock"
                    iconSize: 14
                    color: Theme.info
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 1
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: lockBanner.message
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    component WallpaperColorCard: SettingGroup {
        id: wpColorCard
        animateHeight: false
        enabled: !Theme.wallpapersDisabled
        opacity: Theme.wallpapersDisabled ? 0.45 : 1.0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        readonly property string effectiveMode: (Theme.wallpaperColorMode === "Gradient" && !Theme.reduceMotion) ? "Gradient" : "Solid"
        readonly property var paletteSwatches: effectiveMode === "Gradient"
            ? Theme.wallpaperRefinedPalette
            : Theme.wallpaperExtractedColors

        SettingRow {
            showDivider: false
            iconName: "eye"
            title: "Adjust colors based on what you see"
            subtitle: Theme.wallpapersDisabled
                ? "Disabled while wallpapers are off — manual theme colors are active"
                : (Theme.wallpaperColorEnabled
                    ? (Theme.wallpaperColorBusy
                        ? "Analyzing active wallpaper palette..."
                        : (Theme.reduceMotion
                            ? "Active • Solid palette (Gradient disabled by Reduce motion~)"
                            : (Theme.wallpaperColorMode === "Gradient"
                                ? "Active • 10–12 wallpaper tones refined into smooth light/dark gradients"
                                : "Active • 3–5 prominent wallpaper colors analyzed for UI contrast")))
                    : "Match interface colors automatically to your active wallpaper")
            searchKeywords: "adjust colors based on what you see wallpaper adaptive dynamic solid gradient match palette"

            CtrlSwitch {
                checked: !Theme.wallpapersDisabled && Theme.wallpaperColorEnabled
                enabled: !Theme.wallpapersDisabled
                onToggled: (v) => {
                    if (root.shellState) root.shellState.setWallpaperColorEnabled(v);
                    else Theme.setWallpaperColorEnabled(v);
                }
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: (!Theme.wallpapersDisabled && Theme.wallpaperColorEnabled) ? wpExpandCol.implicitHeight : 0
            opacity: (!Theme.wallpapersDisabled && Theme.wallpaperColorEnabled) ? 1.0 : 0.0
            visible: implicitHeight > 0.5
            clip: true

            Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            ColumnLayout {
                id: wpExpandCol
                width: parent.width
                spacing: 0

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.borderSubtle
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: wpModeRow.implicitHeight + 20

                    RowLayout {
                        id: wpModeRow
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        spacing: 12

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: "Color Style"
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Theme.reduceMotion
                                    ? "Gradient disabled by Reduce motion~"
                                    : (Theme.wallpaperColorMode === "Gradient"
                                        ? "10–12 balanced light/dark spectrum stops"
                                        : "3–5 prominent colors analyzed for solid UI roles")
                                color: Theme.textSub
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            id: wpSegTrack
                            width: 176
                            height: 30
                            radius: 9
                            clip: true
                            color: Theme.pillBg
                            border.width: 1
                            border.color: Theme.borderSubtle

                            Rectangle {
                                y: 2
                                x: wpColorCard.effectiveMode === "Gradient" ? (wpSegTrack.width / 2) : 2
                                width: wpSegTrack.width / 2 - 2
                                height: wpSegTrack.height - 4
                                radius: 7
                                color: Theme.surfaceRaised
                                border.width: 1
                                border.color: Theme.borderSubtle
                                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            }

                            Row {
                                anchors.fill: parent
                                Item {
                                    width: wpSegTrack.width / 2
                                    height: wpSegTrack.height
                                    clip: true
                                    scale: wpSolidMouse.pressed ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Solid"
                                        color: wpColorCard.effectiveMode === "Solid" ? Theme.text : (wpSolidMouse.containsMouse ? Theme.text : Theme.textSub)
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        font.weight: wpColorCard.effectiveMode === "Solid" ? Font.DemiBold : Font.Medium
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                    }
                                    MouseArea {
                                        id: wpSolidMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.shellState) root.shellState.setWallpaperColorMode("Solid");
                                            else Theme.setWallpaperColorMode("Solid");
                                        }
                                    }
                                }
                                Item {
                                    width: wpSegTrack.width / 2
                                    height: wpSegTrack.height
                                    clip: true
                                    enabled: !Theme.reduceMotion
                                    opacity: Theme.reduceMotion ? 0.40 : 1.0
                                    scale: (!Theme.reduceMotion && wpGradMouse.pressed) ? 0.94 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Gradient"
                                        color: wpColorCard.effectiveMode === "Gradient" ? Theme.text : ((!Theme.reduceMotion && wpGradMouse.containsMouse) ? Theme.text : Theme.textSub)
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        font.weight: wpColorCard.effectiveMode === "Gradient" ? Font.DemiBold : Font.Medium
                                        Behavior on color { ColorAnimation { duration: 140 } }
                                    }
                                    MouseArea {
                                        id: wpGradMouse
                                        anchors.fill: parent
                                        enabled: !Theme.reduceMotion
                                        hoverEnabled: !Theme.reduceMotion
                                        cursorShape: !Theme.reduceMotion ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                        onClicked: {
                                            if (Theme.reduceMotion) return;
                                            if (root.shellState) root.shellState.setWallpaperColorMode("Gradient");
                                            else Theme.setWallpaperColorMode("Gradient");
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: wpSwatchStrip.implicitHeight + 12

                    Rectangle {
                        id: wpSwatchStrip
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        implicitHeight: 34
                        radius: 9
                        clip: true
                        color: Theme.pillBg
                        border.width: 1
                        border.color: Theme.borderSubtle

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 6

                            Row {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                clip: true
                                spacing: 3
                                Repeater {
                                    model: wpColorCard.paletteSwatches
                                    delegate: Rectangle {
                                        required property string modelData
                                        width: Theme.wallpaperColorMode === "Gradient" ? 14 : 22
                                        height: 18
                                        radius: 5
                                        clip: true
                                        color: modelData
                                        border.width: 1
                                        border.color: Theme.borderSubtle
                                        Behavior on color { ColorAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }

                            Text {
                                Layout.minimumWidth: 0
                                text: Theme.wallpaperColorBusy
                                    ? "Analyzing..."
                                    : (wpColorCard.paletteSwatches.length + " tones" + (Theme.wallpaperColorMode === "Gradient" ? (" • " + Math.round(Theme.targetGradientAngle) + "°") : ""))
                                color: Theme.textSub
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }

    component CtrlBtn: Rectangle {
        id: cBtn
        property string text: ""
        property string iconName: ""
        property bool ghost: false
        property bool danger: false
        signal clicked()

        height: 30
        implicitWidth: Math.max(30, btnRow.implicitWidth + (cBtn.text !== "" ? 22 : 14))
        radius: 8
        clip: true
        color: danger
            ? (ghost
                ? (bMouse.containsMouse && cBtn.enabled ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.20) : Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.10))
                : Theme.danger)
            : (ghost ? (bMouse.containsMouse && cBtn.enabled ? Theme.cardHover : Theme.surfaceRaised) : Theme.accent)
        border.width: 1
        border.color: danger
            ? (ghost ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, (bMouse.containsMouse && cBtn.enabled) ? 0.70 : 0.40) : Theme.danger)
            : (ghost ? (bMouse.containsMouse && cBtn.enabled ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle) : Theme.accent)
        opacity: !cBtn.enabled ? 0.45 : (bMouse.containsMouse && !ghost ? 0.88 : 1.0)
        scale: (bMouse.pressed && cBtn.enabled) ? 0.96 : 1.0

        Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        ThemeGradientFill {
            anchors.fill: parent
            anchors.margins: 1
            enabled: !cBtn.ghost && !cBtn.danger && Theme.accentGradientEnabled
            color1: Theme.accent
            colorMid: Theme.accentMid
            color2: Theme.accent2
            cornerRadius: 7
        }

        RowLayout {
            id: btnRow
            anchors.centerIn: parent
            spacing: 6
            SvgIcon {
                visible: cBtn.iconName !== ""
                sourceName: cBtn.iconName
                iconSize: 13
                color: cBtn.danger ? (cBtn.ghost ? Theme.dangerText : "#ffffff") : (cBtn.ghost ? Theme.text : Theme.accentFg)
            }
            Text {
                id: btnLbl
                visible: cBtn.text !== ""
                text: cBtn.text
                color: cBtn.danger ? (cBtn.ghost ? Theme.dangerText : "#ffffff") : (cBtn.ghost ? Theme.text : Theme.accentFg)
                font.family: Theme.fontSans
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
        }

        MouseArea {
            id: bMouse
            anchors.fill: parent
            enabled: cBtn.enabled
            hoverEnabled: true
            cursorShape: cBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: cBtn.clicked()
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Left Sidebar
        Rectangle {
            Layout.preferredWidth: 248
            Layout.fillHeight: true
            color: Theme.pillBg
            bottomLeftRadius: (root.shellState && root.shellState.detachedApp === "settings") ? 13 : ((root.shellState && root.shellState.islandApp === "settings" && root.shellState.barPosition !== "bottom") ? 17 : 0)
            topLeftRadius: (root.shellState && root.shellState.islandApp === "settings" && root.shellState.barPosition === "bottom") ? 17 : 0

            ThemeGradientFill {
                anchors.fill: parent
                enabled: Theme.shellGradientEnabled
                color1: Theme.pillBg
                colorMid: Theme.pillBgMid
                color2: Theme.pillBg2
                cornerRadius: 0
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: Theme.borderSubtle
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                // Profile Header
                RowLayout {
                    id: profileHeader
                    readonly property string currentUser: {
                        var u = (Quickshell.env("USER") || Quickshell.env("LOGNAME") || "").trim();
                        if (u.length === 0) {
                            var home = (Quickshell.env("HOME") || "").trim();
                            if (home.length > 0) {
                                var parts = home.split("/").filter(function(p) { return p.length > 0; });
                                if (parts.length > 0) u = parts[parts.length - 1];
                            }
                        }
                        return u.length > 0 ? u : "user";
                    }
                    readonly property string displayUser: currentUser.charAt(0).toUpperCase() + currentUser.slice(1)
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        width: 34; height: 34; radius: 17
                        color: Theme.accent
                        Text { anchors.centerIn: parent; text: profileHeader.currentUser.charAt(0).toUpperCase(); font.family: Theme.fontSans; font.pixelSize: 15; font.weight: Font.Bold; color: Theme.accentFg }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text { Layout.fillWidth: true; text: profileHeader.displayUser; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                        Text { Layout.fillWidth: true; text: profileHeader.currentUser + "@" + TelemetryService.hostname; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
                    }
                }

                // Search Box
                Rectangle {
                    Layout.fillWidth: true
                    height: 32; radius: 8
                    color: Theme.cardBg
                    border.width: 1
                    border.color: searchInput.activeFocus ? Theme.accent : Theme.borderSubtle
                    Behavior on border.color { ColorAnimation { duration: 140 } }
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 8; spacing: 6
                        SvgIcon { sourceName: "search"; iconSize: 13; color: Theme.textMuted }
                        AnimatedTextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            font.family: Theme.fontSans; font.pixelSize: 12; textColor: Theme.text; clip: true
                            onTextChanged: root.searchQuery = text
                            Keys.onEscapePressed: (event) => {
                                focus = false;
                                event.accepted = true;
                            }
                            Text {
                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                text: "Find a setting"; font.family: Theme.fontSans; font.pixelSize: 12; color: Theme.textMuted
                                visible: searchInput.text.length === 0
                            }
                        }
                        Item {
                            visible: searchInput.text.length > 0
                            width: 16; height: 16
                            scale: clearSearchMouse.pressed ? 0.85 : 1.0
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            SvgIcon {
                                anchors.centerIn: parent
                                sourceName: "close"
                                iconSize: 11
                                color: clearSearchMouse.containsMouse ? Theme.text : Theme.textMuted
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            MouseArea {
                                id: clearSearchMouse
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchInput.text = "";
                                    root.searchQuery = "";
                                    if (root.shellState) root.shellState.settingsSpotlight = "";
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                // Tree Navigation List
                ListView {
                    id: navList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 0
                    model: root.navItems

                    delegate: Item {
                        id: navDelegate
                        required property var modelData
                        readonly property bool isVisible: {
                            if (root.searchQuery.trim() !== "") return root.matchesSearch(modelData);
                            if (!modelData.sub) return true;
                            return root.isGroupOpen(modelData.group);
                        }
                        readonly property bool isActive: root.currentPage === modelData.key
                            || (modelData.key === "appearance" && root.currentPage === "cursor")

                        width: navList.width
                        height: isVisible ? (modelData.sub ? 32 : 36) : 0
                        visible: height > 0
                        clip: true

                        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: 1
                            anchors.bottomMargin: 1
                            radius: 8
                            clip: true
                            color: navDelegate.isActive ? Theme.cardHover : (navMouse.containsMouse ? Theme.cardBg : "transparent")
                            scale: navMouse.pressed ? 0.96 : 1.0
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                            Rectangle {
                                width: 3; height: modelData.sub ? 16 : 18; radius: 2
                                anchors.left: parent.left
                                anchors.leftMargin: modelData.sub ? 14 : 3
                                anchors.verticalCenter: parent.verticalCenter
                                clip: true
                                color: Theme.accent
                                opacity: navDelegate.isActive ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                                Behavior on anchors.leftMargin { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                ThemeGradientFill {
                                    anchors.fill: parent
                                    enabled: Theme.accentGradientEnabled
                                    color1: Theme.accent
                                    colorMid: Theme.accentMid
                                    color2: Theme.accent2
                                    cornerRadius: 2
                                }
                            }

                            Rectangle {
                                visible: modelData.sub
                                width: 1
                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                anchors.left: parent.left; anchors.leftMargin: 15
                                color: Theme.borderSubtle
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: modelData.sub ? 26 : 12
                                anchors.rightMargin: 8
                                spacing: 6
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    font.family: Theme.fontSans
                                    font.pixelSize: modelData.sub ? 12 : 13
                                    font.weight: navDelegate.isActive ? Font.DemiBold : Font.Normal
                                    color: navDelegate.isActive ? Theme.text : Theme.textSub
                                    elide: Text.ElideRight
                                }
                                SvgIcon {
                                    visible: modelData.hasChildren === true && root.searchQuery.trim() === ""
                                    sourceName: "chevron-right"
                                    iconSize: 13
                                    color: Theme.textMuted
                                    rotation: root.isGroupOpen(modelData.group) ? 90 : 0
                                    Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                }
                            }

                            MouseArea {
                                id: navMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.hasChildren) root.toggleGroup(modelData.group);
                                    root.openPage(modelData.key);
                                }
                            }
                        }
                    }
                }
            }
        }

        // Right Content Area
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Flickable {
                id: pageFlick
                anchors.fill: parent
                anchors.leftMargin: 22
                anchors.rightMargin: 16
                anchors.topMargin: 14
                anchors.bottomMargin: 14
                contentWidth: width
                contentHeight: pageContainer.implicitHeight + 20
                clip: true

                Item {
                    id: pageContainer
                    width: pageFlick.width
                    implicitHeight: pageCol.implicitHeight

                    ParallelAnimation {
                        id: pageInAnim
                        NumberAnimation { target: pageCol; property: "opacity"; from: 0.0; to: 1.0; duration: Theme.reduceMotion ? 90 : 180; easing.type: Easing.OutCubic }
                        NumberAnimation { target: pageCol; property: "y"; from: Theme.reduceMotion ? 0 : 10; to: 0; duration: Theme.reduceMotion ? 0 : 180; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        id: pageCol
                        width: parent.width
                        spacing: 12

                        // Page Heading
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            CtrlBtn {
                                visible: root.currentPage === "cursor"
                                iconName: "arrow-left"
                                text: "Appearance"
                                ghost: true
                                onClicked: root.openPage("appearance")
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: {
                                    if (root.currentPage === "cursor") return "Cursor";
                                    for (let i = 0; i < root.navItems.length; ++i) {
                                        if (root.navItems[i].key === root.currentPage) return root.navItems[i].label;
                                    }
                                    return "Settings";
                                }
                                font.family: Theme.fontSans
                                font.pixelSize: 20
                                font.weight: Font.Bold
                                color: Theme.text
                                elide: Text.ElideRight
                            }
                        }

                        // ==================== 1. HOME ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "home"
                            active: Boolean(root.loadedPages["home"])
                            sourceComponent: ColumnLayout {
                            spacing: 12

                            SectionLabel { text: "Most used pages" }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 3
                                rowSpacing: 8
                                columnSpacing: 8

                                PresetCard {
                                    iconName: "monitor"
                                    title: "Display"
                                    subtitle: root.displayRes
                                    onTriggered: root.openPage("display")
                                }
                                PresetCard {
                                    iconName: "volume"
                                    title: "Sound & Audio"
                                    subtitle: AudioService.muted ? "Muted" : (AudioService.volumePct + "% volume")
                                    onTriggered: root.openPage("sound")
                                }
                                PresetCard {
                                    iconName: "palette"
                                    title: "Appearance"
                                    subtitle: Theme.activePreset
                                    onTriggered: root.openPage("appearance")
                                }
                                PresetCard {
                                    iconName: "keyboard"
                                    title: "Binding"
                                    subtitle: "Shortcuts & triggers"
                                    onTriggered: root.openPage("keybind")
                                }
                                PresetCard {
                                    iconName: "layout"
                                    title: "Layout"
                                    subtitle: "Tiling & window gaps"
                                    onTriggered: root.openPage("layout")
                                }
                                PresetCard {
                                    iconName: "gauge"
                                    title: "Performance"
                                    subtitle: Theme.reduceMotion ? "Reduced motion" : "Full motion"
                                    onTriggered: root.openPage("performance")
                                }
                            }

                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: AudioService.muted ? "volume-x" : "volume"
                                    title: "Master Volume"
                                    subtitle: AudioService.hasLiveSink
                                        ? ((AudioService.muted ? "Muted • " : "") + "PipeWire default sink")
                                        : "PipeWire sink (wpctl)"
                                    RowLayout {
                                        spacing: 8
                                        CtrlBtn {
                                            text: AudioService.muted ? "Unmute" : "Mute"
                                            ghost: !AudioService.muted
                                            onClicked: AudioService.toggleMute()
                                        }
                                        CtrlSlider {
                                            from: 0; to: 100
                                            value: AudioService.volumePct
                                            unit: "%"
                                            onMoved: (v) => AudioService.setVolume(v, false)
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "monitor"
                                    title: "Display Brightness"
                                    subtitle: "Backlight brightness level"
                                    CtrlSlider {
                                        from: 10; to: 100
                                        value: BrightnessService.brightnessPct
                                        unit: "%"
                                        onMoved: (v) => BrightnessService.setBrightness(v, false)
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true; columns: 2; columnSpacing: 10; rowSpacing: 10

                                // Wi-Fi Quick Toggle
                                Rectangle {
                                    Layout.fillWidth: true; height: 60; radius: 12
                                    color: NetworkService.wifiEnabled
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, wifiTileMouse.containsMouse ? 0.16 : 0.10)
                                        : (wifiTileMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                                    border.width: 1
                                    border.color: NetworkService.wifiEnabled
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.48)
                                        : (wifiTileMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.24) : Theme.borderSubtle)
                                    scale: wifiTileMouse.pressed ? 0.98 : 1.0
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Theme.motionEasing; easing.overshoot: Theme.springOvershoot } }

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 12; spacing: 10
                                        Rectangle {
                                            width: 32; height: 32; radius: 8; clip: true
                                            color: NetworkService.wifiEnabled ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.surfaceRaised
                                            border.width: 1
                                            border.color: NetworkService.wifiEnabled ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            SvgIcon { anchors.centerIn: parent; sourceName: "wifi"; iconSize: 16; color: NetworkService.wifiEnabled ? Theme.accent : Theme.textSub }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                            Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: "Wi-Fi"; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: NetworkService.wifiEnabled ? (NetworkService.activeSsid !== "" ? NetworkService.activeSsid : "On • Disconnected") : "Disabled"; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
                                        }
                                        CtrlSwitch {
                                            checked: NetworkService.wifiEnabled
                                            onToggled: (v) => NetworkService.setWifiEnabled(v)
                                        }
                                    }
                                    MouseArea {
                                        id: wifiTileMouse
                                        anchors.fill: parent
                                        z: -1
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openPage("wifi")
                                    }
                                }

                                // Do Not Disturb Quick Toggle
                                Rectangle {
                                    Layout.fillWidth: true; height: 60; radius: 12
                                    color: NotificationService.dnd
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, dndTileMouse.containsMouse ? 0.16 : 0.10)
                                        : (dndTileMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                                    border.width: 1
                                    border.color: NotificationService.dnd
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.48)
                                        : (dndTileMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.24) : Theme.borderSubtle)
                                    scale: dndTileMouse.pressed ? 0.98 : 1.0
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Theme.motionEasing; easing.overshoot: Theme.springOvershoot } }

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 12; spacing: 10
                                        Rectangle {
                                            width: 32; height: 32; radius: 8; clip: true
                                            color: NotificationService.dnd ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.surfaceRaised
                                            border.width: 1
                                            border.color: NotificationService.dnd ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            SvgIcon { anchors.centerIn: parent; sourceName: NotificationService.dnd ? "bell-off" : "bell"; iconSize: 16; color: NotificationService.dnd ? Theme.accent : Theme.textSub }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                            Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: "Do Not Disturb"; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: NotificationService.dnd ? "Popups silenced" : (NotificationService.unreadCount + " unread notifications"); font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
                                        }
                                        CtrlSwitch {
                                            checked: NotificationService.dnd
                                            onToggled: (v) => NotificationService.dnd = v
                                        }
                                    }
                                    MouseArea {
                                        id: dndTileMouse
                                        anchors.fill: parent
                                        z: -1
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: NotificationService.dnd = !NotificationService.dnd
                                    }
                                }

                                // Power Profile Quick Cycler
                                Rectangle {
                                    Layout.fillWidth: true; height: 60; radius: 12
                                    color: pwrTileMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                                    border.width: 1
                                    border.color: pwrTileMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.24) : Theme.borderSubtle
                                    scale: pwrTileMouse.pressed ? 0.98 : 1.0
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Theme.motionEasing; easing.overshoot: Theme.springOvershoot } }

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 12; spacing: 10
                                        Rectangle {
                                            width: 32; height: 32; radius: 8; clip: true
                                            color: Theme.surfaceRaised
                                            border.width: 1; border.color: Theme.borderSubtle
                                            SvgIcon { anchors.centerIn: parent; sourceName: "bolt"; iconSize: 16; color: Theme.textSub }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                            Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: "Power Profile"; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: root.formatPowerProfile(PowerService.powerProfile) + " • Battery " + PowerService.batteryPct + "%"; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
                                        }
                                        CtrlBtn { text: "Cycle"; ghost: true; onClicked: root.cyclePowerProfile() }
                                    }
                                    MouseArea {
                                        id: pwrTileMouse
                                        anchors.fill: parent
                                        z: -1
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.cyclePowerProfile()
                                    }
                                }

                                // System Updates Quick Card
                                Rectangle {
                                    Layout.fillWidth: true; height: 60; radius: 12
                                    color: PackageService.updateCount > 0
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, updTileMouse.containsMouse ? 0.16 : 0.10)
                                        : (updTileMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                                    border.width: 1
                                    border.color: PackageService.updateCount > 0
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.48)
                                        : (updTileMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.24) : Theme.borderSubtle)
                                    scale: updTileMouse.pressed ? 0.98 : 1.0
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Theme.motionEasing; easing.overshoot: Theme.springOvershoot } }

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 12; spacing: 10
                                        Rectangle {
                                            width: 32; height: 32; radius: 8; clip: true
                                            color: PackageService.updateCount > 0 ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : Theme.surfaceRaised
                                            border.width: 1
                                            border.color: PackageService.updateCount > 0 ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            SvgIcon { anchors.centerIn: parent; sourceName: "package-update"; iconSize: 16; color: PackageService.updateCount > 0 ? Theme.accent : Theme.textSub }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                            Text { Layout.fillWidth: true; Layout.minimumWidth: 0; text: "System Updates"; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                                            Text {
                                                Layout.fillWidth: true; Layout.minimumWidth: 0
                                                text: PackageService.checking
                                                    ? "Checking repositories..."
                                                    : (PackageService.updateCount > 0 ? PackageService.updateCount + " updates ready" : "All packages up to date")
                                                font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight
                                            }
                                        }
                                        CtrlBtn { text: "Open"; ghost: true; onClicked: root.openPage("updates") }
                                    }
                                    MouseArea {
                                        id: updTileMouse
                                        anchors.fill: parent
                                        z: -1
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openPage("updates")
                                    }
                                }
                            }

                            SectionLabel { text: "Quick Settings & Theme" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 3; columnSpacing: 8; rowSpacing: 8
                                enabled: !Theme.wallpaperColorEnabled
                                opacity: Theme.wallpaperColorEnabled ? 0.45 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Repeater {
                                    model: Theme.presetCatalog
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool active: root.isPresetActive(modelData.name)
                                        Layout.fillWidth: true; height: 74; radius: 10
                                        color: ((!Theme.wallpaperColorEnabled && themeMouse.containsMouse) || active) ? Theme.cardHover : Theme.cardBg
                                        border.width: active ? 2 : 1
                                        border.color: active ? Theme.accent : ((!Theme.wallpaperColorEnabled && themeMouse.containsMouse) ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
                                        scale: (!Theme.wallpaperColorEnabled && themeMouse.pressed) ? 0.97 : 1.0
                                        clip: true
                                        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                        ColumnLayout {
                                            anchors.fill: parent; anchors.margins: 10; spacing: 6
                                            Rectangle {
                                                Layout.fillWidth: true; height: 32; radius: 6; color: modelData.previewBg
                                                border.width: 1; border.color: Theme.borderSubtle
                                                Rectangle { width: 32; height: 6; radius: 3; anchors.top: parent.top; anchors.topMargin: 5; anchors.horizontalCenter: parent.horizontalCenter; color: modelData.previewAccent }
                                            }
                                            Text { Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: modelData.name; color: Theme.text; font.pixelSize: 11; font.weight: Font.DemiBold }
                                        }
                                        MouseArea {
                                            id: themeMouse
                                            anchors.fill: parent
                                            enabled: !Theme.wallpaperColorEnabled
                                            hoverEnabled: !Theme.wallpaperColorEnabled
                                            cursorShape: !Theme.wallpaperColorEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                root.selectThemePreset(modelData.name);
                                            }
                                        }
                                    }
                                }
                            }
                            WallpaperLockBanner {
                                message: "Theme presets are disabled while \"Adjust colors based on what you see\" is active — Paithosh is matching colors automatically to your wallpaper."
                            }
                        }
                        }

                        // ==================== 2. SYSTEM ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "system"
                            active: Boolean(root.loadedPages["system"])
                            sourceComponent: ColumnLayout {
                            spacing: 10
                            SectionLabel { text: "System options" }
                            HubCard { iconName: "monitor"; title: "Display"; subtitle: "Resolution, scaling & orientation"; pillText: root.displayRes + " • " + root.displayScale.replace(" (Recommended)", ""); onTriggered: root.openPage("display") }
                            HubCard { iconName: "volume"; title: "Sound & Audio"; subtitle: "PipeWire sinks, input & balance"; pillText: AudioService.muted ? "Muted" : (AudioService.volumePct + "%"); onTriggered: root.openPage("sound") }
                            HubCard { iconName: "gauge"; title: "Performance"; subtitle: "Motion tuning & lightweight rendering"; pillText: Theme.reduceMotion ? "Reduced" : "Default"; onTriggered: root.openPage("performance") }
                            HubCard {
                                iconName: "package-update"
                                title: "Updates"
                                subtitle: "System repositories & installed packages"
                                pillText: PackageService.checking
                                    ? "Checking..."
                                    : (PackageService.updating
                                        ? "Updating..."
                                        : (PackageService.updateCount > 0 ? PackageService.updateCount + " Updates Ready" : "Up to date"))
                                onTriggered: root.openPage("updates")
                            }
                            HubCard {
                                iconName: "shield"
                                title: "Backup & Restore"
                                subtitle: "Btrfs system snapshots & /home .pak data backups"
                                pillText: BackupService.busy
                                    ? "Running..."
                                    : (BackupService.stagedRollback
                                        ? "Rollback Staged"
                                        : (BackupService.totalBackupsCount > 0
                                            ? (BackupService.totalBackupsCount + " Saved")
                                            : (BackupService.isBtrfsRoot ? "Btrfs Ready" : "Ready")))
                                onTriggered: root.openPage("backup")
                            }
                            HubCard {
                                iconName: "hard-drive"
                                title: "Storage"
                                subtitle: "File sight breakdown & Shredder cleanup"
                                pillText: StorageService.scanning
                                    ? "Scanning..."
                                    : (StorageService.hasScanned
                                        ? (StorageService.formatBytes(StorageService.usedBytes) + " / " + StorageService.formatBytes(StorageService.totalBytes))
                                        : "Inspect")
                                onTriggered: root.openPage("storage")
                            }
                            HubCard {
                                iconName: "hard-drive"; title: "Accessibility"; subtitle: "Input indicators, screen recording presets & audio"
                                pillText: ScreenRecordService.preset === "low" ? "Low Storage" : (ScreenRecordService.preset === "high" ? "High Quality" : (ScreenRecordService.preset === "custom" ? "Custom" : "Standard"))
                                onTriggered: root.openPage("accessibility")
                            }

                            SectionLabel { text: "Nearby settings" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconName: "moon"; title: "Night Light"; subtitle: "Shift display to warmer colors after sunset"
                                    CtrlSwitch { checked: root.nightLight; onToggled: (v) => root.nightLight = v }
                                }
                                SettingRow {
                                    iconName: "volume"; title: "Master Volume"; subtitle: "Quick output level for default PipeWire sink"
                                    CtrlSlider { from: 0; to: 100; value: AudioService.volumePct; unit: "%"; onMoved: (v) => AudioService.setVolume(v, false) }
                                }
                                SettingRow {
                                    iconName: "bolt"; title: "Power mode"; subtitle: "Tune CPU governor and thermal profile"
                                    CtrlSelect { options: ["Power Saver", "Balanced", "Performance"]; currentText: root.formatPowerProfile(PowerService.powerProfile); onSelected: (v) => PowerService.setPowerProfile(root.powerProfileKey(v)) }
                                }
                                SettingRow {
                                    iconName: "bell-off"; title: "Do Not Disturb"; subtitle: "Silence popups on the Dynamic Island status bar"
                                    CtrlSwitch { checked: NotificationService.dnd; onToggled: (v) => NotificationService.dnd = v }
                                }
                                SettingRow {
                                    iconName: "refresh"; title: "Reload Shell"; subtitle: "Smoothly reload Quickshell and Hyprland config"
                                    searchKeywords: "reload shell restart quickshell qs hyprctl"
                                    CtrlBtn {
                                        text: root.shellState.reloadPhase !== "idle" ? "Reloading…" : "Reload"
                                        ghost: true
                                        enabled: root.shellState.reloadPhase === "idle"
                                        onClicked: root.shellState.requestShellReload({
                                            reloadHyprland: true,
                                            hard: false,
                                            reason: "Shell Reloaded"
                                        })
                                    }
                                }
                            }
                        }
                        }

                        // ==================== 2b. ACCESSIBILITY ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "accessibility"
                            active: Boolean(root.loadedPages["accessibility"])
                            sourceComponent: ColumnLayout {
                            id: accessibilityPage
                            spacing: 12

                            readonly property string activeRecPreset: root.shellState ? root.shellState.recordPreset : ScreenRecordService.preset
                            readonly property string activeRecRes: root.shellState ? root.shellState.recordResolution : ScreenRecordService.resolution
                            readonly property int activeRecFps: root.shellState ? root.shellState.recordFps : ScreenRecordService.fps
                            readonly property string activeRecCodec: {
                                const raw = root.shellState ? root.shellState.recordCodec : ScreenRecordService.codec;
                                const avail = ScreenRecordService.availableCodecs || ["auto"];
                                if (ScreenRecordService.codecsLoaded && avail.indexOf(raw) === -1) return "auto";
                                return raw;
                            }
                            readonly property bool isSoftwareCodec: activeRecCodec === "libx264" || activeRecCodec === "libx265"
                            function codecLabelForKey(k) {
                                switch (k) {
                                    case "h264_vaapi": return "H.264 (VAAPI)";
                                    case "hevc_vaapi": return "HEVC (VAAPI)";
                                    case "h264_nvenc": return "H.264 (NVENC)";
                                    case "hevc_nvenc": return "HEVC (NVENC)";
                                    case "libx264": return "H.264 (Software)";
                                    case "libx265": return "HEVC (Software)";
                                    default: return "Auto (GPU → CPU)";
                                }
                            }
                            readonly property string codecLabel: codecLabelForKey(activeRecCodec)
                            readonly property var codecOptions: {
                                const avail = ScreenRecordService.availableCodecs || ["auto"];
                                const out = [];
                                for (let i = 0; i < avail.length; ++i) {
                                    const lbl = codecLabelForKey(avail[i]);
                                    if (out.indexOf(lbl) === -1) out.push(lbl);
                                }
                                return out.length > 0 ? out : ["Auto (GPU → CPU)"];
                            }
                            Component.onCompleted: {
                                if (!ScreenRecordService.codecsLoaded) ScreenRecordService.refreshCodecs();
                            }
                            readonly property string codecShortLabel: {
                                switch (activeRecCodec) {
                                    case "h264_vaapi": return "H.264 VAAPI";
                                    case "hevc_vaapi": return "HEVC VAAPI";
                                    case "h264_nvenc": return "H.264 NVENC";
                                    case "hevc_nvenc": return "HEVC NVENC";
                                    case "libx264": return "H.264 CPU";
                                    case "libx265": return "HEVC CPU";
                                    default: return "Auto (H.264)";
                                }
                            }
                            readonly property string codecQualityLabel: {
                                if (activeRecCodec === "h264_vaapi" || activeRecCodec === "hevc_vaapi") {
                                    return activeRecPreset === "low" ? "QP 30" : (activeRecPreset === "high" ? "QP 20" : "QP 24");
                                }
                                if (activeRecCodec === "h264_nvenc" || activeRecCodec === "hevc_nvenc") {
                                    return activeRecPreset === "low" ? "CQ 30" : (activeRecPreset === "high" ? "CQ 19" : "CQ 24");
                                }
                                if (activeRecCodec === "libx265") {
                                    return activeRecPreset === "low" ? "CRF 32" : (activeRecPreset === "high" ? "CRF 22" : "CRF 28");
                                }
                                return activeRecPreset === "low" ? "CRF 32" : (activeRecPreset === "high" ? "CRF 20" : "CRF 26");
                            }
                            function codecKeyFromLabel(lbl) {
                                switch (lbl) {
                                    case "H.264 (VAAPI)": return "h264_vaapi";
                                    case "HEVC (VAAPI)": return "hevc_vaapi";
                                    case "H.264 (NVENC)": return "h264_nvenc";
                                    case "HEVC (NVENC)": return "hevc_nvenc";
                                    case "H.264 (Software)": return "libx264";
                                    case "HEVC (Software)": return "libx265";
                                    default: return "auto";
                                }
                            }
                            readonly property string presetLabel: activeRecPreset === "low" ? "Low Storage" : (activeRecPreset === "high" ? "High Quality" : (activeRecPreset === "custom" ? "Custom" : "Standard"))
                            readonly property string estSizePerMin: {
                                if (activeRecPreset === "low" || (activeRecRes === "480p") || (activeRecRes === "720p" && activeRecFps <= 20)) return "~1.8 MB/min";
                                if (activeRecPreset === "high" || activeRecFps >= 60) return "~12 MB/min";
                                return "~4.5 MB/min";
                            }

                            // 1. Live Recording Quality Preview (matches Personalization Desktop Preview)
                            SettingGroup {
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: recPreviewCol.implicitHeight + 24

                                    ColumnLayout {
                                        id: recPreviewCol
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 10

                                        RowLayout {
                                            Layout.fillWidth: true
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 2
                                                Text { text: "Recording Preview"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold }
                                                Text {
                                                    text: accessibilityPage.presetLabel + " • " + (accessibilityPage.activeRecRes === "native" ? "Native" : accessibilityPage.activeRecRes) + " • " + accessibilityPage.activeRecFps + " FPS • " + accessibilityPage.estSizePerMin
                                                    color: Theme.textSub
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: 170
                                            radius: 10
                                            clip: true
                                            color: Theme.surfaceBg
                                            border.width: 1
                                            border.color: Theme.borderSubtle

                                            ThemeGradientFill {
                                                anchors.fill: parent
                                                cornerRadius: 10
                                                enabled: Theme.surfaceGradientEnabled
                                                color1: Theme.surfaceBg
                                                colorMid: Theme.surfaceBgMid
                                                color2: Theme.surfaceBg2
                                                angle: Theme.gradientAngle
                                            }

                                            // Wallpaper scaled to preview resolution so sharpness difference is visible
                                            Image {
                                                anchors.fill: parent
                                                source: (typeof bgLayer !== "undefined" && bgLayer.currentWallpaperPath) ? ("file://" + bgLayer.currentWallpaperPath) : ""
                                                fillMode: Image.PreserveAspectCrop
                                                smooth: accessibilityPage.activeRecRes !== "480p"
                                                sourceSize.width: accessibilityPage.activeRecRes === "480p" ? 160 : (accessibilityPage.activeRecRes === "720p" ? 360 : 960)
                                                opacity: (!Theme.wallpapersDisabled && status === Image.Ready) ? 0.55 : 0.0
                                                visible: opacity > 0.002
                                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            }

                                            // Mock Dynamic Island with live red recording dot
                                            Rectangle {
                                                anchors.top: parent.top; anchors.topMargin: 10
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                width: 156; height: 24; radius: 12
                                                color: Theme.pillBg
                                                border.width: 1; border.color: Theme.borderSubtle

                                                Row {
                                                    anchors.centerIn: parent; spacing: 6
                                                    Rectangle {
                                                        width: 7; height: 7; radius: 3.5; color: Theme.danger
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    Text {
                                                        text: "00:12 • REC"
                                                        color: Theme.dangerText
                                                        font.family: Theme.fontSans; font.pixelSize: 10; font.weight: Font.DemiBold
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                }
                                            }

                                            // Motion smoothness demo pill (updates at simulated 20 / 30 / 60 FPS)
                                            Rectangle {
                                                id: fpsDemoPill
                                                y: 58
                                                x: 16
                                                width: 112; height: 42; radius: 8
                                                color: Qt.rgba(0.08, 0.09, 0.12, 0.82)
                                                border.width: 1; border.color: Theme.accent
                                                property real phase: 0

                                                Timer {
                                                    interval: Math.round(1000 / Math.max(1, accessibilityPage.activeRecFps))
                                                    running: accessibilityPage.visible
                                                    repeat: true
                                                    onTriggered: {
                                                        fpsDemoPill.phase = (fpsDemoPill.phase + (0.045 * (30 / Math.max(1, accessibilityPage.activeRecFps)))) % (Math.PI * 2);
                                                        const span = Math.max(10, fpsDemoPill.parent.width - fpsDemoPill.width - 32);
                                                        fpsDemoPill.x = 16 + (Math.sin(fpsDemoPill.phase) * 0.5 + 0.5) * span;
                                                    }
                                                }

                                                Column {
                                                    anchors.centerIn: parent; spacing: 2
                                                    Text {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        text: accessibilityPage.activeRecFps + " FPS Motion"
                                                        color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.DemiBold
                                                    }
                                                    Text {
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        text: (accessibilityPage.activeRecRes === "native" ? "Native Res" : accessibilityPage.activeRecRes)
                                                        color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 9
                                                    }
                                                }
                                            }

                                            // Bottom info bar
                                            Rectangle {
                                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                                anchors.margins: 10; height: 24; radius: 6; clip: true
                                                color: Qt.rgba(Theme.pillBg.r, Theme.pillBg.g, Theme.pillBg.b, 0.78)
                                                border.width: 1; border.color: Theme.borderSubtle
                                                RowLayout {
                                                    anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                                                    Text {
                                                        Layout.fillWidth: true; Layout.minimumWidth: 0
                                                        text: accessibilityPage.codecShortLabel + " • " + accessibilityPage.codecQualityLabel
                                                            + " • Audio: " + ((ScreenRecordService.recordAudio && ScreenRecordService.recordMic) ? "Output + Mic" : (ScreenRecordService.recordAudio ? "Output" : (ScreenRecordService.recordMic ? "Mic" : "Off")))
                                                        color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 10
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 2. Recording Presets (2x2 grid matching Theme presets)
                            SectionLabel { text: "Recording presets" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 2; columnSpacing: 10; rowSpacing: 10
                                Repeater {
                                    model: [
                                        { key: "standard", name: "Standard", subtitle: "Native • 30 FPS • Balanced (~4.5 MB/m)", res: "native", fps: 30 },
                                        { key: "low", name: "Low Storage (<20MB)", subtitle: "720p • 20 FPS • Long clips (~1.8 MB/m)", res: "720p", fps: 20 },
                                        { key: "high", name: "High Quality", subtitle: "Native • 60 FPS • Crisp (~12 MB/m)", res: "native", fps: 60 },
                                        { key: "custom", name: "Custom", subtitle: "Manual resolution & FPS in Advanced", res: "", fps: 0 }
                                    ]
                                    delegate: PresetCard {
                                        required property var modelData
                                        title: modelData.name
                                        subtitle: modelData.subtitle
                                        active: accessibilityPage.activeRecPreset === modelData.key
                                        onTriggered: {
                                            ScreenRecordService.preset = modelData.key;
                                            if (modelData.res !== "") ScreenRecordService.resolution = modelData.res;
                                            if (modelData.fps > 0) ScreenRecordService.fps = modelData.fps;
                                            if (root.shellState) {
                                                root.shellState.recordPreset = modelData.key;
                                                if (modelData.res !== "") root.shellState.recordResolution = modelData.res;
                                                if (modelData.fps > 0) root.shellState.recordFps = modelData.fps;
                                            }
                                            if (modelData.key === "custom") recAdvancedSection.expanded = true;
                                        }
                                    }
                                }
                            }

                            // 3. Audio & Storage
                            SectionLabel { text: "General" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "volume"; title: "Record with Audio"; subtitle: "Include audio when recording screen"
                                    CtrlSwitch {
                                        checked: root.shellState ? (root.shellState.recordAudio || root.shellState.recordMic) : (ScreenRecordService.recordAudio || ScreenRecordService.recordMic)
                                        onToggled: (v) => {
                                            ScreenRecordService.recordAudio = v;
                                            if (!v) ScreenRecordService.recordMic = false;
                                            if (root.shellState) {
                                                root.shellState.recordAudio = v;
                                                if (!v) root.shellState.recordMic = false;
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "folder"; title: "Save Location (>20MB)"; subtitle: (root.shellState && root.shellState.recordSaveDir !== "") ? root.shellState.recordSaveDir : (ScreenRecordService.saveDir !== "" ? ScreenRecordService.saveDir : "~/Videos (default)")
                                    PillButton {
                                        text: "Browse..."
                                        onClicked: if (root.shellState) root.shellState.openScreenRecordDirPicker()
                                    }
                                }
                            }

                            // 4. Advanced Settings (collapsible card matching Personalization)
                            AdvancedSection {
                                id: recAdvancedSection
                                title: "Advanced Settings"
                                subtitle: "Resolution, frame rate, video codec & audio channels"
                                SettingRow {
                                    showDivider: false
                                    iconName: "monitor"; title: "Resolution"; subtitle: "Output video scale (Native = monitor resolution)"
                                    CtrlSelect {
                                        options: ["Native", "1080p", "720p", "480p"]
                                        currentText: accessibilityPage.activeRecRes === "native" ? "Native" : accessibilityPage.activeRecRes
                                        onSelected: (v) => {
                                            const r = v === "Native" ? "native" : v;
                                            ScreenRecordService.resolution = r;
                                            ScreenRecordService.preset = "custom";
                                            if (root.shellState) {
                                                root.shellState.recordResolution = r;
                                                root.shellState.recordPreset = "custom";
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "gauge"; title: "Frame Rate (FPS)"; subtitle: "Lower FPS reduces CPU usage and file size"
                                    CtrlSelect {
                                        options: ["20 FPS", "30 FPS", "60 FPS"]
                                        currentText: accessibilityPage.activeRecFps + " FPS"
                                        onSelected: (v) => {
                                            const f = parseInt(v, 10) || 30;
                                            ScreenRecordService.fps = f;
                                            ScreenRecordService.preset = "custom";
                                            if (root.shellState) {
                                                root.shellState.recordFps = f;
                                                root.shellState.recordPreset = "custom";
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "video"; title: "Video Codec"; subtitle: "Detected encoders on this device (GPU or CPU)"
                                    searchKeywords: "codec encoder h264 h265 hevc vaapi nvenc libx264 libx265 software hardware gpu cpu"
                                    CtrlSelect {
                                        options: accessibilityPage.codecOptions
                                        currentText: accessibilityPage.codecLabel
                                        onSelected: (v) => {
                                            const c = accessibilityPage.codecKeyFromLabel(v);
                                            ScreenRecordService.codec = c;
                                            if (root.shellState) root.shellState.recordCodec = c;
                                        }
                                    }
                                }
                                // Subtle animated warning when CPU software encoding is selected
                                Item {
                                    id: swCodecWarnWrap
                                    readonly property bool active: accessibilityPage.isSoftwareCodec
                                    Layout.fillWidth: true
                                    implicitHeight: active ? (swCodecWarnBox.implicitHeight + 12) : 0
                                    opacity: active ? 1.0 : 0.0
                                    visible: implicitHeight > 0.5 || opacity > 0.01
                                    clip: true

                                    Behavior on implicitHeight { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                    Rectangle {
                                        id: swCodecWarnBox
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        anchors.top: parent.top
                                        anchors.topMargin: 2
                                        implicitHeight: swCodecWarnRow.implicitHeight + 16
                                        radius: 8
                                        clip: true
                                        color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.12)
                                        border.width: 1
                                        border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.40)

                                        RowLayout {
                                            id: swCodecWarnRow
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 10

                                            SvgIcon {
                                                sourceName: "alert-triangle"
                                                iconSize: 15
                                                color: Theme.warn
                                                Layout.alignment: Qt.AlignTop
                                                Layout.topMargin: 2
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 2

                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: "Software encoding (CPU)"
                                                    color: Theme.warn
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: "Encoding on CPU increases processor load and may drop frames at high resolution or 60 FPS. Prefer Auto or a GPU codec when available."
                                                    color: Theme.textSub
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 11
                                                    wrapMode: Text.WordWrap
                                                }
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "volume"; title: "Output Audio (System)"; subtitle: "Capture desktop sound from default speaker monitor"
                                    CtrlSwitch {
                                        checked: root.shellState ? root.shellState.recordAudio : ScreenRecordService.recordAudio
                                        onToggled: (v) => {
                                            ScreenRecordService.recordAudio = v;
                                            if (root.shellState) root.shellState.recordAudio = v;
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "mic"; title: "Input Audio (Microphone)"; subtitle: "Capture default microphone (mixed if Output is also on)"
                                    CtrlSwitch {
                                        checked: root.shellState ? root.shellState.recordMic : ScreenRecordService.recordMic
                                        onToggled: (v) => {
                                            ScreenRecordService.recordMic = v;
                                            if (root.shellState) root.shellState.recordMic = v;
                                        }
                                    }
                                }
                            }

                            // 5. Dynamic Island Input Indicators (Caps Lock & Fcitx5)
                            SectionLabel { text: "Dynamic Island Input Indicators" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "keyboard"
                                    title: "Input Indicators on Dynamic Island"
                                    subtitle: "Show Caps Lock and input method switches on the Dynamic Island"
                                    CtrlSwitch {
                                        checked: root.shellState ? root.shellState.inputIndicatorEnabled : InputIndicatorService.enabled
                                        onToggled: (v) => {
                                            InputIndicatorService.enabled = v;
                                            if (root.shellState) root.shellState.inputIndicatorEnabled = v;
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "keyboard"
                                    title: "Caps Lock Indicator"
                                    subtitle: "Display ON/OFF status pill when toggling Caps Lock"
                                    opacity: (root.shellState ? root.shellState.inputIndicatorEnabled : InputIndicatorService.enabled) ? 1.0 : 0.45
                                    enabled: root.shellState ? root.shellState.inputIndicatorEnabled : InputIndicatorService.enabled
                                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    CtrlSwitch {
                                        checked: root.shellState ? root.shellState.capsLockIndicatorEnabled : InputIndicatorService.capsLockEnabled
                                        onToggled: (v) => {
                                            InputIndicatorService.capsLockEnabled = v;
                                            if (root.shellState) root.shellState.capsLockIndicatorEnabled = v;
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "globe"
                                    title: "Fcitx5 Input Method Indicator"
                                    subtitle: "Show EN / Unikey switches on Dynamic Island and hide the default Fcitx5 popup"
                                    opacity: (root.shellState ? root.shellState.inputIndicatorEnabled : InputIndicatorService.enabled) ? 1.0 : 0.45
                                    enabled: root.shellState ? root.shellState.inputIndicatorEnabled : InputIndicatorService.enabled
                                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    CtrlSwitch {
                                        checked: root.shellState ? root.shellState.fcitxIndicatorEnabled : InputIndicatorService.fcitxEnabled
                                        onToggled: (v) => {
                                            InputIndicatorService.fcitxEnabled = v;
                                            if (root.shellState) root.shellState.fcitxIndicatorEnabled = v;
                                        }
                                    }
                                }
                            }
                        }
                        }

                        // ==================== 3. DISPLAY ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "display"
                            active: Boolean(root.loadedPages["display"])
                            sourceComponent: ColumnLayout {
                            spacing: 12

                            // 1. Live Display Preview (mirrors Personalization main page)
                            SectionLabel { text: "Display preview" }
                            SettingGroup {
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: 210

                                    // Monitor info badge (top-left)
                                    Rectangle {
                                        z: 2
                                        anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 12
                                        height: 22; radius: 11
                                        width: displayBadgeRow.implicitWidth + 16
                                        color: Theme.pillBg
                                        border.width: 1; border.color: Theme.borderSubtle
                                        RowLayout {
                                            id: displayBadgeRow
                                            anchors.centerIn: parent; spacing: 6
                                            Rectangle { width: 6; height: 6; radius: 3; color: Theme.accent }
                                            Text {
                                                text: root.draftDisplayRes + " • " + root.draftDisplayRefreshRate + " • " + root.draftDisplayScale.replace(" (Recommended)", "") + " • " + root.draftDisplayOrient
                                                color: Theme.text
                                                font.family: Theme.fontMono
                                                font.pixelSize: 10
                                                font.weight: Font.Medium
                                            }
                                        }
                                    }

                                    // Pending preview indicator (top-right)
                                    Rectangle {
                                        z: 2
                                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 12
                                        height: 22; radius: 11
                                        width: previewBadgeRow.implicitWidth + 16
                                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                        border.width: 1; border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55)
                                        opacity: root.hasPendingDisplayChanges ? 1.0 : 0.0
                                        visible: opacity > 0.01
                                        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                        RowLayout {
                                            id: previewBadgeRow
                                            anchors.centerIn: parent; spacing: 5
                                            Rectangle { width: 6; height: 6; radius: 3; color: Theme.accent }
                                            Text {
                                                text: "Preview"
                                                color: Theme.accent
                                                font.family: Theme.fontSans
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }

                                    // Monitor frame centered in preview
                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        anchors.topMargin: 28

                                        readonly property bool isPortrait: root.draftDisplayOrient === "Portrait"
                                        readonly property real scaleFactor: {
                                            const s = parseFloat(root.draftDisplayScale);
                                            return isNaN(s) ? 1.0 : Math.max(0.85, Math.min(1.45, s / 100.0));
                                        }

                                        Rectangle {
                                            id: displayMonitorFrame
                                            anchors.centerIn: parent
                                            width: parent.isPortrait ? 96 : Math.min(parent.width - 24, 280)
                                            height: parent.isPortrait ? Math.min(parent.height - 4, 164) : Math.min(parent.height - 8, 158)
                                            radius: Math.max(6, Math.min(14, CompositorService.cornerRounding * 0.55))
                                            color: Theme.cardBg
                                            border.width: 2
                                            border.color: Theme.accent
                                            clip: true

                                            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                            ThemeGradientFill {
                                                anchors.fill: parent
                                                cornerRadius: parent.radius
                                                enabled: Theme.surfaceGradientEnabled
                                                color1: Theme.surfaceBg
                                                colorMid: Theme.surfaceBgMid
                                                color2: Theme.surfaceBg2
                                                angle: Theme.gradientAngle
                                            }

                                            // Live Wallpaper
                                            Image {
                                                anchors.fill: parent
                                                source: (typeof bgLayer !== "undefined" && bgLayer.wallpapers && bgLayer.wallpapers.length > 0)
                                                    ? bgLayer.wallpapers[Math.max(0, Math.min(bgLayer.currentIndex, bgLayer.wallpapers.length - 1))]
                                                    : ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                smooth: true
                                                sourceSize.width: Theme.reduceMotion ? 360 : 960
                                                sourceSize.height: Theme.reduceMotion ? 202 : 540
                                                opacity: (!Theme.wallpapersDisabled && status === Image.Ready) ? 1.0 : 0.0
                                                visible: opacity > 0.002
                                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            }

                                            // Subtle vignette for contrast
                                            Rectangle {
                                                anchors.fill: parent
                                                color: Qt.rgba(0, 0, 0, 0.22)
                                                opacity: Theme.wallpapersDisabled ? 0.0 : 1.0
                                                visible: opacity > 0.002
                                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            }

                                            // Simulated Dynamic Island (scales with displayScale)
                                            Rectangle {
                                                id: displayPreviewIsland
                                                readonly property bool isBottomPreview: (root.shellState ? root.shellState.barPosition : root.barPosition) === "bottom"
                                                readonly property real edgeMargin: 5
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                y: isBottomPreview ? (parent.height - height - edgeMargin) : edgeMargin
                                                width: Math.min(parent.width - 16, Math.round(130 * displayMonitorFrame.parent.scaleFactor))
                                                height: Math.round(18 * displayMonitorFrame.parent.scaleFactor)
                                                radius: height / 2
                                                color: Theme.pillBg
                                                border.width: 1
                                                border.color: Theme.borderSubtle
                                                Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                                RowLayout {
                                                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 4
                                                    Rectangle { width: 4; height: 4; radius: 2; color: Theme.accent }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        horizontalAlignment: Text.AlignHCenter
                                                        text: "Paithosh"
                                                        color: Theme.text
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: Math.round(8 * displayMonitorFrame.parent.scaleFactor)
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            // Simulated Tiled Windows
                                            RowLayout {
                                                readonly property real islandClearance: displayPreviewIsland.edgeMargin + displayPreviewIsland.height + 6
                                                anchors.left: parent.left; anchors.right: parent.right
                                                anchors.top: parent.top; anchors.bottom: parent.bottom
                                                anchors.leftMargin: 8; anchors.rightMargin: 8
                                                anchors.topMargin: displayPreviewIsland.isBottomPreview ? 8 : islandClearance
                                                anchors.bottomMargin: displayPreviewIsland.isBottomPreview ? islandClearance : 8
                                                spacing: 6

                                                Rectangle {
                                                    Layout.fillWidth: true; Layout.fillHeight: true
                                                    Layout.preferredWidth: 1.3
                                                    radius: Math.max(2, Math.min(12, CompositorService.cornerRounding * 0.4))
                                                    color: Qt.rgba(Theme.surfaceBg.r, Theme.surfaceBg.g, Theme.surfaceBg.b, CompositorService.blurEnabled ? 0.80 : 0.96)
                                                    border.width: 1; border.color: Theme.accent
                                                    ColumnLayout {
                                                        anchors.fill: parent; anchors.margins: 7; spacing: 4
                                                        Text {
                                                            text: "Display"
                                                            color: Theme.text
                                                            font.family: Theme.fontSans
                                                            font.pixelSize: Math.round(9 * displayMonitorFrame.parent.scaleFactor)
                                                            font.weight: Font.DemiBold
                                                            elide: Text.ElideRight
                                                        }
                                                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Math.round(4 * displayMonitorFrame.parent.scaleFactor); radius: 2; color: Theme.cardHover }
                                                        Rectangle { width: Math.min(parent.width, Math.round(44 * displayMonitorFrame.parent.scaleFactor)); height: Math.round(4 * displayMonitorFrame.parent.scaleFactor); radius: 2; color: Theme.cardBg }
                                                        Item { Layout.fillHeight: true }
                                                    }
                                                }

                                                Rectangle {
                                                    visible: !displayMonitorFrame.parent.isPortrait
                                                    Layout.fillWidth: true; Layout.fillHeight: true
                                                    Layout.preferredWidth: 0.85
                                                    radius: Math.max(2, Math.min(12, CompositorService.cornerRounding * 0.4))
                                                    color: Qt.rgba(Theme.surfaceRaised.r, Theme.surfaceRaised.g, Theme.surfaceRaised.b, (CompositorService.blurEnabled ? 0.74 : 0.95) * CompositorService.inactiveOpacity)
                                                    border.width: 1; border.color: Theme.borderSubtle
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            SectionLabel { text: "Brightness" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "monitor"
                                    title: "Display brightness"
                                    subtitle: "Adjust built-in display backlight level"
                                    CtrlSlider {
                                        from: 10; to: 100
                                        value: BrightnessService.brightnessPct
                                        unit: "%"
                                        onMoved: (v) => BrightnessService.setBrightness(v, false)
                                    }
                                }
                            }

                            SectionLabel { text: "Scale & layout" }

                            // Pending Display Changes Action Bar (Apply / Reset)
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: root.hasPendingDisplayChanges ? 52 : 0
                                opacity: root.hasPendingDisplayChanges ? 1.0 : 0.0
                                visible: Layout.preferredHeight > 0.5
                                clip: true

                                Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.10)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        SvgIcon {
                                            sourceName: "monitor"
                                            iconSize: 15
                                            color: Theme.accent
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: "Previewing display changes — click Apply to save"
                                            color: Theme.text
                                            font.family: Theme.fontSans
                                            font.pixelSize: 12
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }

                                        CtrlBtn {
                                            text: "Reset"
                                            ghost: true
                                            enabled: root.hasPendingDisplayChanges
                                            onClicked: root.resetDisplayDraft()
                                        }

                                        CtrlBtn {
                                            text: "Apply"
                                            iconName: "check"
                                            enabled: root.hasPendingDisplayChanges
                                            onClicked: root.applyDisplayChange()
                                        }
                                    }
                                }
                            }

                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconName: "monitor"; title: "Scale"; subtitle: "Change the size of text, apps, and other items"
                                    CtrlSelect { options: ["100%", "125% (Recommended)", "150%", "200%"]; currentText: root.draftDisplayScale; onSelected: (v) => { root.draftDisplayScale = v; } }
                                }
                                SettingRow {
                                    iconName: "monitor"; title: "Display resolution"; subtitle: "Adjust the resolution to fit your connected display (Max: " + root.maxDisplayRes + ")"
                                    CtrlSelect { options: root.displayResOptions; currentText: root.draftDisplayRes; onSelected: (v) => { root.draftDisplayRes = v; root.updateRefreshOptionsForRes(v, 0, true); } }
                                }
                                SettingRow {
                                    iconName: "monitor"; title: "Refresh rate"; subtitle: "Choose a higher refresh rate for smoother motion"
                                    CtrlSelect { options: root.displayRefreshOptions; currentText: root.draftDisplayRefreshRate; onSelected: (v) => { root.draftDisplayRefreshRate = v; } }
                                }
                                SettingRow {
                                    iconName: "monitor"; title: "Display orientation"; subtitle: "Rotate screen layout for Wayland output"
                                    CtrlSelect { options: ["Landscape", "Portrait"]; currentText: root.draftDisplayOrient; onSelected: (v) => { root.draftDisplayOrient = v; } }
                                }
                                SettingRow {
                                    iconName: "lock"; title: "Rotation lock"; subtitle: "Prevent automatic orientation changes"
                                    CtrlSwitch { checked: root.rotationLock; onToggled: (v) => root.rotationLock = v }
                                }
                            }
                        }
                        }

                        // ==================== 4. SOUND ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "sound"
                            active: Boolean(root.loadedPages["sound"])
                            sourceComponent: ColumnLayout {
                            spacing: 12

                            // Output (Default Sink + All Output Devices)
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: AudioService.muted ? "volume-x" : "volume"
                                    title: "Output"
                                    subtitle: AudioService.hasLiveSink
                                        ? (AudioService.deviceDisplayName(AudioService.sink) + " • " + (AudioService.muted ? "Muted" : (AudioService.volumePct + "%")))
                                        : "No default output device"
                                    CtrlSwitch {
                                        checked: !AudioService.muted
                                        enabled: AudioService.hasLiveSink
                                        onToggled: (_) => AudioService.toggleMute()
                                    }
                                }
                                SettingRow {
                                    iconName: "volume"
                                    title: "Output volume"
                                    subtitle: "Master playback volume"
                                    CtrlSlider {
                                        from: 0; to: 100
                                        value: AudioService.volumePct
                                        unit: "%"
                                        onMoved: (v) => AudioService.setVolume(v, false)
                                    }
                                }
                            }

                            // System Sound (Independent SFX Volume)
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: (!SoundService.enabled || SoundService.volumePct === 0) ? "bell-off" : "bell"
                                    title: "System Sound"
                                    subtitle: SoundService.enabled
                                        ? ("UI & alert effects • " + SoundService.volumePct + "%")
                                        : "Muted • Independent from app audio"
                                    searchKeywords: "system sound sfx effects ui notification alert volume mute"
                                    CtrlSwitch {
                                        checked: SoundService.enabled
                                        onToggled: (v) => SoundService.setEnabled(v)
                                    }
                                }
                                SettingRow {
                                    iconName: "sliders"
                                    title: "System sound volume"
                                    subtitle: "Independent SFX level for UI, alerts & feedback"
                                    searchKeywords: "system sound sfx volume slider effects ui independent"
                                    RowLayout {
                                        spacing: 8
                                        CtrlBtn {
                                            text: "Test"
                                            ghost: true
                                            enabled: SoundService.enabled && SoundService.volumePct > 0
                                            onClicked: SoundService.playSystemPreview(true)
                                        }
                                        CtrlSlider {
                                            from: 0; to: 100
                                            value: SoundService.volumePct
                                            unit: "%"
                                            enabled: SoundService.enabled
                                            opacity: SoundService.enabled ? 1.0 : 0.45
                                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            onMoved: (v) => {
                                                SoundService.setVolumePct(v);
                                                SoundService.playSystemPreview(false);
                                            }
                                        }
                                    }
                                }
                            }

                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "headphones"
                                    title: "Output devices"
                                    subtitle: AudioService.outputDevices.length + (AudioService.outputDevices.length === 1 ? " device available" : " devices available")
                                }
                                Repeater {
                                    model: AudioService.outputDevices
                                    delegate: SettingRow {
                                        required property var modelData
                                        readonly property bool isDefault: AudioService.sink && modelData.id === AudioService.sink.id
                                        readonly property bool devMuted: AudioService.isDeviceMuted(modelData)
                                        readonly property int devVol: AudioService.deviceVolumePct(modelData)
                                        iconName: isDefault ? "circle-dot" : "circle"
                                        title: AudioService.deviceDisplayName(modelData)
                                        subtitle: (isDefault ? "Default • " : "") + (devMuted ? "Muted" : (devVol + "%"))
                                        RowLayout {
                                            spacing: 8
                                            CtrlBtn {
                                                text: isDefault ? "Default" : "Use"
                                                ghost: isDefault
                                                enabled: !isDefault
                                                onClicked: AudioService.setDefaultOutput(modelData)
                                            }
                                            CtrlBtn {
                                                text: devMuted ? "Unmute" : "Mute"
                                                ghost: !devMuted
                                                onClicked: AudioService.toggleDeviceMute(modelData)
                                            }
                                            CtrlSlider {
                                                Layout.preferredWidth: 150
                                                from: 0; to: 100
                                                value: devVol
                                                unit: "%"
                                                onMoved: (v) => AudioService.setDeviceVolume(modelData, v)
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    visible: AudioService.outputDevices.length === 0
                                    iconName: "minus"
                                    title: "No output devices found"
                                    subtitle: "Connect speakers or headphones"
                                }
                            }

                            // Applications (Per-App Playback Streams)
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "volume"
                                    title: "Applications"
                                    subtitle: AudioService.appPlaybackStreams.length === 0
                                        ? "No active audio streams"
                                        : (AudioService.appPlaybackStreams.length + (AudioService.appPlaybackStreams.length === 1 ? " app playing" : " apps playing"))
                                    searchKeywords: "application app volume mixer stream playback per-app"
                                }
                                Repeater {
                                    model: AudioService.appPlaybackStreams
                                    delegate: SettingRow {
                                        required property var modelData
                                        readonly property bool appMuted: AudioService.isDeviceMuted(modelData)
                                        readonly property int appVol: AudioService.deviceVolumePct(modelData)
                                        readonly property string appName: AudioService.streamAppName(modelData)
                                        readonly property string mediaName: AudioService.streamMediaName(modelData)
                                        iconName: "music"
                                        title: appName
                                        subtitle: (mediaName !== "" ? (mediaName + " • ") : "") + (appMuted ? "Muted" : (appVol + "%"))
                                        searchKeywords: "application app volume mixer stream " + appName + " " + mediaName
                                        RowLayout {
                                            spacing: 8
                                            CtrlBtn {
                                                text: appMuted ? "Unmute" : "Mute"
                                                ghost: !appMuted
                                                onClicked: AudioService.toggleDeviceMute(modelData)
                                            }
                                            CtrlSlider {
                                                Layout.preferredWidth: 150
                                                from: 0; to: 100
                                                value: appVol
                                                unit: "%"
                                                onMoved: (v) => AudioService.setDeviceVolume(modelData, v)
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    visible: AudioService.appPlaybackStreams.length === 0
                                    iconName: "music"
                                    title: "No active applications"
                                    subtitle: "Apps playing audio will appear here"
                                    searchKeywords: "application app volume mixer stream"
                                }
                            }

                            // Input (Default Source + All Input Devices)
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: AudioService.inputMuted ? "mic-off" : "mic"
                                    title: "Input"
                                    subtitle: AudioService.hasLiveSource
                                        ? (AudioService.deviceDisplayName(AudioService.source) + " • " + (AudioService.inputMuted ? "Muted" : (AudioService.inputVolumePct + "%")))
                                        : "No default input device"
                                    CtrlSwitch {
                                        checked: !AudioService.inputMuted
                                        enabled: AudioService.hasLiveSource
                                        onToggled: (_) => AudioService.toggleInputMute()
                                    }
                                }
                                SettingRow {
                                    iconName: "sliders"
                                    title: "Input volume"
                                    subtitle: "Master microphone gain"
                                    CtrlSlider {
                                        from: 0; to: 100
                                        value: AudioService.inputVolumePct
                                        unit: "%"
                                        onMoved: (v) => AudioService.setInputVolume(v)
                                    }
                                }
                            }

                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "mic"
                                    title: "Input devices"
                                    subtitle: AudioService.inputDevices.length + (AudioService.inputDevices.length === 1 ? " device available" : " devices available")
                                }
                                Repeater {
                                    model: AudioService.inputDevices
                                    delegate: SettingRow {
                                        required property var modelData
                                        readonly property bool isDefault: AudioService.source && modelData.id === AudioService.source.id
                                        readonly property bool devMuted: AudioService.isDeviceMuted(modelData)
                                        readonly property int devVol: AudioService.deviceVolumePct(modelData)
                                        iconName: isDefault ? "circle-dot" : "circle"
                                        title: AudioService.deviceDisplayName(modelData)
                                        subtitle: (isDefault ? "Default • " : "") + (devMuted ? "Muted" : (devVol + "%"))
                                        RowLayout {
                                            spacing: 8
                                            CtrlBtn {
                                                text: isDefault ? "Default" : "Use"
                                                ghost: isDefault
                                                enabled: !isDefault
                                                onClicked: AudioService.setDefaultInput(modelData)
                                            }
                                            CtrlBtn {
                                                text: devMuted ? "Unmute" : "Mute"
                                                ghost: !devMuted
                                                onClicked: AudioService.toggleDeviceMute(modelData)
                                            }
                                            CtrlSlider {
                                                Layout.preferredWidth: 150
                                                from: 0; to: 100
                                                value: devVol
                                                unit: "%"
                                                onMoved: (v) => AudioService.setDeviceVolume(modelData, v)
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    visible: AudioService.inputDevices.length === 0
                                    iconName: "minus"
                                    title: "No input devices found"
                                    subtitle: "Connect a microphone"
                                }
                            }
                        }
                        }

                        // ==================== 5. PERFORMANCE ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "performance"
                            active: Boolean(root.loadedPages["performance"])
                            sourceComponent: ColumnLayout {
                            spacing: 10
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "bolt"
                                    title: "Reduce motion~"
                                    subtitle: "hacky way to increase performance"
                                    searchKeywords: "reduce motion performance fps lag smooth blur shadow gooey animations potato pc"
                                    CtrlSwitch {
                                        checked: Theme.reduceMotion
                                        onToggled: (v) => root.shellState.setReduceMotion(v)
                                    }
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: perfNoteRow.implicitHeight + 24
                                radius: 12
                                clip: true
                                color: Theme.cardBg
                                border.width: 1
                                border.color: Theme.borderSubtle

                                RowLayout {
                                    id: perfNoteRow
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    SvgIcon {
                                        Layout.alignment: Qt.AlignTop
                                        Layout.topMargin: 2
                                        sourceName: "info"
                                        iconSize: 14
                                        color: Theme.textSub
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        wrapMode: Text.WordWrap
                                        readonly property string baseNote: "To perceive the world at its purest is to strip away the illusion of excess—every superfluous blur, every theatrical bounce, every restless shader is merely noise standing between your eyes and true clarity. By embracing a calmer, smoother, and far more refined stillness, the interface transcends spectacle to become effortless thought. Overall, it increases performance for your potato pc"
                                        function _corruptNote(src) {
                                            if (!Theme.reduceMotion || Math.random() > 0.5) return src;
                                            const glyphs = "▓▒░█╬╫┼¤§øæþð¿¡";
                                            const jpEchoes = [
                                                "私の言語の限界が、私の世界の限界だ。",
                                                "素晴らしい日々——あるいは、ただの空と世界。",
                                                "存在とは何か。世界はただそこにある。"
                                            ];
                                            const parts = src.split(". ");
                                            for (let i = 0; i < parts.length - 1; ++i) {
                                                const r = Math.random();
                                                if (r < 0.30) {
                                                    const bleakSwaps = {
                                                        "purest": "emptiest",
                                                        "clarity": "oblivion",
                                                        "calmer": "colder",
                                                        "smoother": "hollower",
                                                        "refined": "fading",
                                                        "stillness": "void",
                                                        "effortless": "meaningless",
                                                        "thought": "silence",
                                                        "illusion": "truth",
                                                        "noise": "echoes"
                                                    };
                                                    let bleak = parts[i];
                                                    for (const k in bleakSwaps) {
                                                        bleak = bleak.replace(new RegExp("\\b" + k + "\\b", "gi"), bleakSwaps[k]);
                                                    }
                                                    parts[i] = bleak.split("").reverse().join("");
                                                } else if (r < 0.60) {
                                                    let out = "";
                                                    for (let j = 0; j < parts[i].length; ++j) {
                                                        const ch = parts[i][j];
                                                        out += (ch !== " " && Math.random() < 0.45)
                                                            ? glyphs[Math.floor(Math.random() * glyphs.length)]
                                                            : ch;
                                                    }
                                                    parts[i] = out;
                                                } else if (r < 0.85) {
                                                    parts[i] = jpEchoes[Math.floor(Math.random() * jpEchoes.length)];
                                                }
                                            }
                                            if (Math.random() < 0.25) {
                                                const endEchoes = [
                                                    "世界の果てで、あなたのpotato pcはただ静かに動き続ける",
                                                    "You don't know, and you never will"
                                                ];
                                                parts[parts.length - 1] = endEchoes[Math.floor(Math.random() * endEchoes.length)];
                                            }
                                            return parts.join(". ");
                                        }
                                        text: _corruptNote(baseNote)
                                        color: Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        lineHeight: 1.4
                                    }
                                }
                            }
                        }
                        }

                        // ==================== 6. UPDATES ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "updates"
                            active: Boolean(root.loadedPages["updates"])
                            sourceComponent: ColumnLayout {
                            spacing: 10
                            SettingGroup {
                                SettingRow {
                                    showDivider: true
                                    iconName: "paithosh"
                                    title: {
                                        if (PackageService.shellUpdateStream === "release" && PackageService.shellCurrentTag !== "") {
                                            return "Paithosh Shell  •  " + PackageService.shellCurrentTag;
                                        }
                                        if (PackageService.shellBranch !== "") {
                                            return "Paithosh Shell  •  " + PackageService.shellBranch + (PackageService.shellCommit !== "" ? "@" + PackageService.shellCommit : "");
                                        }
                                        return "Paithosh Shell";
                                    }
                                    subtitle: {
                                        const isRelease = PackageService.shellUpdateStream === "release";
                                        if (PackageService.shellChecking) {
                                            return isRelease ? "Checking GitHub releases for shell updates..." : "Checking main branch for shell updates...";
                                        }
                                        if (PackageService.shellUpdating) {
                                            return isRelease ? "Switching to latest release and reloading shell..." : "Pulling latest changes from main and reloading shell...";
                                        }
                                        if (PackageService.shellUpdateError !== "") return PackageService.shellUpdateError;
                                        if (PackageService.shellUpdateBehind > 0) {
                                            if (isRelease && PackageService.shellTargetVersion !== "") {
                                                return "Release " + PackageService.shellTargetVersion + " available (" + PackageService.shellUpdateBehind + (PackageService.shellUpdateBehind === 1 ? " commit)" : " commits)")
                                                    + (PackageService.shellLatestSummary !== "" ? " — " + PackageService.shellLatestSummary : "");
                                            }
                                            return PackageService.shellUpdateBehind + (PackageService.shellUpdateBehind === 1 ? " new commit available" : " new commits available")
                                                + (PackageService.shellLatestSummary !== "" ? " — " + PackageService.shellLatestSummary : "");
                                        }
                                        if (isRelease && PackageService.shellUpdateAhead > 0 && PackageService.shellTargetVersion !== "") {
                                            return "Ahead of latest stable release " + PackageService.shellTargetVersion + " (" + PackageService.shellUpdateAhead + (PackageService.shellUpdateAhead === 1 ? " commit)" : " commits)");
                                        }
                                        if (PackageService.shellCheckedOnce) {
                                            if (isRelease) return "Shell is up to date with release " + (PackageService.shellTargetVersion || PackageService.shellCurrentTag || "stable");
                                            return "Shell is up to date with " + (PackageService.shellTargetVersion || "main");
                                        }
                                        return isRelease
                                            ? "Update Paithosh Shell from tagged GitHub releases (Stable)"
                                            : "Update Paithosh Shell directly from GitHub main branch";
                                    }
                                    searchKeywords: "paithosh shell git repo pull self update reload release stable main github"
                                    RowLayout {
                                        spacing: 8
                                        CtrlBtn {
                                            text: PackageService.shellChecking ? "Checking..." : "Check"
                                            ghost: true
                                            enabled: !PackageService.shellChecking && !PackageService.shellUpdating
                                            onClicked: PackageService.checkShellUpdate()
                                        }
                                        CtrlBtn {
                                            readonly property bool canSwitchToRelease: PackageService.shellUpdateStream === "release"
                                                && PackageService.shellUpdateBehind === 0
                                                && PackageService.shellUpdateAhead > 0
                                                && PackageService.shellTargetVersion !== ""
                                            text: {
                                                if (PackageService.shellUpdating) return "Updating...";
                                                if (PackageService.shellUpdateBehind > 0) {
                                                    return PackageService.shellUpdateStream === "release" && PackageService.shellTargetVersion !== ""
                                                        ? ("Update (" + PackageService.shellTargetVersion + ")")
                                                        : ("Update (" + PackageService.shellUpdateBehind + ")");
                                                }
                                                if (canSwitchToRelease) return "Switch (" + PackageService.shellTargetVersion + ")";
                                                return "Update";
                                            }
                                            enabled: !PackageService.shellChecking && !PackageService.shellUpdating && (PackageService.shellUpdateBehind > 0 || canSwitchToRelease)
                                            onClicked: PackageService.updateShell()
                                        }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 14
                                    Layout.rightMargin: 14
                                    Layout.topMargin: 8
                                    Layout.bottomMargin: 10
                                    spacing: 5
                                    visible: PackageService.shellUpdateStream !== "release"
                                        && PackageService.shellUpdateBehind > 0
                                        && PackageService.shellCommits.length > 0
                                    Repeater {
                                        model: PackageService.shellCommits
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text {
                                                text: modelData.hash
                                                color: Theme.accent
                                                font.family: Theme.fontMono
                                                font.pixelSize: 11
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: modelData.subject
                                                color: Theme.textSub
                                                font.family: Theme.fontSans
                                                font.pixelSize: 12
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                    Text {
                                        visible: PackageService.shellUpdateBehind > PackageService.shellCommits.length
                                        text: "+" + (PackageService.shellUpdateBehind - PackageService.shellCommits.length) + " more commits"
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 14
                                    Layout.rightMargin: 14
                                    Layout.topMargin: 8
                                    Layout.bottomMargin: 10
                                    spacing: 4
                                    visible: PackageService.shellUpdateStream === "release"
                                        && (PackageService.shellUpdateBehind > 0 || PackageService.shellUpdateAhead > 0)
                                        && PackageService.shellReleaseChangelog !== ""
                                    Text {
                                        text: "CHANGELOG"
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        font.letterSpacing: 0.6
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: PackageService.shellReleaseChangelog
                                        textFormat: Text.MarkdownText
                                        color: Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        wrapMode: Text.Wrap
                                    }
                                }
                                SettingRow {
                                    showDivider: !(PackageService.shellUpdateStream === "release" && PackageService.shellUpdateBehind === 0 && PackageService.shellUpdateAhead > 0 && PackageService.shellTargetVersion !== "")
                                    iconName: "download"
                                    title: "Update Stream"
                                    subtitle: PackageService.shellUpdateStream === "release"
                                        ? "Release (Stable) — update from tagged GitHub releases"
                                        : "Main (GitHub) — pull latest commits directly from main branch"
                                    searchKeywords: "update stream channel release stable main github branch"
                                    CtrlSelect {
                                        options: ["Main (GitHub)", "Release (Stable)"]
                                        currentText: PackageService.shellUpdateStream === "release" ? "Release (Stable)" : "Main (GitHub)"
                                        enabled: !PackageService.shellChecking && !PackageService.shellUpdating
                                        onSelected: (v) => PackageService.setShellUpdateStream(v.indexOf("Release") === 0 ? "release" : "main")
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 14
                                    Layout.rightMargin: 14
                                    Layout.bottomMargin: 10
                                    implicitHeight: releaseReminderRow.implicitHeight + 16
                                    radius: 8
                                    color: Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.10)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.30)
                                    visible: PackageService.shellUpdateStream === "release"
                                        && PackageService.shellUpdateBehind === 0
                                        && PackageService.shellUpdateAhead > 0
                                        && PackageService.shellTargetVersion !== ""
                                    RowLayout {
                                        id: releaseReminderRow
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 8
                                        SvgIcon {
                                            sourceName: "info"
                                            iconSize: 14
                                            color: Theme.info
                                            Layout.alignment: Qt.AlignTop
                                            Layout.topMargin: 1
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            wrapMode: Text.WordWrap
                                            text: "Reminder: Switching from main to " + PackageService.shellTargetVersion
                                                + " rolls back " + PackageService.shellUpdateAhead
                                                + (PackageService.shellUpdateAhead === 1 ? " commit" : " commits")
                                                + ". Consider backing up first — some newer features may be unavailable and Hyprland config will need to be synced."
                                            color: Theme.textSub
                                            font.family: Theme.fontSans
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                                SettingRow {
                                    showDivider: true
                                    iconName: "code"
                                    title: "Hyprland Default Config"
                                    subtitle: {
                                        if (PackageService.hyprSyncing) return "Syncing defaults/hypr to ~/.config/hypr...";
                                        if (PackageService.hyprSyncError !== "") return PackageService.hyprSyncError;
                                        if (PackageService.hyprSyncMessage !== "") return PackageService.hyprSyncMessage;
                                        return "Back up ~/.config/hypr and sync Paithosh's modular Lua configuration";
                                    }
                                    searchKeywords: "hyprland config lua defaults sync backup"
                                    RowLayout {
                                        spacing: 8
                                        CtrlBtn {
                                            visible: PackageService.hyprSyncState === "outdated"
                                            text: PackageService.hyprSyncing ? "Updating..." : "Update"
                                            enabled: !PackageService.hyprSyncing && !PackageService.shellUpdating
                                            onClicked: root.pendingHyprMode = "update"
                                        }
                                        CtrlBtn {
                                            visible: PackageService.hyprSyncState === "outdated"
                                            text: "Reset All"
                                            ghost: true
                                            enabled: !PackageService.hyprSyncing && !PackageService.shellUpdating
                                            onClicked: root.pendingHyprMode = "replace"
                                        }
                                        CtrlBtn {
                                            visible: PackageService.hyprSyncState !== "outdated"
                                            text: PackageService.hyprSyncing ? "Syncing..." : "Sync Defaults"
                                            ghost: PackageService.hyprSyncState === "synced"
                                            enabled: !PackageService.hyprSyncing && !PackageService.shellUpdating
                                            onClicked: root.pendingHyprMode = "replace"
                                        }
                                    }
                                }
                                ColumnLayout {
                                    visible: PackageService.hyprModifiedFiles.length > 0
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 16
                                    Layout.rightMargin: 16
                                    Layout.bottomMargin: 12
                                    spacing: 6

                                    Text {
                                        text: "Modified vs. defaults"
                                        color: Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        font.weight: Font.Medium
                                    }

                                    Repeater {
                                        model: PackageService.hyprModifiedFiles
                                        delegate: ColumnLayout {
                                            required property string modelData
                                            readonly property bool isSelected: PackageService.hyprDiffFile === modelData
                                            Layout.fillWidth: true
                                            spacing: 4

                                            Rectangle {
                                                id: modFileRow
                                                Layout.fillWidth: true
                                                height: 30
                                                radius: 8
                                                clip: true
                                                color: modFileMouse.containsMouse
                                                    ? Theme.cardHover
                                                    : (isSelected
                                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                                                        : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.035))
                                                border.width: 1
                                                border.color: isSelected
                                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                                                    : Theme.borderSubtle
                                                scale: modFileMouse.pressed ? 0.99 : 1.0
                                                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    spacing: 8

                                                    SvgIcon {
                                                        sourceName: "code"
                                                        iconSize: 13
                                                        color: isSelected ? Theme.accent : Theme.textSub
                                                    }

                                                    Text {
                                                        text: modelData
                                                        color: Theme.text
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 11
                                                        elide: Text.ElideMiddle
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 0
                                                    }

                                                    Text {
                                                        text: isSelected ? "Hide diff" : "Diff"
                                                        color: isSelected ? Theme.accent : Theme.textMuted
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: 10
                                                        font.weight: Font.Medium
                                                    }

                                                    SvgIcon {
                                                        sourceName: "chevron-right"
                                                        iconSize: 12
                                                        color: isSelected ? Theme.accent : Theme.textMuted
                                                        rotation: isSelected ? 90 : 0
                                                        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                    }
                                                }

                                                MouseArea {
                                                    id: modFileMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: PackageService.loadHyprFileDiff(modelData)
                                                }
                                            }

                                            Rectangle {
                                                visible: isSelected
                                                Layout.fillWidth: true
                                                implicitHeight: diffPanelCol.implicitHeight
                                                radius: 8
                                                clip: true
                                                color: Theme.surfaceRaised
                                                border.width: 1
                                                border.color: Theme.borderSubtle

                                                ColumnLayout {
                                                    id: diffPanelCol
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    spacing: 0

                                                    Rectangle {
                                                        Layout.fillWidth: true
                                                        height: 28
                                                        color: Theme.pillBg

                                                        RowLayout {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 10
                                                            anchors.rightMargin: 10
                                                            spacing: 6

                                                            Text {
                                                                text: "Manual edits vs. defaults"
                                                                color: Theme.textMuted
                                                                font.family: Theme.fontSans
                                                                font.pixelSize: 10
                                                                font.weight: Font.Medium
                                                                elide: Text.ElideRight
                                                                Layout.fillWidth: true
                                                                Layout.minimumWidth: 0
                                                            }

                                                            Rectangle {
                                                                visible: !PackageService.hyprDiffLoading && PackageService.hyprDiffAdded > 0
                                                                height: 18
                                                                implicitWidth: addBadgeTxt.implicitWidth + 10
                                                                radius: 5
                                                                color: Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.12)
                                                                border.width: 1
                                                                border.color: Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.35)

                                                                Text {
                                                                    id: addBadgeTxt
                                                                    anchors.centerIn: parent
                                                                    text: "+" + PackageService.hyprDiffAdded
                                                                    color: Theme.ok
                                                                    font.family: Theme.fontMono
                                                                    font.pixelSize: 10
                                                                    font.weight: Font.DemiBold
                                                                }
                                                            }

                                                            Rectangle {
                                                                visible: !PackageService.hyprDiffLoading && PackageService.hyprDiffDeleted > 0
                                                                height: 18
                                                                implicitWidth: delBadgeTxt.implicitWidth + 10
                                                                radius: 5
                                                                color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.12)
                                                                border.width: 1
                                                                border.color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.35)

                                                                Text {
                                                                    id: delBadgeTxt
                                                                    anchors.centerIn: parent
                                                                    text: "-" + PackageService.hyprDiffDeleted
                                                                    color: Theme.dangerText
                                                                    font.family: Theme.fontMono
                                                                    font.pixelSize: 10
                                                                    font.weight: Font.DemiBold
                                                                }
                                                            }
                                                        }

                                                        Rectangle {
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            anchors.bottom: parent.bottom
                                                            height: 1
                                                            color: Theme.borderSubtle
                                                        }
                                                    }

                                                    Item {
                                                        id: diffContentBox
                                                        Layout.fillWidth: true
                                                        Layout.margins: 6
                                                        implicitHeight: PackageService.hyprDiffLoading || PackageService.hyprDiffError !== ""
                                                            ? 24
                                                            : Math.min(220, diffLinesCol.implicitHeight)

                                                        Text {
                                                            visible: PackageService.hyprDiffLoading
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            anchors.left: parent.left
                                                            anchors.leftMargin: 4
                                                            text: "Loading diff..."
                                                            color: Theme.textMuted
                                                            font.family: Theme.fontMono
                                                            font.pixelSize: 11
                                                        }

                                                        Text {
                                                            visible: !PackageService.hyprDiffLoading && PackageService.hyprDiffError !== ""
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            anchors.leftMargin: 4
                                                            anchors.rightMargin: 4
                                                            text: PackageService.hyprDiffError
                                                            color: Theme.textSub
                                                            font.family: Theme.fontMono
                                                            font.pixelSize: 11
                                                            elide: Text.ElideRight
                                                        }

                                                        Flickable {
                                                            visible: !PackageService.hyprDiffLoading && PackageService.hyprDiffError === ""
                                                            anchors.fill: parent
                                                            contentWidth: width
                                                            contentHeight: diffLinesCol.implicitHeight
                                                            clip: true
                                                            boundsBehavior: Flickable.StopAtBounds

                                                            Column {
                                                                id: diffLinesCol
                                                                width: parent.width
                                                                spacing: 1

                                                                Repeater {
                                                                    model: isSelected ? PackageService.hyprDiffLines : []
                                                                    delegate: Rectangle {
                                                                        required property var modelData
                                                                        width: diffLinesCol.width
                                                                        height: diffRowLayout.implicitHeight + 4
                                                                        radius: 4
                                                                        clip: true
                                                                        color: modelData.type === "add"
                                                                            ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.10)
                                                                            : (modelData.type === "del"
                                                                                ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.10)
                                                                                : (modelData.type === "hunk"
                                                                                    ? Qt.rgba(Theme.info.r, Theme.info.g, Theme.info.b, 0.08)
                                                                                    : "transparent"))

                                                                        RowLayout {
                                                                            id: diffRowLayout
                                                                            anchors.left: parent.left
                                                                            anchors.right: parent.right
                                                                            anchors.verticalCenter: parent.verticalCenter
                                                                            anchors.leftMargin: 6
                                                                            anchors.rightMargin: 6
                                                                            spacing: 8

                                                                            Text {
                                                                                visible: modelData.type !== "hunk"
                                                                                Layout.preferredWidth: 28
                                                                                horizontalAlignment: Text.AlignRight
                                                                                text: modelData.line > 0 ? String(modelData.line) : ""
                                                                                color: Theme.textMuted
                                                                                font.family: Theme.fontMono
                                                                                font.pixelSize: 10
                                                                            }

                                                                            Text {
                                                                                Layout.fillWidth: true
                                                                                Layout.minimumWidth: 0
                                                                                text: modelData.text
                                                                                color: modelData.type === "add"
                                                                                    ? Theme.ok
                                                                                    : (modelData.type === "del"
                                                                                        ? Theme.dangerText
                                                                                        : (modelData.type === "hunk" ? Theme.info : Theme.textSub))
                                                                                font.family: Theme.fontMono
                                                                                font.pixelSize: 11
                                                                                wrapMode: Text.WrapAnywhere
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Text {
                                                        visible: !PackageService.hyprDiffLoading && PackageService.hyprDiffTruncated
                                                        Layout.fillWidth: true
                                                        Layout.leftMargin: 10
                                                        Layout.rightMargin: 10
                                                        Layout.bottomMargin: 6
                                                        text: "Showing first 200 diff lines"
                                                        color: Theme.textMuted
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 10
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    visible: PackageService.missingCoreDeps.length > 0
                                    showDivider: true
                                    iconName: "alert-triangle"
                                    title: "Required Shell Packages Missing"
                                    subtitle: PackageService.installingDeps
                                        ? ("Installing: " + PackageService.missingCorePkgs)
                                        : (PackageService.depsError !== ""
                                            ? PackageService.depsError
                                            : ("Mandatory dependencies missing (" + PackageService.missingCorePkgs + ")"))
                                    searchKeywords: "hyprcursor required dependencies cursor packages install"
                                    CtrlBtn {
                                        text: PackageService.installingDeps ? "Installing..." : "Install Required"
                                        enabled: !PackageService.installingDeps && !PackageService.shellUpdating
                                        onClicked: PackageService.installMissingCoreDeps()
                                    }
                                }
                            }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "package-update"
                                    title: "System Updates"
                                    subtitle: {
                                        if (PackageService.checking) return "Checking for available package updates...";
                                        if (PackageService.backingUpBeforeUpdate) return "Creating pre-update system backup...";
                                        if (PackageService.updating) return "Installing " + PackageService.selectedCount + (PackageService.selectedCount === 1 ? " package..." : " packages...");
                                        if (PackageService.lastError !== "") return PackageService.lastError;
                                        if (PackageService.updateCount > 0) {
                                            return PackageService.updateCount + (PackageService.updateCount === 1 ? " package available to upgrade" : " packages available to upgrade")
                                                + (PackageService.lastCheckedText !== "" ? " • Checked " + PackageService.lastCheckedText : "");
                                        }
                                        return "All packages are up to date" + (PackageService.lastCheckedText !== "" ? " • Checked " + PackageService.lastCheckedText : "");
                                    }
                                    RowLayout {
                                        spacing: 8
                                        CtrlBtn {
                                            text: PackageService.checking ? "Checking..." : "Check"
                                            ghost: true
                                            enabled: !PackageService.checking && !PackageService.updating && !PackageService.backingUpBeforeUpdate
                                            onClicked: PackageService.checkUpdates(true)
                                        }
                                        CtrlBtn {
                                            text: PackageService.backingUpBeforeUpdate
                                                ? "Backing up..."
                                                : (PackageService.updating
                                                    ? "Updating..."
                                                    : ((PackageService.backupBeforeUpdate ? "Backup & Update (" : "Update (") + PackageService.selectedCount + ")"))
                                            enabled: !PackageService.checking && !PackageService.updating && !PackageService.backingUpBeforeUpdate && PackageService.selectedCount > 0
                                            onClicked: PackageService.installSelected()
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "shield"
                                    title: PackageService.isMajorUpdate ? "Pre-Update System Backup  •  Major Update" : "Pre-Update System Backup"
                                    subtitle: {
                                        if (PackageService.backingUpBeforeUpdate) return "Creating system state archive before package upgrade...";
                                        if (PackageService.isMajorUpdate) return "Auto-enabled — " + PackageService.majorUpdateSummary;
                                        if (BackupService.lastSystemBackupTime !== "") {
                                            return "Last system backup at " + BackupService.lastSystemBackupTime + " • Toggle to snapshot before update";
                                        }
                                        return "Create a system snapshot & package manifest before installing updates";
                                    }
                                    searchKeywords: "backup snapshot btrfs major update pre-update"
                                    RowLayout {
                                        spacing: 8
                                        CtrlBtn {
                                            text: "Manage"
                                            ghost: true
                                            onClicked: root.openPage("backup")
                                        }
                                        CtrlSwitch {
                                            checked: PackageService.backupBeforeUpdate
                                            enabled: !PackageService.updating && !PackageService.backingUpBeforeUpdate
                                            onToggled: (v) => PackageService.setBackupBeforeUpdate(v)
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "package-update"
                                    title: "Automatic Updates"
                                    subtitle: "Schedule automatic package updates (Daily, Weekly, or Monthly)"
                                    searchKeywords: "auto update schedule daily weekly monthly timer"
                                    CtrlSelect {
                                        options: ["Off", "Daily", "Weekly", "Monthly"]
                                        currentText: {
                                            if (PackageService.autoUpdateSchedule === "daily") return "Daily";
                                            if (PackageService.autoUpdateSchedule === "weekly") return "Weekly";
                                            if (PackageService.autoUpdateSchedule === "monthly") return "Monthly";
                                            return "Off";
                                        }
                                        onSelected: (v) => PackageService.setAutoUpdateSchedule(v.toLowerCase())
                                    }
                                }
                                SettingRow {
                                    visible: PackageService.isFedora
                                    iconName: "package-update"
                                    title: "Beta Updates"
                                    subtitle: "Include Fedora testing repository (updates-testing) packages"
                                    searchKeywords: "beta testing updates-testing fedora"
                                    CtrlSwitch {
                                        checked: PackageService.betaUpdatesEnabled
                                        enabled: !PackageService.checking && !PackageService.updating && !PackageService.backingUpBeforeUpdate
                                        onToggled: (v) => PackageService.setBetaUpdatesEnabled(v)
                                    }
                                }
                                SettingRow {
                                    iconName: "trash"
                                    title: PackageService.cacheSizeText !== "" ? ("Package Cache  •  " + PackageService.cacheSizeText) : "Package Cache"
                                    subtitle: {
                                        if (PackageService.cleaningCache) return "Cleaning package manager cache... " + PackageService.cleanCacheProgress + "%";
                                        if (PackageService.isArch) return "Remove old & uninstalled packages from pacman cache (pacman -Sc)";
                                        if (PackageService.isFedora) return "Remove cached repository metadata and packages (dnf clean all)";
                                        if (PackageService.isDebian) return "Remove downloaded .deb archives from apt cache (apt-get clean)";
                                        return "Remove cached package manager files and metadata";
                                    }
                                    searchKeywords: "cache clean clear pacman dnf dnf5"
                                    CtrlBtn {
                                        text: PackageService.cleaningCache ? ("Cleaning... " + PackageService.cleanCacheProgress + "%") : "Clean Cache"
                                        ghost: true
                                        enabled: !PackageService.checking && !PackageService.updating && !PackageService.backingUpBeforeUpdate && !PackageService.cleaningCache
                                        onClicked: PackageService.cleanCache()
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                visible: PackageService.updateCount > 0
                                SectionLabel {
                                    Layout.fillWidth: true
                                    text: "Pending packages"
                                }
                                CtrlBtn {
                                    text: PackageService.selectedCount === PackageService.updateCount ? "Deselect all" : "Select all"
                                    ghost: true
                                    enabled: !PackageService.updating && !PackageService.backingUpBeforeUpdate
                                    onClicked: PackageService.setAllSelected(PackageService.selectedCount !== PackageService.updateCount)
                                }
                            }
                            SettingGroup {
                                visible: PackageService.updateCount > 0
                                Repeater {
                                    model: PackageService.packages
                                    delegate: SettingRow {
                                        required property var modelData
                                        required property int index
                                        showDivider: index > 0
                                        title: modelData.name
                                        subtitle: (modelData.oldVersion !== "" ? modelData.oldVersion + " → " : "") + modelData.newVersion
                                        CtrlTickBox {
                                            checked: modelData.selected
                                            enabled: !PackageService.updating && !PackageService.backingUpBeforeUpdate
                                            onToggled: PackageService.togglePackage(index)
                                        }
                                    }
                                }
                            }
                            SettingGroup {
                                visible: PackageService.updateCount === 0 && !PackageService.checking
                                SettingRow {
                                    showDivider: false
                                    iconName: "check"
                                    title: "No pending updates"
                                    subtitle: "Your system packages are on the latest available versions."
                                }
                            }
                        }
                        }

                        // ==================== 6b. BACKUP & RESTORE ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "backup"
                            active: Boolean(root.loadedPages["backup"])
                            sourceComponent: ColumnLayout {
                            spacing: 10

                            // Staged Rollback Banner (only visible after staging a rollback prior to reboot)
                            Rectangle {
                                visible: BackupService.stagedRollback !== null
                                Layout.fillWidth: true
                                implicitHeight: stagedCol.implicitHeight + 24
                                radius: 12
                                clip: true
                                color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.45)

                                ColumnLayout {
                                    id: stagedCol
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 2
                                            Text {
                                                Layout.fillWidth: true
                                                text: "System Rollback Staged — Reboot Required"
                                                color: Theme.warn
                                                font.family: Theme.fontSans
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: BackupService.stagedRollback
                                                    ? ("Target: " + (BackupService.stagedRollback.target_id || "")
                                                        + " • Kernel: " + (BackupService.stagedRollback.preferred_kernel || "auto")
                                                        + " • /home untouched • Previous root kept at " + (BackupService.stagedRollback.prev_name || ""))
                                                    : ""
                                                color: Theme.text
                                                font.family: Theme.fontSans
                                                font.pixelSize: 11
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                        CtrlBtn {
                                            text: "Undo Rollback"
                                            ghost: true
                                            enabled: !BackupService.busy
                                            onClicked: BackupService.undoStagedRollback()
                                        }
                                        CtrlBtn {
                                            text: "Reboot Now"
                                            danger: true
                                            enabled: !BackupService.busy
                                            onClicked: BackupService.rebootNow()
                                        }
                                    }
                                }
                            }

                            // Environment Transparency Card
                            SectionLabel { text: "Storage & Snapshot Transparency" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "hard-drive"
                                    title: BackupService.isBtrfsRoot
                                        ? ("Btrfs Root: subvol=" + (BackupService.btrfsInfo.rootSubvol || "root") + " (" + (BackupService.btrfsInfo.rootDevice || "/") + ")")
                                        : ("Root Filesystem: " + (BackupService.btrfsInfo.rootFstype || "unknown"))
                                    subtitle: (BackupService.btrfsInfo.homeSeparateSubvol ? "/home on separate subvolume (safe)" : "/home shared with /")
                                        + (BackupService.btrfsInfo.bootSeparate ? (" • /boot " + (BackupService.btrfsInfo.bootFstype || "") + " (" + (BackupService.btrfsInfo.kernelRunning || "") + (BackupService.btrfsInfo.vmlinuzExists ? " • OK" : " • Missing") + ")") : "")
                                    searchKeywords: "btrfs subvolume root home boot kernel transparency"
                                    CtrlBtn {
                                        text: "Refresh"
                                        ghost: true
                                        enabled: !BackupService.busy
                                        onClicked: BackupService.refreshAll()
                                    }
                                }
                                SettingRow {
                                    iconName: "shield"
                                    title: BackupService.btrfsInfo.polkitAgentActive ? "Privilege Mode: Polkit Agent" : "Privilege Mode: Secure Sudo Prompt (stdin)"
                                    subtitle: "Free disk space: " + BackupService.formatBytes(Number(BackupService.btrfsInfo.diskAvailBytes || 0))
                                        + " (" + (BackupService.btrfsInfo.diskUsedPct || 0) + "% used)"
                                        + ((BackupService.btrfsInfo.diskUsedPct || 0) >= 85 ? " • Low disk space" : "")
                                        + (BackupService.systemBackups.length > 10 ? (" • " + BackupService.systemBackups.length + " snapshots stored") : "")
                                    searchKeywords: "polkit sudo disk space elevation"
                                }
                            }

                            SectionLabel { text: "System Backup (Btrfs Snapshot & Rollback)" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "shield"
                                    title: "System Backup"
                                    subtitle: {
                                        if (BackupService.backingUpSystem || BackupService.verifying || BackupService.rollingBack) return BackupService.statusText;
                                        return BackupService.isBtrfsRoot
                                            ? "Flat top-level @paithosh-snapshots + Package/Config archive"
                                            : "Package manifest & /etc config archive (.tar.gz)";
                                    }
                                    searchKeywords: "system backup snapshot btrfs packages etc rollback"
                                    RowLayout {
                                        spacing: 8
                                        CtrlBtn {
                                            text: "Open Folder"
                                            ghost: true
                                            onClicked: {
                                                if (root.shellState) root.shellState.openFilesAt(BackupService.systemBackupDir);
                                                else BackupService.openBackupFolder("system");
                                            }
                                        }
                                        CtrlBtn {
                                            text: BackupService.backingUpSystem ? "Snapshotting..." : "Backup System"
                                            enabled: !BackupService.busy
                                            onClicked: BackupService.createSystemBackup("Manual system backup", false, null)
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "refresh"
                                    title: "Auto-backup before major updates"
                                    subtitle: "Automatically turn on System Backup when updating kernel, hyprland, mesa, systemd or ≥10 packages"
                                    searchKeywords: "auto backup major update kernel hyprland mesa systemd"
                                    CtrlSwitch {
                                        checked: PackageService.autoBackupMajorUpdates
                                        onToggled: (v) => PackageService.setAutoBackupMajorUpdates(v)
                                    }
                                }
                                SettingRow {
                                    visible: BackupService.isBtrfsRoot
                                    iconName: "hard-drive"
                                    title: "Include Btrfs root subvolume snapshot"
                                    subtitle: "Verified read-only snapshot of subvol=" + (BackupService.btrfsInfo.rootSubvol || "root") + " at top-level @paithosh-snapshots"
                                    searchKeywords: "btrfs subvolume snapshot root top-level rollback"
                                    CtrlSwitch {
                                        checked: BackupService.useBtrfsSnapshot
                                        onToggled: (v) => BackupService.setUseBtrfsSnapshot(v)
                                    }
                                }
                            }

                            // System Error Banner (isolated from Data errors)
                            Rectangle {
                                visible: BackupService.systemError !== ""
                                Layout.fillWidth: true
                                implicitHeight: sysErrText.implicitHeight + 16
                                radius: 10
                                clip: true
                                color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.40)

                                Text {
                                    id: sysErrText
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    text: "System Backup Error: " + BackupService.systemError
                                    color: Theme.dangerText
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                }
                            }

                            // Live Audit Steps Card
                            Rectangle {
                                visible: (BackupService.lastAuditSteps || []).length > 0
                                Layout.fillWidth: true
                                implicitHeight: auditCol.implicitHeight + 18
                                radius: 10
                                clip: true
                                color: Theme.cardBg
                                border.width: 1
                                border.color: Theme.borderSubtle

                                ColumnLayout {
                                    id: auditCol
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    spacing: 4

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Audit Trail"
                                        color: Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                    Repeater {
                                        model: BackupService.lastAuditSteps
                                        delegate: RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 6
                                            SvgIcon {
                                                sourceName: modelData.status === "ok" ? "check" : (modelData.status === "warn" ? "alert-triangle" : (modelData.status === "fail" ? "close" : "circle-dot"))
                                                iconSize: 12
                                                color: modelData.status === "ok" ? Theme.ok : (modelData.status === "warn" ? Theme.warn : (modelData.status === "fail" ? Theme.dangerText : Theme.info))
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: modelData.detail
                                                color: Theme.text
                                                font.family: Theme.fontSans
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }

                            SectionLabel { text: "User Data Backup (.pak Store & Restore)" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "archive"
                                    title: "Data Backup (.pak Archive)"
                                    subtitle: (BackupService.backingUpData || BackupService.restoringData || BackupService.importingPak)
                                        ? BackupService.statusText
                                        : ("Standard ZIP archive saved as .pak • " + BackupService.selectedFolderCount + " folders selected")
                                    searchKeywords: "data backup pak zip store home folders documents projects"
                                    RowLayout {
                                        spacing: 8
                                        CtrlBtn {
                                            text: "Open Store"
                                            ghost: true
                                            onClicked: {
                                                if (root.shellState) root.shellState.openFilesAt(BackupService.dataBackupDir);
                                                else BackupService.openBackupFolder("data");
                                            }
                                        }
                                        CtrlBtn {
                                            text: "Restore .pak..."
                                            ghost: true
                                            enabled: !BackupService.busy
                                            onClicked: {
                                                if (root.shellState) {
                                                    root.shellState.openFilePicker({
                                                        title: "Select .pak Backup File",
                                                        acceptLabel: "Inspect / Restore",
                                                        sourceLabel: "Backup & Restore",
                                                        initialFolder: BackupService.dataBackupDir,
                                                        returnSettingsPage: "backup",
                                                        filters: [{ label: "Paithosh Data Backup (*.pak)", patterns: [{ kind: 0, pattern: "*.pak" }] }],
                                                        onSelected: function(path) {
                                                            if (path && path !== "") BackupService.inspectPak(path);
                                                        }
                                                    });
                                                }
                                            }
                                        }
                                        CtrlBtn {
                                            text: BackupService.backingUpData ? "Packing .pak..." : ("Backup Data (" + BackupService.selectedFolderCount + ")")
                                            enabled: !BackupService.busy && BackupService.selectedFolderCount > 0
                                            onClicked: BackupService.createDataBackup()
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "folder"
                                    title: ".pak Store Folder"
                                    subtitle: BackupService.dataBackupDir
                                    searchKeywords: "pak store folder directory path"
                                    CtrlBtn {
                                        text: "Change Folder"
                                        ghost: true
                                        enabled: !BackupService.busy
                                        onClicked: {
                                            if (root.shellState) {
                                                root.shellState.openFolderPicker({
                                                    title: "Select .pak Store Directory",
                                                    acceptLabel: "Use Store Folder",
                                                    sourceLabel: "Backup Store",
                                                    initialFolder: BackupService.dataBackupDir,
                                                    returnSettingsPage: "backup",
                                                    onSelected: function(path) {
                                                        if (path && path !== "") BackupService.setDataStoreDir(path);
                                                    }
                                                });
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "bolt"
                                    title: "Exclude cache & build artifacts"
                                    subtitle: "Skip .cache, node_modules, target, __pycache__ & venv (keeps .git intact)"
                                    searchKeywords: "exclude cache node_modules target venv"
                                    CtrlSwitch {
                                        checked: BackupService.excludeHeavyCache
                                        onToggled: (v) => BackupService.setExcludeHeavyCache(v)
                                    }
                                }
                            }

                            // Data Error Banner (isolated from System errors)
                            Rectangle {
                                visible: BackupService.dataError !== ""
                                Layout.fillWidth: true
                                implicitHeight: dataErrText.implicitHeight + 16
                                radius: 10
                                clip: true
                                color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.40)

                                Text {
                                    id: dataErrText
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    text: "Data Backup Error: " + BackupService.dataError
                                    color: Theme.dangerText
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                SectionLabel {
                                    Layout.fillWidth: true
                                    text: "Important /home folders"
                                }
                                CtrlBtn {
                                    text: (BackupService.existingFolderCount > 0 && BackupService.selectedFolderCount === BackupService.existingFolderCount) ? "Deselect all" : "Select all"
                                    ghost: true
                                    enabled: !BackupService.busy && BackupService.existingFolderCount > 0
                                    onClicked: BackupService.setAllDataFolders(BackupService.selectedFolderCount !== BackupService.existingFolderCount)
                                }
                            }
                            SettingGroup {
                                Repeater {
                                    model: BackupService.dataFolders
                                    delegate: SettingRow {
                                        required property var modelData
                                        required property int index
                                        showDivider: index > 0
                                        title: modelData.label
                                        subtitle: "~/" + modelData.relPath + (modelData.exists ? (modelData.sizeText !== "" ? " • " + modelData.sizeText : " • Ready") : " • Not found")
                                        CtrlTickBox {
                                            checked: modelData.selected
                                            enabled: !BackupService.busy && modelData.exists
                                            onToggled: BackupService.toggleDataFolder(index)
                                        }
                                    }
                                }
                            }

                            SectionLabel { text: "Saved system snapshots (" + BackupService.systemBackups.length + ")" }
                            SettingGroup {
                                Repeater {
                                    model: BackupService.systemBackups
                                    delegate: SettingRow {
                                        required property var modelData
                                        required property int index
                                        showDivider: index > 0
                                        iconName: modelData.hasBtrfsSnap ? "shield" : "hard-drive"
                                        title: modelData.id
                                        subtitle: (modelData.dateText || "Unknown")
                                            + (modelData.sizeText !== "" ? (" • " + modelData.sizeText) : "")
                                            + (modelData.hasBtrfsSnap
                                                ? (" • Btrfs Verified" + (modelData.kernel ? (" (" + modelData.kernel + ")") : ""))
                                                : " • Archive Only (No Btrfs Snapshot)")
                                            + (modelData.reason !== "" ? (" • " + modelData.reason) : "")
                                        RowLayout {
                                            spacing: 6
                                            CtrlBtn {
                                                visible: modelData.hasBtrfsSnap
                                                text: "Verify"
                                                ghost: true
                                                enabled: !BackupService.busy
                                                onClicked: BackupService.verifySystemBackup(modelData.id)
                                            }
                                            CtrlBtn {
                                                visible: modelData.hasBtrfsSnap && !modelData.isPreRollback
                                                text: "Rollback"
                                                ghost: true
                                                danger: true
                                                enabled: !BackupService.busy && BackupService.stagedRollback === null
                                                onClicked: BackupService.requestRollbackSystemBackup(modelData.id)
                                            }
                                            CtrlBtn {
                                                text: "Delete"
                                                ghost: true
                                                enabled: !BackupService.busy
                                                onClicked: BackupService.deleteBackup("system", modelData.id, modelData.hasBtrfsSnap)
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    visible: BackupService.systemBackups.length === 0
                                    showDivider: false
                                    iconName: "shield"
                                    title: "No system backups yet"
                                    subtitle: "Run Backup System above or enable Pre-Update System Backup when updating packages."
                                }
                            }

                            SectionLabel { text: ".pak Data Store (" + BackupService.dataBackups.length + ")" }
                            SettingGroup {
                                Repeater {
                                    model: BackupService.dataBackups
                                    delegate: SettingRow {
                                        required property var modelData
                                        required property int index
                                        showDivider: index > 0
                                        iconName: "archive"
                                        title: modelData.name
                                        subtitle: modelData.dateText + " • " + modelData.sizeText
                                            + (modelData.corrupt ? " • Corrupt Archive" : (modelData.legacyZip ? " • Legacy .zip" : " • .pak (ZIP)"))
                                            + (modelData.fileCount > 0 ? (" • " + modelData.fileCount + " files") : "")
                                            + (modelData.foldersText !== "" ? (" • " + modelData.foldersText) : "")
                                        RowLayout {
                                            spacing: 6
                                            CtrlBtn {
                                                text: "Inspect"
                                                ghost: true
                                                enabled: !BackupService.busy
                                                onClicked: BackupService.inspectPak(modelData.path)
                                            }
                                            CtrlBtn {
                                                text: (BackupService.restoringData && BackupService.activeRestorePath === modelData.path) ? "Restoring..." : "Restore"
                                                ghost: true
                                                enabled: !BackupService.busy && !modelData.corrupt
                                                onClicked: BackupService.restoreDataBackup(modelData.path, "staged", "")
                                            }
                                            CtrlBtn {
                                                text: "Delete"
                                                ghost: true
                                                enabled: !BackupService.busy
                                                onClicked: BackupService.deleteBackup("data", modelData.path, false)
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    visible: BackupService.dataBackups.length === 0
                                    showDivider: false
                                    iconName: "minus"
                                    title: "No .pak backups in store yet"
                                    subtitle: "Select /home folders above and click Backup Data to save a .pak file, or import an existing .pak."
                                }
                            }
                        }
                        }

                        // ==================== 7. NETWORK ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "network"
                            active: Boolean(root.loadedPages["network"])
                            sourceComponent: ColumnLayout {
                            spacing: 10
                            SectionLabel { text: "Network options" }
                            HubCard { iconName: "wifi"; title: "Wi-Fi"; subtitle: "Wireless networks, SSID & signal"; pillText: NetworkService.wifiEnabled ? NetworkService.activeSsid : "Off"; onTriggered: { root.openPage("wifi"); NetworkService.refreshNetworks(true); } }
                            HubCard { iconName: "shield"; title: "VPN & Proxy"; subtitle: "WireGuard tunnels & HTTP proxy"; pillText: VpnProxyService.vpnActive ? ("WireGuard • " + VpnProxyService.activeTunnel) : "WireGuard • Standby"; onTriggered: root.openPage("vpn") }
                            HubCard {
                                iconName: "message-square"
                                title: "Discord RPC"
                                subtitle: "Live presence & Linux larper persona"
                                pillText: !DiscordRpcService.enabled ? "Off" : (DiscordRpcService.connected ? "Connected" : "Discord Offline")
                                onTriggered: root.openPage("discord_rpc")
                            }
                            HubCard { iconName: "globe"; title: "DNS & Routing"; subtitle: "Encrypted DoH & split-horizon"; pillText: "1.1.1.1 • DoH Active"; onTriggered: {} }
                            HubCard { iconName: "smartphone"; title: "KDE Connect & Share"; subtitle: "Local LAN pairing & file drop"; pillText: "Pixel 8 Pro • Paired"; onTriggered: {} }

                            SectionLabel { text: "Nearby settings" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconName: "wifi"; title: "Wi-Fi Radio (wlan0)"; subtitle: "Connected to Paithon_5G • 5 GHz WPA3"
                                    CtrlSwitch { checked: NetworkService.wifiEnabled; onToggled: (v) => NetworkService.setWifiEnabled(v) }
                                }
                                SettingRow {
                                    iconName: "plane"; title: "Airplane mode"; subtitle: "Stop all wireless communication"
                                    CtrlSwitch { checked: root.airplaneMode; onToggled: (v) => root.airplaneMode = v }
                                }
                                SettingRow {
                                    iconName: "globe"; title: "DNS Provider"; subtitle: "Resolver used for all system queries"
                                    CtrlSelect { options: ["Cloudflare (1.1.1.1)", "Quad9 (9.9.9.9)", "System Auto (DHCP)"]; currentText: root.dnsProvider; onSelected: (v) => root.dnsProvider = v }
                                }
                                SettingRow {
                                    iconName: "gauge"; title: "Metered connection"; subtitle: "Pause automatic background package sync"
                                    CtrlSwitch { checked: root.meteredConn; onToggled: (v) => root.meteredConn = v }
                                }
                            }
                        }
                        }

                        // ==================== 8. WIFI ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "wifi"
                            active: Boolean(root.loadedPages["wifi"])
                            sourceComponent: ColumnLayout {
                            spacing: 10
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconName: "wifi"
                                    title: "Wi-Fi Adapter (" + NetworkService.wifiDevice + ")"
                                    subtitle: NetworkService.wifiEnabled
                                        ? (NetworkService.activeSsid !== "Disconnected" ? ("Connected to " + NetworkService.activeSsid) : "Not connected")
                                        : "Wi-Fi is turned off"
                                    CtrlSwitch { checked: NetworkService.wifiEnabled; onToggled: (v) => NetworkService.setWifiEnabled(v) }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: NetworkService.wifiEnabled
                                SectionLabel { text: "Available networks"; Layout.fillWidth: true }
                                CtrlBtn {
                                    text: NetworkService.scanning ? "Scanning..." : "Scan"
                                    ghost: true
                                    onClicked: NetworkService.refreshNetworks(true)
                                }
                            }

                            Text {
                                visible: NetworkService.lastError !== ""
                                text: NetworkService.lastError
                                color: "#ff6b6b"
                                font.family: Theme.fontSans
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            SettingGroup {
                                visible: root.wifiShowPrompt && NetworkService.wifiEnabled
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: promptCol.implicitHeight + 24
                                    ColumnLayout {
                                        id: promptCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                                        spacing: 8
                                    Text {
                                        text: root.wifiPromptHidden ? "Join hidden network" : ("Connect to " + root.wifiPromptSsid)
                                        color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.Medium
                                    }
                                    Rectangle {
                                        visible: root.wifiPromptHidden
                                        Layout.fillWidth: true; height: 32; radius: 6
                                        color: Qt.rgba(1, 1, 1, 0.06); border.color: Qt.rgba(1, 1, 1, 0.14); border.width: 1
                                        AnimatedTextInput {
                                            anchors.fill: parent; anchors.margins: 8
                                            textColor: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12
                                            verticalAlignment: TextInput.AlignVCenter
                                            text: root.wifiPromptSsid
                                            onTextChanged: root.wifiPromptSsid = text
                                            Keys.onEscapePressed: (event) => {
                                                focus = false;
                                                event.accepted = true;
                                            }
                                            Text {
                                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                                text: "Network SSID"; color: Theme.textSub; font: parent.font
                                                visible: parent.text === ""
                                            }
                                        }
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true; height: 32; radius: 6
                                        color: Qt.rgba(1, 1, 1, 0.06); border.color: Qt.rgba(1, 1, 1, 0.14); border.width: 1
                                        AnimatedTextInput {
                                            anchors.fill: parent; anchors.margins: 8
                                            textColor: Theme.text; font.family: Theme.fontSans; font.pixelSize: 12
                                            verticalAlignment: TextInput.AlignVCenter
                                            echoMode: TextInput.Password
                                            text: root.wifiPromptPassword
                                            onTextChanged: root.wifiPromptPassword = text
                                            Keys.onEscapePressed: (event) => {
                                                focus = false;
                                                event.accepted = true;
                                            }
                                            onAccepted: {
                                                NetworkService.connectToNetwork(root.wifiPromptSsid, root.wifiPromptPassword, root.wifiPromptHidden);
                                                root.wifiShowPrompt = false;
                                                root.wifiPromptPassword = "";
                                            }
                                            Text {
                                                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                                text: root.wifiPromptHidden ? "Password (optional)" : "Password"
                                                color: Theme.textSub; font: parent.font
                                                visible: parent.text === ""
                                            }
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        Item { Layout.fillWidth: true }
                                        CtrlBtn {
                                            text: "Cancel"; ghost: true
                                            onClicked: { root.wifiShowPrompt = false; root.wifiPromptPassword = ""; }
                                        }
                                        CtrlBtn {
                                            text: "Connect"
                                            onClicked: {
                                                NetworkService.connectToNetwork(root.wifiPromptSsid, root.wifiPromptPassword, root.wifiPromptHidden);
                                                root.wifiShowPrompt = false;
                                                root.wifiPromptPassword = "";
                                            }
                                        }
                                    }
                                    }
                                }
                            }

                            SettingGroup {
                                visible: NetworkService.wifiEnabled
                                Repeater {
                                    model: NetworkService.networks
                                    delegate: SettingRow {
                                        required property var modelData
                                        required property int index
                                        showDivider: index > 0
                                        iconName: {
                                            const s = Number(modelData.signal || 0);
                                            if (s >= 75) return "wifi-4";
                                            if (s >= 50) return "wifi-3";
                                            if (s >= 25) return "wifi-2";
                                            return "wifi-1";
                                        }
                                        iconColor: modelData.inUse ? Theme.accent : Theme.textSub
                                        title: modelData.ssid
                                        subtitle: {
                                            const parts = [];
                                            parts.push(modelData.inUse ? "Connected" : (modelData.security ? "Secured" : "Open"));
                                            if (modelData.band) parts.push(modelData.band);
                                            if (modelData.security) parts.push(modelData.security);
                                            parts.push(modelData.signal + "%");
                                            return parts.join(" • ");
                                        }
                                        CtrlBtn {
                                            text: modelData.inUse
                                                ? "Disconnect"
                                                : (NetworkService.connecting && NetworkService.connectingSsid === modelData.ssid ? "Connecting..." : "Connect")
                                            ghost: true
                                            onClicked: {
                                                if (modelData.inUse) {
                                                    NetworkService.disconnectActive();
                                                } else if (modelData.security && modelData.security !== "") {
                                                    root.wifiPromptHidden = false;
                                                    root.wifiPromptSsid = modelData.ssid;
                                                    root.wifiPromptPassword = "";
                                                    root.wifiShowPrompt = true;
                                                } else {
                                                    NetworkService.connectToNetwork(modelData.ssid, "", false);
                                                }
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    showDivider: NetworkService.networks.length > 0
                                    iconName: "plus"; title: "Hidden network"; subtitle: "Enter SSID manually"
                                    CtrlBtn {
                                        text: "Join"
                                        onClicked: {
                                            root.wifiPromptHidden = true;
                                            root.wifiPromptSsid = "";
                                            root.wifiPromptPassword = "";
                                            root.wifiShowPrompt = true;
                                        }
                                    }
                                }
                            }
                        }
                        }

                        // ==================== 9. VPN ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "vpn"
                            active: Boolean(root.loadedPages["vpn"])
                            sourceComponent: ColumnLayout {
                            id: vpnPage
                            spacing: 12
                            property bool showNewConfig: false

                            SectionLabel { text: "WIREGUARD (WG-QUICK)" }

                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "shield"
                                    title: VpnProxyService.vpnActive ? ("Active: " + VpnProxyService.activeTunnel) : "No active tunnel"
                                    subtitle: VpnProxyService.vpnActive
                                        ? ("Endpoint: " + VpnProxyService.vpnEndpoint + " • DNS: " + VpnProxyService.vpnDns)
                                        : "Import or paste a wg-quick .conf file to connect"
                                    RowLayout {
                                        spacing: 6
                                        CtrlBtn {
                                            text: "Import .conf"
                                            onClicked: VpnProxyService.importConfigFile()
                                        }
                                        CtrlBtn {
                                            text: vpnPage.showNewConfig ? "Cancel" : "Paste Config"
                                            onClicked: vpnPage.showNewConfig = !vpnPage.showNewConfig
                                        }
                                        CtrlBtn {
                                            iconName: "refresh"
                                            ghost: true
                                            onClicked: VpnProxyService.refresh()
                                        }
                                    }
                                }
                            }

                            // Error banner
                            Rectangle {
                                Layout.fillWidth: true
                                visible: VpnProxyService.lastError !== ""
                                implicitHeight: vpnErrText.implicitHeight + 16
                                radius: 10
                                color: Qt.rgba(0.95, 0.25, 0.25, 0.14)
                                border.width: 1
                                border.color: Qt.rgba(0.95, 0.35, 0.35, 0.45)
                                Text {
                                    id: vpnErrText
                                    anchors.fill: parent; anchors.margins: 8
                                    text: VpnProxyService.lastError
                                    color: "#ff8a8a"
                                    font.family: Theme.fontSans; font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                }
                            }

                            // Paste / New wg-quick config form
                            Rectangle {
                                Layout.fillWidth: true
                                visible: vpnPage.showNewConfig
                                implicitHeight: newCfgCol.implicitHeight + 20
                                radius: 12
                                color: Theme.cardBg
                                border.width: 1; border.color: Theme.borderSubtle

                                ColumnLayout {
                                    id: newCfgCol
                                    anchors.fill: parent; anchors.margins: 10
                                    spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        Text { text: "Tunnel name:"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11 }
                                        Rectangle {
                                            Layout.fillWidth: true; height: 28; radius: 7
                                            color: Theme.pillBg; border.width: 1; border.color: Theme.borderSubtle
                                            TextInput {
                                                id: newTunnelName
                                                anchors.fill: parent; anchors.margins: 6
                                                color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11
                                                text: "wg0"
                                                clip: true
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true; height: 110; radius: 8
                                        color: Theme.pillBg; border.width: 1; border.color: Theme.borderSubtle
                                        Flickable {
                                            anchors.fill: parent; anchors.margins: 6
                                            contentWidth: width; contentHeight: newTunnelBody.implicitHeight
                                            clip: true
                                            TextEdit {
                                                id: newTunnelBody
                                                width: parent.width
                                                color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 10
                                                wrapMode: TextEdit.Wrap
                                                text: "[Interface]\nPrivateKey = \nAddress = 10.0.0.2/32\nDNS = 1.1.1.1\n\n[Peer]\nPublicKey = \nEndpoint = \nAllowedIPs = 0.0.0.0/0"
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Item { Layout.fillWidth: true }
                                        CtrlBtn {
                                            text: "Save .conf"
                                            onClicked: {
                                                if (VpnProxyService.saveConfigText(newTunnelName.text, newTunnelBody.text)) {
                                                    vpnPage.showNewConfig = false;
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Tunnel list
                            SettingGroup {
                                visible: VpnProxyService.tunnels.length > 0
                                Repeater {
                                    model: VpnProxyService.tunnels
                                    SettingRow {
                                        required property var modelData
                                        required property int index
                                        showDivider: index > 0
                                        iconName: modelData.active ? "circle-dot" : "circle"
                                        title: modelData.name + (modelData.active ? " (Connected)" : "")
                                        subtitle: "Endpoint: " + modelData.endpoint + " • DNS: " + modelData.dns
                                        RowLayout {
                                            spacing: 8
                                            CtrlBtn {
                                                visible: modelData.userOwned && !modelData.active
                                                text: "Delete"
                                                onClicked: VpnProxyService.deleteConfig(modelData.name)
                                            }
                                            CtrlSwitch {
                                                checked: modelData.active
                                                opacity: (VpnProxyService.busy && VpnProxyService.busyTunnel === modelData.name) ? 0.5 : 1.0
                                                onToggled: () => VpnProxyService.toggleTunnel(modelData.name)
                                            }
                                        }
                                    }
                                }
                            }

                            SectionLabel { text: "SYSTEM PROXY" }

                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: "repeat"
                                    title: "Enable System Proxy"
                                    subtitle: "Apply gsettings proxy & ~/.config/paithosh/proxy.env"
                                    CtrlSwitch {
                                        checked: VpnProxyService.proxyEnabled
                                        onToggled: (v) => VpnProxyService.applyProxySettings(
                                            v, httpHostInput.text, httpPortInput.text,
                                            socksHostInput.text, socksPortInput.text, VpnProxyService.noProxy
                                        )
                                    }
                                }
                                SettingRow {
                                    title: "HTTP / HTTPS Proxy"
                                    subtitle: "Host and port for HTTP/HTTPS traffic"
                                    RowLayout {
                                        spacing: 6
                                        Rectangle {
                                            width: 120; height: 26; radius: 6
                                            color: Theme.pillBg; border.width: 1; border.color: Theme.borderSubtle
                                            TextInput {
                                                id: httpHostInput
                                                anchors.fill: parent; anchors.margins: 5
                                                color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11
                                                text: VpnProxyService.proxyHost
                                                clip: true
                                            }
                                        }
                                        Rectangle {
                                            width: 64; height: 26; radius: 6
                                            color: Theme.pillBg; border.width: 1; border.color: Theme.borderSubtle
                                            TextInput {
                                                id: httpPortInput
                                                anchors.fill: parent; anchors.margins: 5
                                                color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11
                                                text: String(VpnProxyService.proxyPort)
                                                clip: true
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    title: "SOCKS5 Proxy"
                                    subtitle: "Host and port for SOCKS5 traffic"
                                    RowLayout {
                                        spacing: 6
                                        Rectangle {
                                            width: 120; height: 26; radius: 6
                                            color: Theme.pillBg; border.width: 1; border.color: Theme.borderSubtle
                                            TextInput {
                                                id: socksHostInput
                                                anchors.fill: parent; anchors.margins: 5
                                                color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11
                                                text: VpnProxyService.socksHost
                                                clip: true
                                            }
                                        }
                                        Rectangle {
                                            width: 64; height: 26; radius: 6
                                            color: Theme.pillBg; border.width: 1; border.color: Theme.borderSubtle
                                            TextInput {
                                                id: socksPortInput
                                                anchors.fill: parent; anchors.margins: 5
                                                color: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11
                                                text: String(VpnProxyService.socksPort)
                                                clip: true
                                            }
                                        }
                                        CtrlBtn {
                                            text: VpnProxyService.proxyBusy ? "Saving..." : "Apply"
                                            onClicked: VpnProxyService.applyProxySettings(
                                                VpnProxyService.proxyEnabled, httpHostInput.text, httpPortInput.text,
                                                socksHostInput.text, socksPortInput.text, VpnProxyService.noProxy
                                            )
                                        }
                                    }
                                }
                            }
                        }
                        }

                        // ==================== 9b. DISCORD RPC ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "discord_rpc"
                            active: Boolean(root.loadedPages["discord_rpc"])
                            sourceComponent: ColumnLayout {
                                id: rpcPage
                                spacing: 12

                                // Live Presence Preview Card (concentric r:12, semantic status border)
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: rpcPreviewCol.implicitHeight + 28
                                    radius: 12
                                    clip: true
                                    color: Theme.cardBg
                                    border.width: 1
                                    border.color: !DiscordRpcService.enabled
                                        ? Theme.borderSubtle
                                        : (DiscordRpcService.connected
                                            ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.42)
                                            : Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.42))
                                    Behavior on border.color { ColorAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                    ColumnLayout {
                                        id: rpcPreviewCol
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        spacing: 10

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 10

                                            Rectangle {
                                                Layout.alignment: Qt.AlignVCenter
                                                width: 34; height: 34; radius: 10; clip: true
                                                color: Theme.surfaceRaised
                                                border.width: 1
                                                border.color: Theme.borderSubtle
                                                SvgIcon {
                                                    anchors.centerIn: parent
                                                    sourceName: "terminal"
                                                    iconSize: 16
                                                    color: DiscordRpcService.connected ? Theme.ok : (DiscordRpcService.enabled ? Theme.warn : Theme.textMuted)
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                Layout.alignment: Qt.AlignVCenter
                                                spacing: 2

                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: "Live Discord Presence"
                                                    color: Theme.text
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 14
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: DiscordRpcService.connected
                                                        ? ((DiscordRpcService.currentDetails || "Paithosh Shell") + " • " + (DiscordRpcService.currentState || "Wayland"))
                                                        : (!DiscordRpcService.enabled
                                                            ? "Presence paused — toggle below to broadcast again"
                                                            : "Waiting for Discord IPC socket (auto-connects when Discord opens)")
                                                    color: Theme.textSub
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 12
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            Rectangle {
                                                readonly property bool showStatusPill: !DiscordRpcService.connected
                                                Layout.alignment: Qt.AlignVCenter
                                                Layout.preferredWidth: showStatusPill ? (statusPillLbl.implicitWidth + 14) : 0
                                                height: 22
                                                radius: 11
                                                clip: true
                                                opacity: showStatusPill ? 1.0 : 0.0
                                                color: !DiscordRpcService.enabled
                                                    ? Theme.surfaceRaised
                                                    : Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.14)
                                                border.width: showStatusPill ? 1 : 0
                                                border.color: !DiscordRpcService.enabled
                                                    ? Theme.borderSubtle
                                                    : Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.38)
                                                Behavior on Layout.preferredWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                                Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Text {
                                                    id: statusPillLbl
                                                    anchors.centerIn: parent
                                                    text: !DiscordRpcService.enabled ? "DISABLED" : "DISCORD OFFLINE"
                                                    color: !DiscordRpcService.enabled ? Theme.textMuted : Theme.warn
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                }
                                            }

                                            CtrlBtn {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: "Reroll"
                                                enabled: DiscordRpcService.enabled && DiscordRpcService.connected && DiscordRpcService.preset !== "custom"
                                                opacity: enabled ? 1.0 : 0.45
                                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                                onClicked: DiscordRpcService.reroll()
                                            }
                                        }
                                    }
                                }

                                // Presets-First Progressive Disclosure
                                SectionLabel { text: "Larper Persona Presets" }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    columnSpacing: 10
                                    rowSpacing: 10

                                    PresetCard {
                                        title: "Time-of-Day Vibe"
                                        subtitle: "Rotates chill status lines from morning coffee to 3AM debugging"
                                        badge: "Auto"
                                        searchKeywords: "discord rpc auto time morning night"
                                        active: DiscordRpcService.preset === "auto"
                                        onTriggered: DiscordRpcService.preset = "auto"
                                    }
                                    PresetCard {
                                        title: "Elite Linux Larper"
                                        subtitle: "Compiling kernels with -O3 & benchmarking 0.2ms bar latency"
                                        badge: "Flex"
                                        searchKeywords: "discord rpc larper linux rice hyprland kernel"
                                        active: DiscordRpcService.preset === "larper"
                                        onTriggered: DiscordRpcService.preset = "larper"
                                    }
                                    PresetCard {
                                        title: "Honest Paithosh"
                                        subtitle: "Entirely vibecoded satire — actually daily-driving KDE on Fedora"
                                        badge: "README"
                                        searchKeywords: "discord rpc satire honest readme kde fedora vibecoded"
                                        active: DiscordRpcService.preset === "satire"
                                        onTriggered: DiscordRpcService.preset = "satire"
                                    }
                                    PresetCard {
                                        title: "Stealth Minimal"
                                        subtitle: "Clean, understated Paithosh Shell • Wayland status"
                                        badge: "Clean"
                                        searchKeywords: "discord rpc minimal clean stealth"
                                        active: DiscordRpcService.preset === "minimal"
                                        onTriggered: DiscordRpcService.preset = "minimal"
                                    }
                                    PresetCard {
                                        title: "Now Playing"
                                        subtitle: "Live track & artist from Mixcloud or MPRIS media player"
                                        badge: "Music"
                                        searchKeywords: "discord rpc music now playing mixcloud mpris track"
                                        active: DiscordRpcService.preset === "music"
                                        onTriggered: DiscordRpcService.preset = "music"
                                    }
                                    PresetCard {
                                        title: "Mixcloud & DJ Vibe"
                                        subtitle: "Curated DJ set & sidechain RMS audio ducking status lines"
                                        badge: "DJ"
                                        searchKeywords: "discord rpc dj mixcloud music sidechain ducking"
                                        active: DiscordRpcService.preset === "dj"
                                        onTriggered: DiscordRpcService.preset = "dj"
                                    }
                                    PresetCard {
                                        Layout.columnSpan: 2
                                        title: "Custom Flex"
                                        subtitle: "Write your own two-line Discord presence with instant live sync"
                                        badge: "Custom"
                                        searchKeywords: "discord rpc custom text details state"
                                        active: DiscordRpcService.preset === "custom"
                                        onTriggered: DiscordRpcService.preset = "custom"
                                    }
                                }

                                // Smoothly animated Custom Flex inputs (zero dead snap)
                                Item {
                                    id: customFlexWrap
                                    Layout.fillWidth: true
                                    readonly property bool shown: DiscordRpcService.preset === "custom"
                                    Layout.preferredHeight: shown ? customFlexGroup.implicitHeight : 0
                                    opacity: shown ? 1.0 : 0.0
                                    clip: true
                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                    SettingGroup {
                                        id: customFlexGroup
                                        width: parent.width

                                        SettingRow {
                                            showDivider: false
                                            title: "Details (Line 1)"
                                            subtitle: "Primary activity line shown under app name"
                                            searchKeywords: "discord rpc custom details line 1"
                                            Rectangle {
                                                width: 240; height: 32; radius: 8; clip: true
                                                color: Theme.surfaceRaised
                                                border.width: 1
                                                border.color: customDetailsInput.activeFocus ? Theme.accent : Theme.borderSubtle
                                                Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                AnimatedTextInput {
                                                    id: customDetailsInput
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10; anchors.rightMargin: 10
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    textColor: Theme.text
                                                    font.family: Theme.fontSans; font.pixelSize: 12; clip: true
                                                    text: DiscordRpcService.customDetails
                                                    onTextEdited: DiscordRpcService.customDetails = text
                                                    Text {
                                                        anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                                        text: "Compiling kernel with -O3..."
                                                        color: Theme.textMuted; font: customDetailsInput.font
                                                        visible: customDetailsInput.text.length === 0; elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }

                                        SettingRow {
                                            title: "State (Line 2)"
                                            subtitle: "Secondary flex line shown below details"
                                            searchKeywords: "discord rpc custom state line 2"
                                            Rectangle {
                                                width: 240; height: 32; radius: 8; clip: true
                                                color: Theme.surfaceRaised
                                                border.width: 1
                                                border.color: customStateInput.activeFocus ? Theme.accent : Theme.borderSubtle
                                                Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                AnimatedTextInput {
                                                    id: customStateInput
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10; anchors.rightMargin: 10
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    textColor: Theme.text
                                                    font.family: Theme.fontSans; font.pixelSize: 12; clip: true
                                                    text: DiscordRpcService.customState
                                                    onTextEdited: DiscordRpcService.customState = text
                                                    Text {
                                                        anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                                        text: "I use Fedora btw..."
                                                        color: Theme.textMuted; font: customStateInput.font
                                                        visible: customStateInput.text.length === 0; elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }

                                        SettingRow {
                                            title: "Dynamic Flex Tokens"
                                            subtitle: "Click to insert live desktop values into your custom text"
                                            searchKeywords: "discord rpc custom token window uptime theme time"
                                            RowLayout {
                                                spacing: 6
                                                Repeater {
                                                    model: ["{window}", "{uptime}", "{theme}", "{time}"]
                                                    CtrlBtn {
                                                        required property string modelData
                                                        text: "+ " + modelData
                                                        onClicked: {
                                                            const tok = modelData;
                                                            if (customDetailsInput.activeFocus) {
                                                                const cur = DiscordRpcService.customDetails.trim();
                                                                DiscordRpcService.customDetails = cur !== "" ? (cur + " • " + tok) : tok;
                                                            } else {
                                                                const cur = DiscordRpcService.customState.trim();
                                                                DiscordRpcService.customState = cur !== "" ? (cur + " • " + tok) : tok;
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Core Presence Settings
                                SectionLabel { text: "Presence Behavior" }
                                SettingGroup {
                                    SettingRow {
                                        showDivider: false
                                        title: "Enable Discord RPC"
                                        subtitle: "Automatically detect Discord IPC and broadcast shell presence"
                                        searchKeywords: "discord rpc enable toggle broadcast"
                                        CtrlSwitch {
                                            checked: DiscordRpcService.enabled
                                            onToggled: (v) => DiscordRpcService.enabled = v
                                        }
                                    }
                                    SettingRow {
                                        title: "Show Active Theme Preset"
                                        subtitle: "Append current Paithosh theme (" + Theme.activePreset + ") to status line"
                                        searchKeywords: "discord rpc theme preset show"
                                        CtrlSwitch {
                                            checked: DiscordRpcService.showTheme
                                            onToggled: (v) => DiscordRpcService.showTheme = v
                                        }
                                    }
                                    SettingRow {
                                        title: "Show Session Elapsed Timer"
                                        subtitle: "Display live uptime counter on your Discord profile"
                                        searchKeywords: "discord rpc elapsed timer uptime"
                                        CtrlSwitch {
                                            checked: DiscordRpcService.showElapsed
                                            onToggled: (v) => DiscordRpcService.showElapsed = v
                                        }
                                    }
                                }

                                // Advanced tuning collapsed by default
                                AdvancedSection {
                                    expanded: false
                                    title: "Advanced RPC Settings"
                                    subtitle: "Rotation cadence & custom Discord Application ID"

                                    SettingRow {
                                        showDivider: false
                                        title: "Rotation Interval"
                                        subtitle: "How often preset lines cycle while connected"
                                        searchKeywords: "discord rpc interval rotation seconds"
                                        CtrlSlider {
                                            from: 15; to: 300; stepSize: 15
                                            unit: "s"
                                            value: DiscordRpcService.updateInterval
                                            onMoved: (v) => DiscordRpcService.updateInterval = Math.round(v)
                                        }
                                    }

                                    SettingRow {
                                        title: "Discord Application ID"
                                        subtitle: "Custom Developer Portal client ID (reconnects automatically)"
                                        searchKeywords: "discord rpc client id application developer"
                                        RowLayout {
                                            spacing: 8
                                            Rectangle {
                                                width: 190; height: 30; radius: 8; clip: true
                                                color: Theme.surfaceRaised
                                                border.width: 1
                                                border.color: clientIdInput.activeFocus ? Theme.accent : Theme.borderSubtle
                                                Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                AnimatedTextInput {
                                                    id: clientIdInput
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10; anchors.rightMargin: 10
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    textColor: Theme.text
                                                    font.family: Theme.fontMono; font.pixelSize: 11; clip: true
                                                    text: DiscordRpcService.clientId
                                                    onEditingFinished: DiscordRpcService.clientId = text.trim()
                                                    Text {
                                                        anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                                        text: DiscordRpcService.defaultClientId
                                                        color: Theme.textMuted; font: clientIdInput.font
                                                        visible: clientIdInput.text.length === 0; elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                            CtrlBtn {
                                                text: "Reset"
                                                onClicked: {
                                                    DiscordRpcService.resetClientId();
                                                    clientIdInput.text = DiscordRpcService.defaultClientId;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ==================== 10. PERSONALIZATION (MAINPAGE) ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "personalization"
                            active: Boolean(root.loadedPages["personalization"])
                            sourceComponent: ColumnLayout {
                            spacing: 14

                            // 1. Live Desktop Theme Preview (uses real Wallpaper, Theme tokens & Dynamic Island layout)
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: previewCardCol.implicitHeight + 24
                                radius: 14
                                color: Theme.cardBg
                                border.width: 1
                                border.color: Theme.borderSubtle

                                ColumnLayout {
                                    id: previewCardCol
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    RowLayout {
                                        Layout.fillWidth: true
                                        ColumnLayout {
                                            Layout.fillWidth: true; spacing: 2
                                            Text { text: "Desktop Preview"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold }
                                            Text {
                                                text: (Theme.wallpaperColorEnabled ? ("Wallpaper Match (" + (Theme.reduceMotion ? "Solid" : Theme.wallpaperColorMode) + ")") : Theme.activePreset) + " • Rounding " + (Theme.reduceMotion ? 10 : CompositorService.cornerRounding) + "px • Gaps " + CompositorService.gapsIn + "/" + CompositorService.gapsOut + "px • " + ((!Theme.reduceMotion && CompositorService.blurEnabled) ? ("Blur " + CompositorService.blurSize + "px") : "Blur Off")
                                                color: Theme.textSub
                                                font.family: Theme.fontSans
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        CtrlBtn { text: "Appearance"; ghost: true; onClicked: root.openPage("appearance") }
                                        CtrlBtn { text: "Layout"; ghost: true; onClicked: root.openPage("layout") }
                                    }

                                    // Real Desktop Canvas (Wallpaper + Dynamic Island + Tiled Windows using Theme tokens)
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 196
                                        radius: 10
                                        clip: true
                                        color: Theme.surfaceBg
                                        border.width: 1
                                        border.color: Theme.borderSubtle

                                        ThemeGradientFill {
                                            anchors.fill: parent
                                            cornerRadius: 10
                                            enabled: Theme.surfaceGradientEnabled
                                            color1: Theme.surfaceBg
                                            colorMid: Theme.surfaceBgMid
                                            color2: Theme.surfaceBg2
                                            angle: Theme.gradientAngle
                                        }

                                        // Real active wallpaper from bgLayer
                                        Image {
                                            anchors.fill: parent
                                            source: (typeof bgLayer !== "undefined" && bgLayer.wallpapers && bgLayer.wallpapers.length > 0)
                                                ? bgLayer.wallpapers[Math.max(0, Math.min(bgLayer.currentIndex, bgLayer.wallpapers.length - 1))]
                                                : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            smooth: true
                                            sourceSize.width: Theme.reduceMotion ? 360 : 960
                                            sourceSize.height: Theme.reduceMotion ? 202 : 540
                                            opacity: (!Theme.wallpapersDisabled && status === Image.Ready) ? 1.0 : 0.0
                                            visible: opacity > 0.002
                                            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                        }

                                        // Subtle vignette for contrast
                                        Rectangle {
                                            anchors.fill: parent
                                            color: Qt.rgba(0, 0, 0, 0.22)
                                            opacity: Theme.wallpapersDisabled ? 0.0 : 1.0
                                            visible: opacity > 0.002
                                            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                        }

                                        // Real Paithosh Dynamic Island (scaled 1:2 representation of DynamicIsland.qml)
                                        Rectangle {
                                            id: previewIsland
                                            readonly property bool isBottomPreview: (root.shellState ? root.shellState.barPosition : root.barPosition) === "bottom"
                                            readonly property real edgeMargin: root.topEdgeOffset ? 8 : 3
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            y: isBottomPreview ? (parent.height - height - edgeMargin) : edgeMargin
                                            width: Math.min(parent.width - 40, 260)
                                            height: 28
                                            radius: {
                                                const r = root.islandCornerRadius.indexOf("12") !== -1 ? 12 : (root.islandCornerRadius.indexOf("18") !== -1 ? 18 : 26);
                                                return Math.round(r * 0.54);
                                            }
                                            color: Theme.pillBg
                                            border.width: 1
                                            border.color: Theme.borderSubtle
                                            clip: true
                                            Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                            ThemeGradientFill {
                                                anchors.fill: parent
                                                anchors.margins: 1
                                                enabled: Theme.shellGradientEnabled
                                                color1: Theme.pillBg
                                                colorMid: Theme.pillBgMid
                                                color2: Theme.pillBg2
                                                cornerRadius: Math.max(0, previewIsland.radius - 1)
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 12; anchors.rightMargin: 12
                                                spacing: 8
                                                Text {
                                                    text: WeatherService.tempText
                                                    color: Theme.text
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 11
                                                    font.weight: Font.Bold
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    horizontalAlignment: Text.AlignHCenter
                                                    text: "Paithosh Shell"
                                                    color: Theme.textSub
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 10
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: Qt.formatTime(new Date(), "hh:mm")
                                                    color: Theme.text
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 11
                                                    font.weight: Font.Medium
                                                }
                                            }
                                        }

                                        // Simulated Tiled Windows using real Theme & CompositorService values
                                        RowLayout {
                                            readonly property real baseGap: Math.max(4, Math.min(18, CompositorService.gapsOut * 0.8))
                                            readonly property real islandClearance: previewIsland.edgeMargin + previewIsland.height + Math.max(6, Math.min(14, CompositorService.gapsIn + 4))
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.leftMargin: baseGap
                                            anchors.rightMargin: baseGap
                                            anchors.topMargin: previewIsland.isBottomPreview ? baseGap : islandClearance
                                            anchors.bottomMargin: previewIsland.isBottomPreview ? islandClearance : baseGap
                                            spacing: Math.max(3, Math.min(14, CompositorService.gapsIn * 0.8))
                                            Behavior on anchors.topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                            Behavior on anchors.bottomMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                            // Focused Window (Active Border Highlight)
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                Layout.preferredWidth: CompositorService.layoutName === "master" ? 1.45 : 1.2
                                                radius: Math.max(0, Math.min(18, CompositorService.cornerRounding * 0.65))
                                                clip: true
                                                color: Qt.rgba(Theme.surfaceBg.r, Theme.surfaceBg.g, Theme.surfaceBg.b, CompositorService.blurEnabled ? 0.80 : 0.97)
                                                border.width: Math.max(0, Math.min(4, CompositorService.borderSize))
                                                border.color: root.activeBorderHighlight ? Theme.accent : Theme.borderSubtle
                                                Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                ThemeGradientFill {
                                                    anchors.fill: parent
                                                    anchors.margins: parent.border.width
                                                    enabled: Theme.surfaceGradientEnabled
                                                    color1: Qt.rgba(Theme.surfaceBg.r, Theme.surfaceBg.g, Theme.surfaceBg.b, CompositorService.blurEnabled ? 0.80 : 0.97)
                                                    colorMid: Qt.rgba(Theme.surfaceBgMid.r, Theme.surfaceBgMid.g, Theme.surfaceBgMid.b, CompositorService.blurEnabled ? 0.80 : 0.97)
                                                    color2: Qt.rgba(Theme.surfaceBg2.r, Theme.surfaceBg2.g, Theme.surfaceBg2.b, CompositorService.blurEnabled ? 0.80 : 0.97)
                                                    cornerRadius: Math.max(0, parent.radius - parent.border.width)
                                                }

                                                ColumnLayout {
                                                    anchors.fill: parent; anchors.margins: 10; spacing: 6
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        Text { text: "Settings • Personalization"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 10; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                                                        Rectangle {
                                                            width: 6; height: 6; radius: 3; clip: true; color: Theme.accent
                                                            ThemeGradientFill { anchors.fill: parent; enabled: Theme.accentGradientEnabled; color1: Theme.accent; colorMid: Theme.accentMid; color2: Theme.accent2; cornerRadius: 3 }
                                                        }
                                                    }
                                                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 6; radius: 3; color: Theme.cardHover }
                                                    Rectangle { width: 96; height: 6; radius: 3; color: Theme.cardBg }
                                                    Item { Layout.fillHeight: true }
                                                    Text { text: CompositorService.layoutName + " • border " + CompositorService.borderSize + "px"; color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 9 }
                                                }
                                            }

                                            // Secondary Stack (Inactive Opacity)
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                Layout.preferredWidth: 0.8
                                                spacing: Math.max(3, Math.min(14, CompositorService.gapsIn * 0.8))

                                                Rectangle {
                                                    Layout.fillWidth: true; Layout.fillHeight: true
                                                    radius: Math.max(0, Math.min(18, CompositorService.cornerRounding * 0.65))
                                                    color: Qt.rgba(Theme.surfaceRaised.r, Theme.surfaceRaised.g, Theme.surfaceRaised.b, (CompositorService.blurEnabled ? 0.74 : 0.95) * CompositorService.inactiveOpacity)
                                                    border.width: 1; border.color: Theme.borderSubtle
                                                    Text { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 8; text: "Terminal"; color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 9 }
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true; Layout.fillHeight: true
                                                    radius: Math.max(0, Math.min(18, CompositorService.cornerRounding * 0.65))
                                                    color: Qt.rgba(Theme.surfaceRaised.r, Theme.surfaceRaised.g, Theme.surfaceRaised.b, (CompositorService.blurEnabled ? 0.74 : 0.95) * CompositorService.inactiveOpacity)
                                                    border.width: 1; border.color: Theme.borderSubtle
                                                    Text { anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 8; text: "Audio • " + AudioService.volumePct + "%"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 9 }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 2. Theme Presets (Pre-configured + Adaptive Wallpaper + Local .paish + Share Code)
                            SectionLabel { text: "Theme presets" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 2; columnSpacing: 10; rowSpacing: 10
                                enabled: !Theme.wallpaperColorEnabled
                                opacity: Theme.wallpaperColorEnabled ? 0.45 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                Repeater {
                                    model: Theme.presetCatalog
                                    delegate: PresetCard {
                                        required property var modelData
                                        title: modelData.name
                                        subtitle: modelData.subtitle
                                        active: root.isPresetActive(modelData.name)
                                        onTriggered: root.selectThemePreset(modelData.name)
                                    }
                                }
                            }

                            WallpaperColorCard {}

                            WallpaperLockBanner {
                                message: "Theme presets are disabled while \"Adjust colors based on what you see\" is active so Paithosh can match colors directly to your wallpaper. Your manual preset and custom palette remain preserved."
                            }

                            SectionLabel { text: "Quick Share Code (Personalization + Advanced)" }
                            SettingGroup {
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: shareCodeCol.implicitHeight + 24
                                    ColumnLayout {
                                        id: shareCodeCol
                                        anchors.fill: parent; anchors.margins: 12; spacing: 8
                                        property bool copiedFeedback: false

                                        Timer {
                                            id: copyFeedbackTimer
                                            interval: 1600
                                            repeat: false
                                            onTriggered: shareCodeCol.copiedFeedback = false
                                        }

                                        Component.onCompleted: {
                                            if (root.shellState) root.shellState.refreshShareCode();
                                        }

                                        Connections {
                                            target: root.shellState
                                            function onShareCodeCopied(code) {
                                                root.themeExportOk = true;
                                                root.themeExportStatus = "Copied share code (" + code.length + " chars)";
                                                shareCodeCol.copiedFeedback = true;
                                                copyFeedbackTimer.restart();
                                            }
                                            function onThemeCodeImported(ok, message) {
                                                root.themeExportOk = ok;
                                                root.themeExportStatus = message;
                                                if (ok) root.themeImportInput = "";
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 2
                                                Text { text: "Export current settings as compact code"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                                                Text {
                                                    text: (root.shellState && root.shellState.currentShareCode !== "") ? root.shellState.currentShareCode : "paish:..."
                                                    color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 10
                                                    elide: Text.ElideMiddle; Layout.fillWidth: true
                                                }
                                            }
                                            CtrlBtn {
                                                text: shareCodeCol.copiedFeedback ? "Copied" : "Copy Code"
                                                onClicked: {
                                                    if (root.shellState) root.shellState.copyShareCode();
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true; height: 1; color: Theme.borderSubtle
                                        }

                                        Text { text: "Paste share code (paish:...) to apply"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11 }
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Rectangle {
                                                Layout.fillWidth: true; height: 34; radius: 6
                                                color: Qt.rgba(1, 1, 1, 0.06); border.color: Qt.rgba(1, 1, 1, 0.14); border.width: 1
                                                AnimatedTextInput {
                                                    anchors.fill: parent; anchors.margins: 8
                                                    textColor: Theme.text; font.family: Theme.fontMono; font.pixelSize: 11
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    clip: true
                                                    text: root.themeImportInput
                                                    onTextChanged: root.themeImportInput = text
                                                    Keys.onEscapePressed: (event) => {
                                                        focus = false;
                                                        event.accepted = true;
                                                    }
                                                    onAccepted: {
                                                        if (root.shellState) root.shellState.importThemeCode(root.themeImportInput);
                                                    }
                                                    Text {
                                                        anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                                        text: "paish:..."
                                                        color: Theme.textMuted; font: parent.font
                                                        visible: parent.text === ""
                                                    }
                                                }
                                            }
                                            CtrlBtn {
                                                text: "Apply Code"
                                                onClicked: {
                                                    if (root.shellState) root.shellState.importThemeCode(root.themeImportInput);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            AdvancedSection {
                                expanded: true
                                title: ".paish Profile Files (Local Presets)"
                                subtitle: "Save or load plain-text profiles at ~/.config/paithosh/<profile>.paish"
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: paishCol.implicitHeight + 24
                                    ColumnLayout {
                                        id: paishCol
                                        anchors.fill: parent; anchors.margins: 12; spacing: 8
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Rectangle {
                                                Layout.fillWidth: true; Layout.preferredWidth: 0; Layout.minimumWidth: 0; height: 32; radius: 6
                                                color: Qt.rgba(1, 1, 1, 0.06); border.color: Qt.rgba(1, 1, 1, 0.14); border.width: 1
                                                AnimatedTextInput {
                                                    anchors.fill: parent; anchors.margins: 8
                                                    textColor: Theme.text; font.family: Theme.fontMono; font.pixelSize: 12
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    clip: true
                                                    text: root.profileNameInput
                                                    onTextChanged: root.profileNameInput = text
                                                    Keys.onEscapePressed: (event) => {
                                                        focus = false;
                                                        event.accepted = true;
                                                    }
                                                    Text {
                                                        anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                                        text: "Profile name (e.g. default)"
                                                        color: Theme.textMuted; font: parent.font
                                                        visible: parent.text === ""
                                                    }
                                                }
                                            }
                                            CtrlBtn {
                                                text: "Save .paish"
                                                onClicked: {
                                                    if (root.shellState) root.shellState.saveProfile(root.profileNameInput);
                                                }
                                            }
                                            CtrlBtn {
                                                text: "Load .paish"
                                                ghost: true
                                                onClicked: {
                                                    if (root.shellState) root.shellState.loadProfile(root.profileNameInput, false);
                                                }
                                            }
                                        }

                                        Flow {
                                            Layout.fillWidth: true; spacing: 6
                                            visible: root.shellState && root.shellState.availableProfiles && root.shellState.availableProfiles.length > 0
                                            Repeater {
                                                model: root.shellState ? root.shellState.availableProfiles : []
                                                delegate: CtrlBtn {
                                                    required property string modelData
                                                    text: modelData + ".paish"
                                                    ghost: !root.shellState || root.shellState.activeProfile !== modelData
                                                    onClicked: {
                                                        root.profileNameInput = modelData;
                                                        if (root.shellState) root.shellState.loadProfile(modelData, false);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Text {
                                visible: root.themeExportStatus !== ""
                                Layout.fillWidth: true; Layout.preferredWidth: 0
                                wrapMode: Text.WrapAnywhere
                                text: root.themeExportStatus
                                color: root.themeExportOk ? Theme.ok : Theme.dangerText
                                font.family: Theme.fontSans
                                font.pixelSize: 11
                            }

                            // 3. Quick Standard Settings
                            SectionLabel { text: "Quick standard settings" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconName: "palette"; title: "Window Blur (Kawase)"; subtitle: "Frosted translucency behind panels"
                                    CtrlSwitch { checked: CompositorService.blurEnabled; onToggled: (v) => { CompositorService.setBlurConfig(v, CompositorService.blurSize, CompositorService.blurPasses, CompositorService.blurVibrancy); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "palette"; title: "Hyprland Animations"; subtitle: "Smooth spring window transitions"
                                    CtrlSwitch { checked: CompositorService.animationsEnabled; onToggled: (v) => { CompositorService.setAnimationsEnabled(v); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "maximize"; title: "Dynamic Island Auto-Hide"; subtitle: "Hide status bar when fullscreen or overlapped"
                                    CtrlSwitch {
                                        checked: root.shellState ? (root.shellState.autoHideOnOverlap || root.shellState.hideBarFullscreen) : root.hideBarFullscreen
                                        onToggled: (v) => {
                                            root.hideBarFullscreen = v;
                                            root.islandAutoHide = v;
                                            if (root.shellState) {
                                                root.shellState.hideBarFullscreen = v;
                                                root.shellState.autoHideOnOverlap = v;
                                            }
                                            root.markAppearanceChanged();
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "square-rounded"; title: "Active Border Highlight"; subtitle: "Crisp outline on focused window"
                                    CtrlSwitch {
                                        checked: root.shellState ? root.shellState.activeBorderHighlight : root.activeBorderHighlight
                                        onToggled: (v) => {
                                            root.activeBorderHighlight = v;
                                            if (root.shellState) root.shellState.activeBorderHighlight = v;
                                            root.markAppearanceChanged();
                                        }
                                    }
                                }
                            }

                            // 4. Customize by Area
                            SectionLabel { text: "Customize by area" }
                            HubCard { iconName: "palette"; title: "Appearance"; subtitle: "Themes, colors, wallpaper, decoration & blur"; pillText: (Theme.wallpaperColorEnabled ? ("Wallpaper (" + (Theme.reduceMotion ? "Solid" : Theme.wallpaperColorMode) + ")") : Theme.activePreset) + " • " + ((!Theme.reduceMotion && CompositorService.blurEnabled) ? "Blur" : "No Blur"); onTriggered: root.openPage("appearance") }
                            HubCard { iconName: "keyboard"; title: "Binding"; subtitle: "Shortcuts, apps, capture & Island IPC"; pillText: KeybindService.totalComboCount + " binds"; onTriggered: root.openPage("keybind") }
                            HubCard { iconName: "layout"; title: "Layout"; subtitle: "Tiling, gaps, borders & Dynamic Island"; pillText: CompositorService.layoutName + " • " + CompositorService.gapsIn + "/" + CompositorService.gapsOut + "px"; onTriggered: root.openPage("layout") }
                            HubCard {
                                iconName: "lock"
                                title: "Lock Screen"
                                subtitle: "Ambient effects, sound presets, notifications & alerts"
                                pillText: {
                                    const eff = LockService.effectPreset === "snow" ? "Snow" : (LockService.effectPreset === "rain" ? "Rain" : (LockService.effectPreset === "wind" ? "Wind" : "Clean"));
                                    const snd = LockService.silentMode ? "Muted" : (LockService.ambientSound === "wind" ? "Wind" : (LockService.ambientSound === "rain" ? "Rain" : (LockService.ambientSound === "snow" ? "Winter" : "Silent")));
                                    return eff + " • " + snd;
                                }
                                onTriggered: root.openPage("lockscreen")
                            }
                        }
                        }

                        // ==================== 11. APPEARANCE ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "appearance"
                            active: Boolean(root.loadedPages["appearance"])
                            sourceComponent: ColumnLayout {
                            spacing: 12

                            WallpaperColorCard {}

                            WallpaperLockBanner {
                                message: "Manual color, surface, gradient, and studio controls below are disabled while \"Adjust colors based on what you see\" is enabled — Paithosh is automatically matching interface colors to your active wallpaper. Turn it off above to resume manual tuning (your previous setup is preserved)."
                            }

                            SectionLabel { text: "Surface & Gradients" }
                            SettingGroup {
                                enabled: !Theme.wallpaperColorEnabled
                                opacity: Theme.wallpaperColorEnabled ? 0.45 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                SettingRow {
                                    showDivider: false; iconName: "contrast"; title: "Global Surface Theme"; subtitle: "Contrast & backdrop style synced across apps"
                                    searchKeywords: "surface theme oled mica adaptive contrast"
                                    CtrlSelect {
                                        options: ["OLED Pure", "Mica Dark", "Adaptive"]
                                        currentText: Theme.surfaceTheme
                                        onSelected: (v) => {
                                            root.globalSurfaceTheme = v;
                                            if (root.shellState) root.shellState.applyGlobalSurfaceTheme(v);
                                            else Theme.applySurfaceTheme(v);
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "layers"; title: "Shell Gradient"
                                    subtitle: Theme.reduceMotion ? "Disabled by Reduce motion~" : "Directional gradient on Island, Popover, Menu & Sidebars"
                                    searchKeywords: "shell gradient pillbg island popover sidebar"
                                    enabled: !Theme.reduceMotion
                                    opacity: Theme.reduceMotion ? 0.45 : 1.0
                                    CtrlSwitch {
                                        checked: !Theme.reduceMotion && (Theme.wallpaperColorEnabled ? Theme.manualShellGradientEnabled : Theme.shellGradientEnabled)
                                        enabled: !Theme.reduceMotion
                                        onToggled: (v) => {
                                            if (root.shellState) root.shellState.setThemeGradients(v, Theme.manualSurfaceGradientEnabled, Theme.manualAccentMode === "Gradient");
                                            else Theme.setGradientFlags(v, Theme.manualSurfaceGradientEnabled, Theme.manualAccentMode === "Gradient");
                                            root.loadStudioSlot(root.colorStudioSlot);
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "layers"; title: "Surface Gradient"
                                    subtitle: Theme.reduceMotion ? "Disabled by Reduce motion~" : "Directional gradient on Workspace canvas, Detached windows & Modals"
                                    searchKeywords: "surface gradient background workspace modal"
                                    enabled: !Theme.reduceMotion
                                    opacity: Theme.reduceMotion ? 0.45 : 1.0
                                    CtrlSwitch {
                                        checked: !Theme.reduceMotion && (Theme.wallpaperColorEnabled ? Theme.manualSurfaceGradientEnabled : Theme.surfaceGradientEnabled)
                                        enabled: !Theme.reduceMotion
                                        onToggled: (v) => {
                                            if (root.shellState) root.shellState.setThemeGradients(Theme.manualShellGradientEnabled, v, Theme.manualAccentMode === "Gradient");
                                            else Theme.setGradientFlags(Theme.manualShellGradientEnabled, v, Theme.manualAccentMode === "Gradient");
                                            root.loadStudioSlot(root.colorStudioSlot);
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "sparkles"; title: "Accent Gradient"
                                    subtitle: Theme.reduceMotion ? "Disabled by Reduce motion~" : "Directional gradient on active buttons, switches, sliders & Hyprland border"
                                    searchKeywords: "accent gradient border active control"
                                    enabled: !Theme.reduceMotion
                                    opacity: Theme.reduceMotion ? 0.45 : 1.0
                                    CtrlSwitch {
                                        checked: !Theme.reduceMotion && (Theme.wallpaperColorEnabled ? (Theme.manualAccentMode === "Gradient") : Theme.accentGradientEnabled)
                                        enabled: !Theme.reduceMotion
                                        onToggled: (v) => {
                                            if (root.shellState) root.shellState.setThemeGradients(Theme.manualShellGradientEnabled, Theme.manualSurfaceGradientEnabled, v);
                                            else Theme.setGradientFlags(Theme.manualShellGradientEnabled, Theme.manualSurfaceGradientEnabled, v);
                                            root.loadStudioSlot(root.colorStudioSlot);
                                        }
                                    }
                                }
                                Item {
                                    readonly property bool anyGrad: !Theme.reduceMotion && (Theme.wallpaperColorEnabled
                                        ? (Theme.manualShellGradientEnabled || Theme.manualSurfaceGradientEnabled || Theme.manualAccentMode === "Gradient")
                                        : (Theme.shellGradientEnabled || Theme.surfaceGradientEnabled || Theme.accentGradientEnabled))
                                    Layout.fillWidth: true
                                    implicitHeight: anyGrad ? angleRow.implicitHeight : 0
                                    clip: true
                                    visible: implicitHeight > 0.5
                                    opacity: anyGrad ? 1.0 : 0.0
                                    Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    SettingRow {
                                        id: angleRow
                                        width: parent.width
                                        iconName: "sliders"; title: "Gradient Angle"; subtitle: "Shared light direction across shell, workspace & borders"
                                        searchKeywords: "gradient angle degree direction"
                                        CtrlSlider {
                                            from: 0; to: 360; unit: "°"
                                            value: Theme.wallpaperColorEnabled ? Theme.manualGradientAngle : Theme.gradientAngle
                                            onMoved: (v) => {
                                                root.gradientAngle = v;
                                                if (root.shellState) root.shellState.setThemeGradientAngle(v);
                                                else Theme.setGradientAngle(v);
                                            }
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "palette"; title: "Theme Palette"; subtitle: "Click any swatch to customize in Studio"
                                    searchKeywords: "palette colors shell surface accent raised text border hex"
                                    RowLayout {
                                        spacing: 6
                                        Repeater {
                                            model: [
                                                { slot: "pillBg", label: "Shell" },
                                                { slot: "surfaceBg", label: "Surface" },
                                                { slot: "accent", label: "Accent" },
                                                { slot: "surfaceRaised", label: "Raised" },
                                                { slot: "text", label: "Text" },
                                                { slot: "borderColor", label: "Border" }
                                            ]
                                            delegate: Rectangle {
                                                id: quickSwatch
                                                required property var modelData
                                                readonly property bool isTarget: !Theme.wallpaperColorEnabled && root.studioExpanded && root.colorStudioSlot === modelData.slot
                                                width: 24; height: 24; radius: 7; clip: true
                                                color: Theme.getSlotHex(modelData.slot)
                                                border.width: isTarget ? 2 : 1
                                                border.color: isTarget
                                                    ? Theme.accent
                                                    : ((!Theme.wallpaperColorEnabled && swHover.containsMouse) ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) : Theme.borderSubtle)
                                                scale: (!Theme.wallpaperColorEnabled && swHover.pressed) ? 0.92 : ((!Theme.wallpaperColorEnabled && swHover.containsMouse) ? 1.06 : 1.0)
                                                Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                                MouseArea {
                                                    id: swHover
                                                    anchors.fill: parent
                                                    enabled: !Theme.wallpaperColorEnabled
                                                    hoverEnabled: !Theme.wallpaperColorEnabled
                                                    cursorShape: !Theme.wallpaperColorEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: {
                                                        root.loadStudioSlot(quickSwatch.modelData.slot);
                                                        root.studioExpanded = true;
                                                    }
                                                }
                                            }
                                        }
                                        CtrlBtn {
                                            text: "Reset"
                                            ghost: true
                                            enabled: !Theme.wallpaperColorEnabled
                                            onClicked: root.selectThemePreset(Theme.activePreset)
                                        }
                                    }
                                }
                            }

                            AdvancedSection {
                                id: themeStudioAdv
                                title: "Theme Color & Gradient Studio"
                                subtitle: "Shell, Surface, Accent, Raised, Text, Border & Gradient Stops"
                                enabled: !Theme.wallpaperColorEnabled
                                opacity: Theme.wallpaperColorEnabled ? 0.45 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                onExpandedChanged: {
                                    if (root.studioExpanded !== expanded) root.studioExpanded = expanded;
                                }
                                Connections {
                                    target: root
                                    function onStudioExpandedChanged() {
                                        if (themeStudioAdv.expanded !== root.studioExpanded) {
                                            themeStudioAdv.expanded = root.studioExpanded;
                                        }
                                    }
                                }
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: hsvStudioCol.implicitHeight + 24
                                    ColumnLayout {
                                        id: hsvStudioCol
                                        readonly property var curGroup: root.studioGroupForSlot(root.colorStudioSlot)
                                        readonly property bool hasStop2: curGroup.slot2 !== ""
                                        readonly property bool isStop2: hasStop2 && root.colorStudioSlot === curGroup.slot2
                                        anchors.fill: parent; anchors.margins: 12; spacing: 10

                                        // 1. Multi-option Layer Selector + Base/End Gradient Stop Segmented Switcher
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            CtrlSelect {
                                                id: studioLayerSelect
                                                implicitWidth: 168
                                                options: [
                                                    "Shell Chrome",
                                                    "Surface Canvas",
                                                    "Accent & Focus",
                                                    "Raised Chrome",
                                                    "Primary Text",
                                                    "Border Tint"
                                                ]
                                                currentText: hsvStudioCol.curGroup.label
                                                onSelected: (label) => {
                                                    for (let i = 0; i < root.studioGroups.length; ++i) {
                                                        if (root.studioGroups[i].label === label) {
                                                            root.loadStudioSlot(root.studioGroups[i].slot1);
                                                            return;
                                                        }
                                                    }
                                                }
                                            }

                                            // Segmented Stop Selector (Base vs Gradient End) for Shell / Surface / Accent
                                            Rectangle {
                                                id: stopSegmentTrack
                                                Layout.preferredWidth: hsvStudioCol.hasStop2 ? 156 : 0
                                                height: 30
                                                radius: 9
                                                clip: true
                                                visible: Layout.preferredWidth > 1
                                                opacity: hsvStudioCol.hasStop2 ? 1.0 : 0.0
                                                color: Theme.pillBg
                                                border.width: 1
                                                border.color: Theme.borderSubtle
                                                Behavior on Layout.preferredWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                                Rectangle {
                                                    id: stopThumb
                                                    y: 2
                                                    x: hsvStudioCol.isStop2 ? (stopSegmentTrack.width / 2) : 2
                                                    width: Math.max(0, stopSegmentTrack.width / 2 - 2)
                                                    height: stopSegmentTrack.height - 4
                                                    radius: 7
                                                    color: Theme.surfaceRaised
                                                    border.width: 1
                                                    border.color: Theme.borderSubtle
                                                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                                }

                                                Row {
                                                    anchors.fill: parent
                                                    Item {
                                                        width: stopSegmentTrack.width / 2
                                                        height: stopSegmentTrack.height
                                                        scale: stop1Mouse.pressed ? 0.94 : 1.0
                                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                                        RowLayout {
                                                            anchors.centerIn: parent; spacing: 5
                                                            Rectangle {
                                                                width: 9; height: 9; radius: 4.5
                                                                color: Theme.getSlotHex(hsvStudioCol.curGroup.slot1)
                                                                border.width: 1; border.color: Theme.borderSubtle
                                                            }
                                                            Text {
                                                                text: "Base"
                                                                color: !hsvStudioCol.isStop2 ? Theme.text : Theme.textSub
                                                                font.family: Theme.fontSans; font.pixelSize: 11
                                                                font.weight: !hsvStudioCol.isStop2 ? Font.DemiBold : Font.Medium
                                                            }
                                                        }
                                                        MouseArea {
                                                            id: stop1Mouse
                                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                            onClicked: root.loadStudioSlot(hsvStudioCol.curGroup.slot1)
                                                        }
                                                    }
                                                    Item {
                                                        width: stopSegmentTrack.width / 2
                                                        height: stopSegmentTrack.height
                                                        scale: stop2Mouse.pressed ? 0.94 : 1.0
                                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                                        RowLayout {
                                                            anchors.centerIn: parent; spacing: 5
                                                            Rectangle {
                                                                width: 9; height: 9; radius: 4.5
                                                                color: hsvStudioCol.hasStop2 ? Theme.getSlotHex(hsvStudioCol.curGroup.slot2) : "transparent"
                                                                border.width: 1; border.color: Theme.borderSubtle
                                                            }
                                                            Text {
                                                                text: "End"
                                                                color: hsvStudioCol.isStop2 ? Theme.text : Theme.textSub
                                                                font.family: Theme.fontSans; font.pixelSize: 11
                                                                font.weight: hsvStudioCol.isStop2 ? Font.DemiBold : Font.Medium
                                                            }
                                                        }
                                                        MouseArea {
                                                            id: stop2Mouse
                                                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                            onClicked: if (hsvStudioCol.hasStop2) root.loadStudioSlot(hsvStudioCol.curGroup.slot2)
                                                        }
                                                    }
                                                }
                                            }

                                            Item { Layout.fillWidth: true }

                                            CtrlBtn {
                                                text: "Auto"
                                                ghost: true
                                                enabled: root.isSlotCustomized(root.colorStudioSlot)
                                                onClicked: {
                                                    if (root.shellState) root.shellState.clearThemeColorOverride(root.colorStudioSlot);
                                                    else Theme.clearPaletteOverride(root.colorStudioSlot);
                                                    root.loadStudioSlot(root.colorStudioSlot);
                                                }
                                            }
                                            CtrlBtn {
                                                text: "Reset"
                                                ghost: true
                                                onClicked: root.selectThemePreset(Theme.activePreset)
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: hsvStudioCol.curGroup.desc + (hsvStudioCol.isStop2 ? " • Gradient End Stop" : (hsvStudioCol.hasStop2 ? " • Base Stop" : ""))
                                            color: Theme.textSub
                                            font.family: Theme.fontSans
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }

                                        // 2. HSV Canvas + Hue Slider + Hex Input + Quick Swatches + Gradient Pair Strip
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 14
                                            Rectangle {
                                                id: svBox
                                                Layout.preferredWidth: 152
                                                Layout.preferredHeight: 152
                                                Layout.alignment: Qt.AlignTop
                                                radius: 10; clip: true
                                                color: Qt.hsva(root.studioHue, 1.0, 1.0, 1.0)
                                                border.width: 1; border.color: Theme.borderSubtle
                                                Rectangle {
                                                    anchors.fill: parent; radius: 10
                                                    gradient: Gradient {
                                                        orientation: Gradient.Horizontal
                                                        GradientStop { position: 0.0; color: "#ffffff" }
                                                        GradientStop { position: 1.0; color: "transparent" }
                                                    }
                                                }
                                                Rectangle {
                                                    anchors.fill: parent; radius: 10
                                                    gradient: Gradient {
                                                        orientation: Gradient.Vertical
                                                        GradientStop { position: 0.0; color: "transparent" }
                                                        GradientStop { position: 1.0; color: "#000000" }
                                                    }
                                                }
                                                Rectangle {
                                                    width: 12; height: 12; radius: 6
                                                    x: Math.max(0, Math.min(svBox.width - width, root.studioSat * (svBox.width - width)))
                                                    y: Math.max(0, Math.min(svBox.height - height, (1.0 - root.studioVal) * (svBox.height - height)))
                                                    color: "transparent"
                                                    border.width: 2; border.color: "#ffffff"
                                                    scale: svMouse.pressed ? 1.22 : 1.0
                                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                                    Rectangle {
                                                        anchors.fill: parent; anchors.margins: 2; radius: 4
                                                        color: "transparent"
                                                        border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.55)
                                                    }
                                                }
                                                MouseArea {
                                                    id: svMouse
                                                    anchors.fill: parent
                                                    preventStealing: true
                                                    cursorShape: Qt.CrossCursor
                                                    onPressed: (m) => { root.applyStudioHsv(root.studioHue, m.x / width, 1.0 - m.y / height); }
                                                    onPositionChanged: (m) => { if (pressed) root.applyStudioHsv(root.studioHue, m.x / width, 1.0 - m.y / height); }
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 8
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text { text: "Hue"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; Layout.fillWidth: true }
                                                    Text {
                                                        text: Math.round(root.studioHue * 360) + "°"
                                                        color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10
                                                    }
                                                }
                                                HueSlider {
                                                    Layout.fillWidth: true
                                                    value: root.studioHue
                                                    onMoved: root.applyStudioHsv(value, root.studioSat, root.studioVal)
                                                }

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Text { text: "Hex Code"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11; Layout.fillWidth: true }
                                                    Text {
                                                        text: "S " + Math.round(root.studioSat * 100) + "% • V " + Math.round(root.studioVal * 100) + "%"
                                                        color: Theme.textMuted; font.family: Theme.fontMono; font.pixelSize: 10
                                                    }
                                                }
                                                RowLayout {
                                                    Layout.fillWidth: true; spacing: 8
                                                    Rectangle {
                                                        id: studioHexBox
                                                        Layout.fillWidth: true; Layout.minimumWidth: 0; height: 32; radius: 8; clip: true
                                                        color: Theme.pillBg
                                                        border.width: 1
                                                        border.color: root.studioHexError !== "" ? Theme.danger : (studioHexField.activeFocus ? Theme.accent : Theme.borderSubtle)
                                                        Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                                        transform: Translate { id: hexShakeTrans; x: 0 }
                                                        SequentialAnimation {
                                                            id: hexShake
                                                            NumberAnimation { target: hexShakeTrans; property: "x"; to: -8; duration: 45 }
                                                            NumberAnimation { target: hexShakeTrans; property: "x"; to: 8; duration: 45 }
                                                            NumberAnimation { target: hexShakeTrans; property: "x"; to: -6; duration: 45 }
                                                            NumberAnimation { target: hexShakeTrans; property: "x"; to: 0; duration: 45 }
                                                        }

                                                        RowLayout {
                                                            anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 8
                                                            Rectangle {
                                                                width: 16; height: 16; radius: 5
                                                                color: Theme.getSlotHex(root.colorStudioSlot)
                                                                border.width: 1; border.color: Theme.borderSubtle
                                                            }
                                                            AnimatedTextInput {
                                                                id: studioHexField
                                                                Layout.fillWidth: true; Layout.minimumWidth: 0
                                                                verticalAlignment: TextInput.AlignVCenter
                                                                textColor: Theme.text
                                                                font.family: Theme.fontMono; font.pixelSize: 12
                                                                maximumLength: 7; clip: true
                                                                Component.onCompleted: text = root.studioHexInput
                                                                Connections {
                                                                    target: root
                                                                    function onStudioHexInputChanged() {
                                                                        if (studioHexField.text !== root.studioHexInput) {
                                                                            studioHexField.text = root.studioHexInput;
                                                                        }
                                                                    }
                                                                }
                                                                onTextChanged: {
                                                                    if (root.studioHexError !== "") root.studioHexError = "";
                                                                    root.studioHexInput = text;
                                                                }
                                                                Keys.onEscapePressed: (event) => {
                                                                    focus = false;
                                                                    root.forceActiveFocus();
                                                                    event.accepted = true;
                                                                }
                                                                onAccepted: root.applyStudioHex(text, hexShake)
                                                                Text {
                                                                    anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                                                    text: "#rrggbb"
                                                                    color: Theme.textMuted; font: parent.font
                                                                    visible: parent.text === ""
                                                                }
                                                            }
                                                        }
                                                    }
                                                    CtrlBtn {
                                                        text: "Apply"
                                                        onClicked: root.applyStudioHex(studioHexField.text, hexShake)
                                                    }
                                                }
                                                Text {
                                                    visible: root.studioHexError !== ""
                                                    Layout.fillWidth: true; Layout.minimumWidth: 0
                                                    text: root.studioHexError
                                                    color: Theme.dangerText
                                                    font.family: Theme.fontSans; font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }

                                                // Curated Quick Swatches (context-aware: dark surfaces vs bright accents)
                                                RowLayout {
                                                    Layout.fillWidth: true; spacing: 6
                                                    Text {
                                                        text: "Swatches"
                                                        color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    Repeater {
                                                        model: (hsvStudioCol.curGroup.id === "shell" || hsvStudioCol.curGroup.id === "surface" || hsvStudioCol.curGroup.id === "raised")
                                                            ? ["#000000", "#0b0b0c", "#141416", "#1a1f29", "#1e1e2e", "#0d1216", "#182436", "#232136"]
                                                            : ["#ffffff", "#eceff4", "#88c0d0", "#a8c7fa", "#cba6f7", "#80cbc4", "#f5c2e7", "#f9e2af"]
                                                        delegate: Rectangle {
                                                            id: pickSwatch
                                                            required property string modelData
                                                            readonly property bool matched: Theme.getSlotHex(root.colorStudioSlot) === modelData
                                                            width: 20; height: 20; radius: 6; clip: true
                                                            color: modelData
                                                            border.width: matched ? 2 : 1
                                                            border.color: matched
                                                                ? Theme.accent
                                                                : (psMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) : Theme.borderSubtle)
                                                            scale: psMouse.pressed ? 0.88 : (psMouse.containsMouse ? 1.08 : 1.0)
                                                            Behavior on border.color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                                            MouseArea {
                                                                id: psMouse
                                                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                                onClicked: root.applyStudioHex(pickSwatch.modelData, null)
                                                            }
                                                        }
                                                    }
                                                }

                                                // Live Gradient Pair Strip (only for gradient-capable layers)
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: hsvStudioCol.hasStop2 ? 24 : 0
                                                    radius: 7; clip: true
                                                    visible: Layout.preferredHeight > 1
                                                    opacity: hsvStudioCol.hasStop2 ? 1.0 : 0.0
                                                    color: Theme.getSlotHex(hsvStudioCol.curGroup.slot1)
                                                    border.width: 1; border.color: Theme.borderSubtle
                                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                                    ThemeGradientFill {
                                                        anchors.fill: parent; anchors.margins: 1
                                                        enabled: hsvStudioCol.hasStop2
                                                        color1: Theme.getSlotHex(hsvStudioCol.curGroup.slot1)
                                                        color2: hsvStudioCol.hasStop2 ? Theme.getSlotHex(hsvStudioCol.curGroup.slot2) : color1
                                                        angle: 90
                                                        cornerRadius: 6
                                                    }
                                                    RowLayout {
                                                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8
                                                        Text {
                                                            text: "Base " + Theme.getSlotHex(hsvStudioCol.curGroup.slot1)
                                                            color: Theme.contrastFg(Theme.getSlotHex(hsvStudioCol.curGroup.slot1))
                                                            font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.Medium
                                                        }
                                                        Item { Layout.fillWidth: true }
                                                        Text {
                                                            text: "End " + (hsvStudioCol.hasStop2 ? Theme.getSlotHex(hsvStudioCol.curGroup.slot2) : "")
                                                            color: hsvStudioCol.hasStop2 ? Theme.contrastFg(Theme.getSlotHex(hsvStudioCol.curGroup.slot2)) : Theme.textSub
                                                            font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.Medium
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // 3. Dedicated Live Preview (clearly separated from Hex input)
                                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderSubtle }

                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text {
                                                text: "LIVE PREVIEW"
                                                color: Theme.textMuted
                                                font.family: Theme.fontSans
                                                font.pixelSize: 10
                                                font.weight: Font.Bold
                                                font.letterSpacing: 0.6
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: (Theme.shellGradientEnabled || Theme.surfaceGradientEnabled || Theme.accentGradientEnabled)
                                                    ? ("Gradient • " + Theme.gradientAngle + "°")
                                                    : "Solid Palette"
                                                color: Theme.textMuted
                                                font.family: Theme.fontMono
                                                font.pixelSize: 10
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true; height: 54; radius: 10; clip: true
                                            color: Theme.surfaceBg
                                            border.width: 1; border.color: Theme.borderSubtle
                                            ThemeGradientFill {
                                                anchors.fill: parent; anchors.margins: 1
                                                enabled: Theme.surfaceGradientEnabled
                                                color1: Theme.surfaceBg; colorMid: Theme.surfaceBgMid; color2: Theme.surfaceBg2
                                                cornerRadius: 9
                                            }
                                            RowLayout {
                                                anchors.fill: parent; anchors.margins: 10; spacing: 10
                                                Rectangle {
                                                    height: 32; radius: 16; clip: true
                                                    Layout.fillWidth: true; Layout.minimumWidth: 0
                                                    color: Theme.pillBg
                                                    border.width: 1; border.color: Theme.borderSubtle
                                                    ThemeGradientFill {
                                                        anchors.fill: parent; anchors.margins: 1
                                                        enabled: Theme.shellGradientEnabled
                                                        color1: Theme.pillBg; colorMid: Theme.pillBgMid; color2: Theme.pillBg2
                                                        cornerRadius: 15
                                                    }
                                                    RowLayout {
                                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12; spacing: 8
                                                        Text {
                                                            text: "24°C"
                                                            color: Theme.text
                                                            font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.Bold
                                                        }
                                                        Item { Layout.fillWidth: true }
                                                        Rectangle {
                                                            implicitWidth: badgePreviewTxt.implicitWidth + 16; height: 20; radius: 10; clip: true
                                                            color: Theme.accent
                                                            ThemeGradientFill {
                                                                anchors.fill: parent
                                                                enabled: Theme.accentGradientEnabled
                                                                color1: Theme.accent; colorMid: Theme.accentMid; color2: Theme.accent2
                                                                cornerRadius: 10
                                                            }
                                                            Text {
                                                                id: badgePreviewTxt
                                                                anchors.centerIn: parent
                                                                text: "Accent"
                                                                color: Theme.accentFg
                                                                font.family: Theme.fontSans; font.pixelSize: 10; font.weight: Font.DemiBold
                                                            }
                                                        }
                                                        Item { Layout.fillWidth: true }
                                                        Text {
                                                            text: "09:41"
                                                            color: Theme.textSub
                                                            font.family: Theme.fontMono; font.pixelSize: 11; font.weight: Font.Medium
                                                        }
                                                    }
                                                }
                                                Rectangle {
                                                    width: 64; height: 32; radius: 8
                                                    color: Theme.surfaceRaised
                                                    border.width: 1; border.color: Theme.borderSubtle
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "Raised"
                                                        color: Theme.textSub
                                                        font.family: Theme.fontSans; font.pixelSize: 11; font.weight: Font.Medium
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            SectionLabel { text: "Pointer & Cursor" }
                            HubCard {
                                iconName: "pointer"
                                title: "Cursor"
                                subtitle: "3 Paithosh custom cursors, size, adaptive contrast & motion blur"
                                pillText: CursorService.styleLabel + " • " + CursorService.size + "px • " + CursorService.colorModeLabel
                                searchKeywords: "cursor pointer mouse hyprcursor xcursor gtk qt auto contrast motion blur"
                                onTriggered: root.openPage("cursor")
                            }

                            SectionLabel { text: "Wallpaper & Transitions" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconName: Theme.wallpapersDisabled ? "eye-off" : "image"
                                    title: "Wallpapers"
                                    subtitle: Theme.wallpapersDisabled
                                        ? "Off • Background follows your manual theme surface color" + (Theme.surfaceGradientEnabled ? " & gradient" : "") + " (adaptive colors off)"
                                        : "Display desktop wallpaper image (turn off to use your theme's surface color & manual colors)"
                                    searchKeywords: "wallpapers disable wallpapers solid background theme color no wallpaper off"

                                    CtrlSwitch {
                                        checked: !Theme.wallpapersDisabled
                                        onToggled: (v) => {
                                            if (root.shellState) root.shellState.setWallpapersDisabled(!v);
                                            else Theme.setWallpapersDisabled(!v);
                                        }
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 12
                                enabled: !Theme.wallpapersDisabled
                                opacity: Theme.wallpapersDisabled ? 0.45 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                WallpaperLockBanner {
                                    active: Theme.reduceMotion && !Theme.wallpapersDisabled
                                    message: "Wallpaper transitions are locked to fast crossfade while Reduce motion~ is active."
                                }

                                GridLayout {
                                    Layout.fillWidth: true; columns: 3; columnSpacing: 8; rowSpacing: 8
                                    enabled: !Theme.reduceMotion
                                    opacity: Theme.reduceMotion ? 0.45 : 1.0
                                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    PresetCard {
                                        title: "Crossfade + Scale"
                                        subtitle: "Smooth zoom & fade"
                                        active: !Theme.reduceMotion && bgLayer.transitionMode === "crossfade-scale"
                                        onTriggered: { bgLayer.transitionMode = "crossfade-scale"; }
                                    }
                                    PresetCard {
                                        title: "Crossfade"
                                        subtitle: "Clean opacity blend"
                                        active: Theme.reduceMotion || bgLayer.transitionMode === "crossfade"
                                        onTriggered: { bgLayer.transitionMode = "crossfade"; }
                                    }
                                    PresetCard {
                                        title: "Instant"
                                        subtitle: "Zero transition delay"
                                        active: !Theme.reduceMotion && bgLayer.transitionMode === "instant"
                                        onTriggered: { bgLayer.transitionMode = "instant"; }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    SvgIcon {
                                        sourceName: "image"
                                        iconSize: 15
                                        color: Theme.textSub
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: bgLayer.wallpapers.length + " / " + bgLayer.maxWallpapers + " • ~/.config/paithosh/wallpapers"
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                        elide: Text.ElideMiddle
                                    }
                                    CtrlBtn {
                                        text: "Open Folder"
                                        ghost: true
                                        onClicked: {
                                            if (root.shellState) root.shellState.openFilesAt(bgLayer.wallpaperDir, "");
                                        }
                                    }
                                    CtrlBtn {
                                        text: bgLayer.importing ? "Adding..." : "Add Wallpaper"
                                        enabled: !bgLayer.importing
                                        onClicked: {
                                            if (root.shellState) root.shellState.openWallpaperPicker();
                                        }
                                    }
                                }
                                Rectangle {
                                    visible: bgLayer.wallpapers.length === 0
                                    Layout.fillWidth: true
                                    implicitHeight: 112
                                    radius: 12
                                    clip: true
                                    color: Theme.cardBg
                                    border.width: 1
                                    border.color: Theme.borderSubtle

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width - 32, 360)
                                        spacing: 8

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: 8
                                            SvgIcon {
                                                sourceName: "image"
                                                iconSize: 18
                                                color: Theme.textSub
                                            }
                                            Text {
                                                text: "No wallpapers in Paithosh yet"
                                                color: Theme.text
                                                font.family: Theme.fontSans
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            horizontalAlignment: Text.AlignHCenter
                                            text: "Add an image to copy it into ~/.config/paithosh/wallpapers and apply it immediately."
                                            color: Theme.textSub
                                            font.family: Theme.fontSans
                                            font.pixelSize: 11
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                                GridLayout {
                                    visible: bgLayer.wallpapers.length > 0
                                    Layout.fillWidth: true
                                    columns: 2
                                    columnSpacing: 10
                                    rowSpacing: 10
                                    Repeater {
                                        model: bgLayer.wallpapers
                                        delegate: Rectangle {
                                            id: wpCard
                                            required property string modelData
                                            required property int index
                                            readonly property bool isActive: bgLayer.currentIndex === index

                                            Layout.fillWidth: true
                                            implicitHeight: 168
                                            radius: 12
                                            clip: true
                                            color: isActive ? Theme.cardHover : (wpMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                                            border.width: isActive ? 2 : 1
                                            border.color: isActive
                                                ? Theme.accent
                                                : (wpMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
                                            scale: wpMouse.pressed ? 0.96 : 1.0

                                            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                            Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 8
                                                spacing: 8

                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    radius: 8
                                                    clip: true
                                                    color: Theme.surfaceRaised

                                                    Image {
                                                        anchors.fill: parent
                                                        source: wpCard.modelData
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true
                                                        cache: true
                                                        sourceSize.width: Theme.reduceMotion ? 240 : 480
                                                        sourceSize.height: Theme.reduceMotion ? 135 : 270
                                                        scale: wpMouse.containsMouse ? 1.04 : 1.0
                                                        opacity: status === Image.Ready ? 1.0 : 0.0
                                                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                    }

                                                    Rectangle {
                                                        anchors.top: parent.top
                                                        anchors.right: parent.right
                                                        anchors.margins: 6
                                                        height: 20
                                                        implicitWidth: wpBadgeLbl.implicitWidth + 14
                                                        radius: 10
                                                        clip: true
                                                        color: wpCard.isActive ? Theme.accent : Qt.rgba(Theme.pillBg.r, Theme.pillBg.g, Theme.pillBg.b, 0.78)
                                                        border.width: wpCard.isActive ? 0 : 1
                                                        border.color: wpMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) : Theme.borderSubtle
                                                        opacity: wpCard.isActive ? 1.0 : (wpMouse.containsMouse ? 1.0 : 0.82)

                                                        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                                        Text {
                                                            id: wpBadgeLbl
                                                            anchors.centerIn: parent
                                                            text: wpCard.isActive ? "Active" : "Apply"
                                                            color: wpCard.isActive ? Theme.accentFg : Theme.text
                                                            font.family: Theme.fontMono
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                        }
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    spacing: 2
                                                    Text {
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 0
                                                        text: wpCard.modelData.split("/").pop()
                                                        color: Theme.text
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: 12
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 0
                                                        text: wpCard.modelData.replace("file://", "")
                                                        color: Theme.textSub
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 10
                                                        elide: Text.ElideMiddle
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: wpMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    bgLayer.selectWallpaper(wpCard.modelData);
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            WallpaperLockBanner {
                                active: Theme.reduceMotion
                                message: "Window decoration, shadows, Kawase blur, and spring physics are locked while Reduce motion~ is active (blur & shadows off, fast slide/fade curves)."
                            }

                            SectionLabel { text: "Window Decoration" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 3; columnSpacing: 8; rowSpacing: 8
                                enabled: !Theme.reduceMotion
                                opacity: Theme.reduceMotion ? 0.45 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                PresetCard {
                                    title: "Soft Glass"
                                    subtitle: "18px • Shadows On"
                                    active: CompositorService.cornerRounding === 18 && CompositorService.shadowEnabled
                                    onTriggered: { CompositorService.setDecoration(18, true, 0.96); root.markAppearanceChanged(); }
                                }
                                PresetCard {
                                    title: "Crisp Modern"
                                    subtitle: "10px • Shadows On"
                                    active: CompositorService.cornerRounding === 10 && CompositorService.shadowEnabled
                                    onTriggered: { CompositorService.setDecoration(10, true, 0.98); root.markAppearanceChanged(); }
                                }
                                PresetCard {
                                    title: "Sharp Minimal"
                                    subtitle: "0px • No Shadows"
                                    active: CompositorService.cornerRounding === 0 && !CompositorService.shadowEnabled
                                    onTriggered: { CompositorService.setDecoration(0, false, 1.0); root.markAppearanceChanged(); }
                                }
                            }

                            SectionLabel { text: "Motion & Blur" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 3; columnSpacing: 8; rowSpacing: 8
                                enabled: !Theme.reduceMotion
                                opacity: Theme.reduceMotion ? 0.45 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                PresetCard {
                                    title: "Paithosh Spring"
                                    subtitle: "Stiffness 260 • Blur 6px"
                                    active: CompositorService.animationsEnabled && CompositorService.springStiffness === 260 && CompositorService.blurEnabled
                                    onTriggered: { CompositorService.setAnimationsEnabled(true); CompositorService.setSpringCurve(260, 23); CompositorService.setBlurConfig(true, 6, 2, 0.12); root.markAppearanceChanged(); }
                                }
                                PresetCard {
                                    title: "Snappy & Crisp"
                                    subtitle: "Stiffness 420 • Blur 4px"
                                    active: CompositorService.animationsEnabled && CompositorService.springStiffness === 420
                                    onTriggered: { CompositorService.setAnimationsEnabled(true); CompositorService.setSpringCurve(420, 30); CompositorService.setBlurConfig(true, 4, 1, 0.08); root.markAppearanceChanged(); }
                                }
                                PresetCard {
                                    title: "Zero Motion"
                                    subtitle: "Animations Off • No Blur"
                                    active: !CompositorService.animationsEnabled && !CompositorService.blurEnabled
                                    onTriggered: { CompositorService.setAnimationsEnabled(false); CompositorService.setBlurConfig(false, 4, 1, 0.0); root.markAppearanceChanged(); }
                                }
                            }

                            SettingGroup {
                                enabled: !Theme.reduceMotion
                                opacity: Theme.reduceMotion ? 0.45 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                SettingRow {
                                    showDivider: false; iconName: "palette"; title: "Drop Shadows"
                                    subtitle: Theme.reduceMotion ? "Disabled by Reduce motion~" : "Render soft ambient window shadows"
                                    CtrlSwitch { checked: !Theme.reduceMotion && CompositorService.shadowEnabled; onToggled: (v) => { CompositorService.setDecoration(CompositorService.cornerRounding, v, CompositorService.inactiveOpacity); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "palette"; title: "Dim inactive windows"
                                    subtitle: Theme.reduceMotion ? "Disabled by Reduce motion~" : "Subtle translucency on unfocused windows"
                                    CtrlSwitch { checked: !Theme.reduceMotion && CompositorService.inactiveOpacity < 0.99; onToggled: (v) => { CompositorService.setDecoration(CompositorService.cornerRounding, CompositorService.shadowEnabled, v ? 0.94 : 1.0); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "palette"; title: "Hyprland Animations"
                                    subtitle: Theme.reduceMotion ? "Managed by Reduce motion~ (fast slide/fade)" : (CompositorService.animationsEnabled ? "Enabled • Spring & bezier motion active" : "Disabled • Instant window transitions")
                                    CtrlSwitch { checked: Theme.reduceMotion || CompositorService.animationsEnabled; onToggled: (v) => { CompositorService.setAnimationsEnabled(v); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "palette"; title: "Kawase Blur"
                                    subtitle: Theme.reduceMotion ? "Disabled by Reduce motion~" : (CompositorService.blurEnabled ? ("Enabled • " + CompositorService.blurSize + "px • " + CompositorService.blurPasses + " passes") : "Disabled")
                                    CtrlSwitch { checked: !Theme.reduceMotion && CompositorService.blurEnabled; onToggled: (v) => { CompositorService.setBlurConfig(v, CompositorService.blurSize, CompositorService.blurPasses, CompositorService.blurVibrancy); root.markAppearanceChanged(); } }
                                }
                            }

                            AdvancedSection {
                                enabled: !Theme.reduceMotion
                                opacity: Theme.reduceMotion ? 0.45 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                subtitle: Theme.reduceMotion ? "Locked while Reduce motion~ is active" : "Corner rounding, shadow spread, spring physics & Kawase blur"
                                SettingRow {
                                    showDivider: false; iconName: "palette"; title: "Corner rounding"; subtitle: "Window border radius"
                                    CtrlSlider { from: 0; to: 28; value: CompositorService.cornerRounding; unit: "px"; onMoved: (v) => { CompositorService.setDecoration(v, CompositorService.shadowEnabled, CompositorService.inactiveOpacity); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "palette"; title: "Inactive opacity"; subtitle: "Opacity of unfocused windows"
                                    CtrlSlider { from: 60; to: 100; value: Math.round(CompositorService.inactiveOpacity * 100); unit: "%"; onMoved: (v) => { CompositorService.setDecoration(CompositorService.cornerRounding, CompositorService.shadowEnabled, v / 100.0); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "palette"; title: "Shadow range"; subtitle: "Drop shadow spread radius"
                                    CtrlSlider { from: 0; to: 48; value: root.shadowRange; unit: "px"; onMoved: (v) => { root.shadowRange = v; Theme.shadowRange = v; root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "palette"; title: "Spring Stiffness"; subtitle: "Motion responsiveness (" + CompositorService.springStiffness + ")"
                                    CtrlSlider { from: 80; to: 600; value: CompositorService.springStiffness; unit: ""; enabled: CompositorService.animationsEnabled; onMoved: (v) => { CompositorService.setSpringCurve(v, CompositorService.springDamping); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "palette"; title: "Spring Damping"; subtitle: "Settle resistance (" + CompositorService.springDamping + ")"
                                    CtrlSlider { from: 5; to: 60; value: CompositorService.springDamping; unit: ""; enabled: CompositorService.animationsEnabled; onMoved: (v) => { CompositorService.setSpringCurve(CompositorService.springStiffness, v); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "palette"; title: "Blur Size"; subtitle: "Kawase blur radius in pixels"
                                    CtrlSlider { from: 1; to: 24; value: CompositorService.blurSize; unit: "px"; enabled: CompositorService.blurEnabled; onMoved: (v) => { CompositorService.setBlurConfig(CompositorService.blurEnabled, v, CompositorService.blurPasses, CompositorService.blurVibrancy); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "palette"; title: "Blur Passes"; subtitle: "Dual-pass iterations (1–6)"
                                    CtrlSlider { from: 1; to: 6; value: CompositorService.blurPasses; unit: ""; enabled: CompositorService.blurEnabled; onMoved: (v) => { CompositorService.setBlurConfig(CompositorService.blurEnabled, CompositorService.blurSize, v, CompositorService.blurVibrancy); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "palette"; title: "Blur Vibrancy"; subtitle: "Color boost (" + Math.round(CompositorService.blurVibrancy * 100) + "%)"
                                    CtrlSlider { from: 0; to: 100; value: Math.round(CompositorService.blurVibrancy * 100); unit: "%"; enabled: CompositorService.blurEnabled; onMoved: (v) => { CompositorService.setBlurConfig(CompositorService.blurEnabled, CompositorService.blurSize, CompositorService.blurPasses, v / 100.0); root.markAppearanceChanged(); } }
                                }
                            }
                        }
                        }

                        // ==================== 11b. CURSOR (Appearance Subpage) ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "cursor"
                            active: Boolean(root.loadedPages["cursor"])
                            sourceComponent: ColumnLayout {
                                id: cursorPageCol
                                spacing: 12

                                function hueToHex(h) {
                                    const c = Qt.hsva(Math.max(0, Math.min(1, h)), 0.78, 0.96, 1.0);
                                    const ch = (v) => {
                                        const hx = Math.max(0, Math.min(255, Math.round(v * 255))).toString(16);
                                        return hx.length === 1 ? ("0" + hx) : hx;
                                    };
                                    return "#" + ch(c.r) + ch(c.g) + ch(c.b);
                                }

                                function hexHue(hex) {
                                    const c = Qt.color(CursorService.normalizeHex(hex));
                                    return c.hslHue >= 0 ? c.hslHue : 0.0;
                                }

                                // Missing mandatory dependency banner
                                Rectangle {
                                    visible: !CursorService.depsReady || CursorService.lastError !== ""
                                    Layout.fillWidth: true
                                    implicitHeight: depWarnRow.implicitHeight + 20
                                    radius: 12
                                    clip: true
                                    color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.14)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.42)

                                    RowLayout {
                                        id: depWarnRow
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 10
                                        SvgIcon { sourceName: "alert-triangle"; iconSize: 16; color: Theme.warn }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 2
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: !CursorService.depsReady ? "Required cursor packages missing" : "Cursor sync warning"
                                                color: Theme.text
                                                font.family: Theme.fontSans
                                                font.pixelSize: 13
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: !CursorService.depsReady
                                                    ? "Install hyprcursor and Cairo/Rsvg renderer to build custom cursors."
                                                    : CursorService.lastError
                                                color: Theme.textSub
                                                font.family: Theme.fontSans
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                        }
                                        CtrlBtn {
                                            visible: !CursorService.depsReady
                                            text: PackageService.installingDeps ? "Installing..." : "Install Required"
                                            enabled: !PackageService.installingDeps
                                            onClicked: PackageService.installMissingCoreDeps(() => { CursorService.checkDeps(() => CursorService.applyNow(true)); })
                                        }
                                    }
                                }

                                // Tier 1: 3 Closed Custom Cursor Showcase Cards
                                SectionLabel { text: "Cursor Style (Paithosh Collection)" }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 3
                                    columnSpacing: 10
                                    rowSpacing: 10

                                    Repeater {
                                        model: CursorService.styleCatalog
                                        delegate: Rectangle {
                                            id: curCard
                                            required property var modelData
                                            readonly property bool isSelected: CursorService.style === modelData.id
                                            readonly property bool spotActive: root.isSpotlightActive()
                                            readonly property bool spotMatched: !spotActive || root.matchesSpotlight(modelData.name, modelData.subtitle, "cursor style sharp soft wedge")

                                            Layout.fillWidth: true
                                            implicitHeight: 172
                                            radius: 12
                                            clip: true
                                            opacity: spotMatched ? 1.0 : 0.28
                                            color: isSelected
                                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                                : (curMouse.containsMouse ? Theme.cardHover : Theme.cardBg)
                                            border.width: isSelected ? 1.5 : 1
                                            border.color: isSelected
                                                ? Theme.accent
                                                : (curMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
                                            scale: curMouse.pressed ? 0.96 : 1.0

                                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 8

                                                // Split Dark/Light Preview Stage (concentric radius 8)
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    radius: 8
                                                    clip: true
                                                    color: Theme.pillBg
                                                    border.width: 1
                                                    border.color: Theme.borderSubtle

                                                    // Right light contrast surface
                                                    Rectangle {
                                                        anchors.top: parent.top
                                                        anchors.bottom: parent.bottom
                                                        anchors.right: parent.right
                                                        width: Math.round(parent.width / 2)
                                                        color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.88)
                                                    }

                                                    // Live generated cursor vector preview
                                                    Image {
                                                        anchors.centerIn: parent
                                                        width: 48
                                                        height: 48
                                                        sourceSize: Qt.size(96, 96)
                                                        source: CursorService.previewTag !== ""
                                                            ? ("file://" + CursorService.previewDir + "/preview-" + curCard.modelData.id + "-" + CursorService.previewTag + ".svg")
                                                            : ""
                                                        smooth: true
                                                        asynchronous: true
                                                        cache: false
                                                        scale: curMouse.containsMouse ? 1.10 : (curCard.isSelected ? 1.04 : 1.0)
                                                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }
                                                    }

                                                    // Earned Active badge
                                                    Rectangle {
                                                        anchors.top: parent.top
                                                        anchors.right: parent.right
                                                        anchors.margins: 6
                                                        height: 18
                                                        implicitWidth: curActiveLbl.implicitWidth + 12
                                                        radius: 9
                                                        clip: true
                                                        color: Theme.accent
                                                        opacity: curCard.isSelected ? 1.0 : 0.0
                                                        scale: curCard.isSelected ? 1.0 : 0.88
                                                        visible: opacity > 0.01
                                                        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                                        Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutBack } }

                                                        Text {
                                                            id: curActiveLbl
                                                            anchors.centerIn: parent
                                                            text: "Active"
                                                            color: Theme.accentFg
                                                            font.family: Theme.fontMono
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                        }
                                                    }
                                                }

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    spacing: 2
                                                    Text {
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 0
                                                        text: curCard.modelData.name
                                                        color: Theme.text
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: 13
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 0
                                                        text: curCard.modelData.subtitle
                                                        color: Theme.textSub
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: 11
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: curMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    CursorService.setStyle(curCard.modelData.id);
                                                    root.markAppearanceChanged();
                                                }
                                            }
                                        }
                                    }
                                }

                                // Tier 2: Core Options
                                SectionLabel { text: "Scale, Color & Motion" }
                                SettingGroup {
                                    SettingRow {
                                        showDivider: false
                                        iconName: "maximize"
                                        title: "Cursor Size"
                                        subtitle: "Quick scale presets • Synced across Hyprland, GTK & Qt"
                                        searchKeywords: "cursor size scale px 20 24 32 40"

                                        RowLayout {
                                            spacing: 6
                                            Repeater {
                                                model: [20, 24, 32, 40]
                                                delegate: Rectangle {
                                                    id: szChip
                                                    required property int modelData
                                                    readonly property bool active: CursorService.size === modelData
                                                    implicitWidth: szLbl.implicitWidth + 16
                                                    height: 28
                                                    radius: 8
                                                    clip: true
                                                    color: active
                                                        ? Theme.accent
                                                        : (szMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised)
                                                    border.width: 1
                                                    border.color: active
                                                        ? Theme.accent
                                                        : (szMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42) : Theme.borderSubtle)
                                                    scale: szMouse.pressed ? 0.94 : 1.0
                                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                                                    Text {
                                                        id: szLbl
                                                        anchors.centerIn: parent
                                                        text: szChip.modelData + "px"
                                                        color: szChip.active ? Theme.accentFg : Theme.text
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                    }

                                                    MouseArea {
                                                        id: szMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            CursorService.setSize(szChip.modelData);
                                                            root.markAppearanceChanged();
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    SettingRow {
                                        iconName: "contrast"
                                        title: "Color Mode"
                                        subtitle: "Auto screen contrast, active theme accent, or fixed color"
                                        searchKeywords: "cursor color auto contrast theme fixed"

                                        RowLayout {
                                            spacing: 6
                                            Repeater {
                                                model: [
                                                    { id: "auto", label: "Auto Contrast" },
                                                    { id: "theme", label: "Theme" },
                                                    { id: "fixed", label: "Fixed" }
                                                ]
                                                delegate: Rectangle {
                                                    id: cmChip
                                                    required property var modelData
                                                    readonly property bool active: CursorService.colorMode === modelData.id
                                                    implicitWidth: cmLbl.implicitWidth + 18
                                                    height: 28
                                                    radius: 8
                                                    clip: true
                                                    color: active
                                                        ? Theme.accent
                                                        : (cmMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised)
                                                    border.width: 1
                                                    border.color: active
                                                        ? Theme.accent
                                                        : (cmMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.42) : Theme.borderSubtle)
                                                    scale: cmMouse.pressed ? 0.94 : 1.0
                                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                                                    Text {
                                                        id: cmLbl
                                                        anchors.centerIn: parent
                                                        text: cmChip.modelData.label
                                                        color: cmChip.active ? Theme.accentFg : Theme.text
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                    }

                                                    MouseArea {
                                                        id: cmMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            CursorService.setColorMode(cmChip.modelData.id);
                                                            root.markAppearanceChanged();
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Animated Color Mode Detail Drawer (zero 0ms snap, strict clip)
                                    Item {
                                        id: colorDrawer
                                        Layout.fillWidth: true
                                        implicitHeight: {
                                            if (CursorService.colorMode === "fixed") return fixedDetailCol.implicitHeight + 24;
                                            if (CursorService.colorMode === "theme") return themeDetailRow.implicitHeight + 20;
                                            return autoDetailRow.implicitHeight + 20;
                                        }
                                        clip: true
                                        Behavior on implicitHeight { NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic } }

                                        Rectangle {
                                            anchors.top: parent.top
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            height: 1
                                            color: Theme.borderSubtle
                                        }

                                        // Auto Contrast Detail
                                        RowLayout {
                                            id: autoDetailRow
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 14
                                            anchors.topMargin: 10
                                            spacing: 10
                                            opacity: CursorService.colorMode === "auto" ? 1.0 : 0.0
                                            visible: opacity > 0.01
                                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: "Samples luminance under the cursor to flip dark/light ink smoothly."
                                                color: Theme.textSub
                                                font.family: Theme.fontSans
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                            Rectangle {
                                                height: 24
                                                implicitWidth: autoToneLbl.implicitWidth + 16
                                                radius: 8
                                                clip: true
                                                color: Theme.surfaceRaised
                                                border.width: 1
                                                border.color: Theme.borderSubtle
                                                Text {
                                                    id: autoToneLbl
                                                    anchors.centerIn: parent
                                                    text: CursorService.activeContrastTone === "dark" ? "Screen Light → Dark Ink" : "Screen Dark → Light Ink"
                                                    color: Theme.text
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 10
                                                }
                                            }
                                        }

                                        // Follow Theme Detail
                                        RowLayout {
                                            id: themeDetailRow
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 14
                                            anchors.topMargin: 10
                                            spacing: 10
                                            opacity: CursorService.colorMode === "theme" ? 1.0 : 0.0
                                            visible: opacity > 0.01
                                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                            Rectangle {
                                                width: 22
                                                height: 22
                                                radius: 11
                                                color: Theme.accent
                                                border.width: 2
                                                border.color: Theme.accentFg
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: "Synced to " + Theme.activePreset + " accent • Contrasting outline computed automatically"
                                                color: Theme.textSub
                                                font.family: Theme.fontSans
                                                font.pixelSize: 11
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: String(Theme.accent).toLowerCase()
                                                color: Theme.text
                                                font.family: Theme.fontMono
                                                font.pixelSize: 11
                                            }
                                        }

                                        // Fixed Color Detail
                                        ColumnLayout {
                                            id: fixedDetailCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 14
                                            anchors.topMargin: 12
                                            spacing: 10
                                            opacity: CursorService.colorMode === "fixed" ? 1.0 : 0.0
                                            visible: opacity > 0.01
                                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 8

                                                Repeater {
                                                    model: CursorService.fixedSwatches
                                                    delegate: Rectangle {
                                                        id: swDot
                                                        required property string modelData
                                                        readonly property bool active: CursorService.fixedColor.toLowerCase() === modelData.toLowerCase()
                                                        width: 24
                                                        height: 24
                                                        radius: 12
                                                        color: modelData
                                                        border.width: active ? 2 : 1
                                                        border.color: active ? Theme.accent : Theme.borderSubtle
                                                        scale: swDotMouse.pressed ? 0.90 : (swDotMouse.containsMouse ? 1.08 : 1.0)
                                                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }

                                                        MouseArea {
                                                            id: swDotMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                CursorService.setFixedColor(swDot.modelData);
                                                                root.markAppearanceChanged();
                                                            }
                                                        }
                                                    }
                                                }

                                                HueSlider {
                                                    Layout.fillWidth: true
                                                    value: cursorPageCol.hexHue(CursorService.fixedColor)
                                                    onMoved: {
                                                        CursorService.setFixedColor(cursorPageCol.hueToHex(value));
                                                        root.markAppearanceChanged();
                                                    }
                                                }

                                                Rectangle {
                                                    height: 24
                                                    implicitWidth: hexLbl.implicitWidth + 14
                                                    radius: 6
                                                    color: Theme.surfaceRaised
                                                    border.width: 1
                                                    border.color: Theme.borderSubtle
                                                    Text {
                                                        id: hexLbl
                                                        anchors.centerIn: parent
                                                        text: CursorService.fixedColor
                                                        color: Theme.text
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 10
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    SettingRow {
                                        iconName: "sparkles"
                                        title: "Motion Blur Cursor"
                                        subtitle: Theme.reduceMotion
                                            ? "Disabled by Reduce motion~"
                                            : (CursorService.motionBlur
                                                ? ("32-tap GPU shutter blur • Synced to " + Math.round(CursorService.cursorRefreshHz) + " Hz display")
                                                : "Continuous directional GPU blur synced to display refresh rate")
                                        searchKeywords: "cursor motion blur experimental trail refresh rate hz"
                                        enabled: !Theme.reduceMotion
                                        opacity: Theme.reduceMotion ? 0.45 : 1.0

                                        RowLayout {
                                            spacing: 10
                                            Rectangle {
                                                height: 20
                                                implicitWidth: expLbl.implicitWidth + 12
                                                radius: 6
                                                clip: true
                                                color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.14)
                                                border.width: 1
                                                border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.42)
                                                Text {
                                                    id: expLbl
                                                    anchors.centerIn: parent
                                                    text: "Experimental"
                                                    color: Theme.warn
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                            CtrlSwitch {
                                                checked: !Theme.reduceMotion && CursorService.motionBlur
                                                enabled: !Theme.reduceMotion
                                                onToggled: (v) => {
                                                    CursorService.setMotionBlur(v);
                                                    root.markAppearanceChanged();
                                                }
                                            }
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: (!Theme.reduceMotion && CursorService.motionBlur) ? blurThreshRow.implicitHeight : 0
                                        clip: true
                                        visible: Layout.preferredHeight > 0.5
                                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                        SettingRow {
                                            id: blurThreshRow
                                            width: parent.width
                                            iconName: "zap"
                                            title: "Activation Speed"
                                            subtitle: CursorService.motionBlurThreshold <= 0
                                                ? "Always active • Blurs even during slow pointer movement"
                                                : ("No shadow on slow moves • Triggers above " + CursorService.motionBlurThreshold + " px/s")
                                            searchKeywords: "cursor motion blur activation speed threshold acceleration trigger"
                                            opacity: (!Theme.reduceMotion && CursorService.motionBlur) ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                            CtrlSlider {
                                                from: 0; to: 2400; stepSize: 100; value: CursorService.motionBlurThreshold; unit: "px/s"
                                                enabled: !Theme.reduceMotion && CursorService.motionBlur
                                                onMoved: (v) => {
                                                    CursorService.setMotionBlurThreshold(v);
                                                }
                                            }
                                        }
                                    }

                                    SettingRow {
                                        iconName: "layers"
                                        title: "Hyprcursor, GTK & Qt Sync"
                                        subtitle: CursorService.applying
                                            ? "Building dual-format Hyprcursor & XCursor assets..."
                                            : (CursorService.activeThemeId !== ""
                                                ? ("Active: " + CursorService.activeThemeId + " • GTK3/4 + Qt5/6")
                                                : "Syncs Hyprcursor, XCursor, gsettings & KDE/Qt")
                                        searchKeywords: "cursor sync gtk qt hyprcursor xcursor"

                                        CtrlBtn {
                                            text: CursorService.applying ? "Syncing..." : "Re-sync"
                                            ghost: true
                                            enabled: !CursorService.applying && CursorService.depsReady
                                            onClicked: CursorService.applyNow(true)
                                        }
                                    }
                                }

                                // Tier 3: Collapsed Advanced Section
                                AdvancedSection {
                                    expanded: false
                                    subtitle: "Fine cursor size (16–64px), motion blur strength & reset"
                                    SettingRow {
                                        showDivider: false
                                        iconName: "maximize"
                                        title: "Fine Cursor Size"
                                        subtitle: "Exact logical pixel height across all toolkits"
                                        searchKeywords: "cursor size slider fine px"
                                        CtrlSlider {
                                            from: 16; to: 64; stepSize: 1; value: CursorService.size; unit: "px"
                                            onMoved: (v) => {
                                                CursorService.setSize(v);
                                                root.markAppearanceChanged();
                                            }
                                        }
                                    }
                                    SettingRow {
                                        iconName: "sparkles"
                                        title: "Motion Blur Intensity"
                                        subtitle: Theme.reduceMotion ? "Disabled by Reduce motion~" : "Trail opacity & velocity stretch"
                                        searchKeywords: "cursor motion blur intensity strength"
                                        enabled: !Theme.reduceMotion
                                        opacity: Theme.reduceMotion ? 0.45 : 1.0
                                        CtrlSlider {
                                            from: 30; to: 100; stepSize: 5; value: Math.round(CursorService.motionBlurStrength * 100); unit: "%"
                                            enabled: !Theme.reduceMotion && CursorService.motionBlur
                                            onMoved: (v) => {
                                                CursorService.setMotionBlurStrength(v / 100.0);
                                            }
                                        }
                                    }
                                    SettingRow {
                                        iconName: "refresh"
                                        title: "Reset Cursor Defaults"
                                        subtitle: "Classic Sharp • 24px • Auto Contrast • Motion Blur Off"
                                        searchKeywords: "cursor reset default"
                                        CtrlBtn {
                                            text: "Reset"
                                            ghost: true
                                            onClicked: {
                                                CursorService.resetDefaults();
                                                root.markAppearanceChanged();
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ==================== 12. LAYOUT ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "layout"
                            active: Boolean(root.loadedPages["layout"])
                            sourceComponent: ColumnLayout {
                            spacing: 12

                            SectionLabel { text: "Window Tiling Layout" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 2; columnSpacing: 10; rowSpacing: 10
                                Repeater {
                                    model: [
                                        { id: "dwindle", name: "Dwindle", desc: "Binary space partitioning that splits each new window cleanly." },
                                        { id: "master", name: "Master", desc: "Large primary workspace on the left with stacked auxiliaries." }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool selected: CompositorService.layoutName === modelData.id
                                        Layout.fillWidth: true; height: 98; radius: 12
                                        clip: true
                                        color: (selected || layoutMouse.containsMouse) ? Theme.cardHover : Theme.cardBg
                                        border.width: selected ? 2 : 1
                                        border.color: selected ? Theme.accent : (layoutMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
                                        scale: layoutMouse.pressed ? 0.98 : 1.0
                                        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                        RowLayout {
                                            anchors.fill: parent; anchors.margins: 12; spacing: 12
                                            Rectangle {
                                                width: 64; height: 44; radius: 6; color: Theme.surfaceRaised
                                                border.width: 1; border.color: (selected || layoutMouse.containsMouse) ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                                                Behavior on border.color { ColorAnimation { duration: 140 } }
                                                Rectangle { x: 4; y: 4; width: 26; height: 36; radius: 3; color: Theme.accent; opacity: (selected || layoutMouse.containsMouse) ? 0.95 : 0.78; Behavior on opacity { NumberAnimation { duration: 140 } } }
                                                Rectangle { x: 34; y: 4; width: 26; height: 16; radius: 3; color: Theme.textSub; opacity: 0.65 }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 3
                                                Text { text: modelData.name; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                                                Text { Layout.fillWidth: true; text: modelData.desc; color: Theme.textSub; font.pixelSize: 11; wrapMode: Text.WordWrap }
                                            }
                                        }
                                        MouseArea {
                                            id: layoutMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: { root.activeLayout = modelData.id; CompositorService.setLayout(modelData.id); }
                                        }
                                    }
                                }
                            }
                            AdvancedSection {
                                subtitle: "Master split ratio & split orientation"
                                SettingRow {
                                    showDivider: false; iconName: "layout"; title: "Master split ratio"; subtitle: "Percentage width reserved for primary window"
                                    CtrlSlider { from: 30; to: 80; value: root.masterRatio; unit: "%"; onMoved: (v) => { root.masterRatio = v; Theme.masterRatio = v; root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    title: "Preserve split direction"; subtitle: "Keep orientation consistent when closing windows"
                                    CtrlTickBox { checked: root.preserveSplit; onToggled: (v) => { root.preserveSplit = v; Theme.preserveSplit = v; root.markAppearanceChanged(); } }
                                }
                            }

                            SectionLabel { text: "Gaps & Borders" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 3; columnSpacing: 8; rowSpacing: 8
                                PresetCard {
                                    title: "Compact"
                                    subtitle: "In 3px • Out 6px • 1px"
                                    active: CompositorService.gapsIn === 3 && CompositorService.gapsOut === 6
                                    onTriggered: { CompositorService.setGapsAndBorder(3, 6, 1); root.markAppearanceChanged(); }
                                }
                                PresetCard {
                                    title: "Balanced"
                                    subtitle: "In 6px • Out 12px • 1px"
                                    active: CompositorService.gapsIn === 6 && CompositorService.gapsOut === 12
                                    onTriggered: { CompositorService.setGapsAndBorder(6, 12, 1); root.markAppearanceChanged(); }
                                }
                                PresetCard {
                                    title: "Spacious"
                                    subtitle: "In 12px • Out 24px • 2px"
                                    active: CompositorService.gapsIn === 12 && CompositorService.gapsOut === 24
                                    onTriggered: { CompositorService.setGapsAndBorder(12, 24, 2); root.markAppearanceChanged(); }
                                }
                            }

                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconName: "square-rounded"; title: "Active Border Highlight"; subtitle: "Show crisp outline on focused window"
                                    CtrlSwitch {
                                        checked: root.shellState ? root.shellState.activeBorderHighlight : root.activeBorderHighlight
                                        onToggled: (v) => {
                                            root.activeBorderHighlight = v;
                                            if (root.shellState) root.shellState.activeBorderHighlight = v;
                                            root.markAppearanceChanged();
                                        }
                                    }
                                }
                            }

                            AdvancedSection {
                                subtitle: "Raw inner/outer pixel gaps & border thickness"
                                SettingRow {
                                    showDivider: false; iconName: "grid-gap"; title: "Inner gaps"; subtitle: "Space between tiled windows"
                                    CtrlSlider { from: 0; to: 32; value: CompositorService.gapsIn; unit: "px"; onMoved: (v) => { CompositorService.setGapsAndBorder(v, CompositorService.gapsOut, CompositorService.borderSize); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "grid-gap"; title: "Outer gaps"; subtitle: "Margin around screen edges"
                                    CtrlSlider { from: 0; to: 48; value: CompositorService.gapsOut; unit: "px"; onMoved: (v) => { CompositorService.setGapsAndBorder(CompositorService.gapsIn, v, CompositorService.borderSize); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconName: "square-rounded"; title: "Border thickness"; subtitle: "Window stroke width"
                                    CtrlSlider { from: 0; to: 6; value: CompositorService.borderSize; unit: "px"; onMoved: (v) => { CompositorService.setGapsAndBorder(CompositorService.gapsIn, CompositorService.gapsOut, v); root.markAppearanceChanged(); } }
                                }
                            }

                            SectionLabel { text: "Dynamic Island Bar" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 3; columnSpacing: 8; rowSpacing: 8
                                PresetCard {
                                    title: "Floating Pill"
                                    subtitle: "26px radius • 12px offset"
                                    active: (root.shellState ? root.shellState.islandCornerRadius : root.islandCornerRadius) === "26px (Default)" && (root.shellState ? root.shellState.topEdgeOffset : root.topEdgeOffset)
                                    onTriggered: {
                                        root.islandCornerRadius = "26px (Default)";
                                        root.topEdgeOffset = true;
                                        if (root.shellState) {
                                            root.shellState.islandCornerRadius = "26px (Default)";
                                            root.shellState.topEdgeOffset = true;
                                        }
                                    }
                                }
                                PresetCard {
                                    title: "Compact Bar"
                                    subtitle: "12px radius • Flush top"
                                    active: (root.shellState ? root.shellState.islandCornerRadius : root.islandCornerRadius) === "12px" && !(root.shellState ? root.shellState.topEdgeOffset : root.topEdgeOffset)
                                    onTriggered: {
                                        root.islandCornerRadius = "12px";
                                        root.topEdgeOffset = false;
                                        if (root.shellState) {
                                            root.shellState.islandCornerRadius = "12px";
                                            root.shellState.topEdgeOffset = false;
                                        }
                                    }
                                }
                                PresetCard {
                                    title: "Stealth Auto"
                                    subtitle: "18px • Auto-hide active"
                                    active: (root.shellState ? root.shellState.islandCornerRadius : root.islandCornerRadius) === "18px" && (root.shellState ? root.shellState.autoHideOnOverlap : false)
                                    onTriggered: {
                                        root.islandCornerRadius = "18px";
                                        root.hideBarFullscreen = true;
                                        root.islandAutoHide = true;
                                        if (root.shellState) {
                                            root.shellState.islandCornerRadius = "18px";
                                            root.shellState.hideBarFullscreen = true;
                                            root.shellState.autoHideOnOverlap = true;
                                            root.shellState.dodgeCursor = false;
                                        }
                                    }
                                }
                            }

                            SettingGroup {
                                SettingRow {
                                    iconName: "move-vertical"
                                    title: "Status bar position"
                                    subtitle: "Place Dynamic Island at the top or bottom edge of the screen"
                                    CtrlSelect {
                                        options: ["Top", "Bottom"]
                                        currentText: (root.shellState ? root.shellState.barPosition : root.barPosition) === "bottom" ? "Bottom" : "Top"
                                        onSelected: (v) => {
                                            const pos = (v === "Bottom") ? "bottom" : "top";
                                            root.barPosition = pos;
                                            if (root.shellState) root.shellState.barPosition = pos;
                                            root.markAppearanceChanged();
                                        }
                                    }
                                }
                                SettingRow {
                                    showDivider: false
                                    iconName: "maximize"
                                    title: "Behavior"
                                    subtitle: "Control when Dynamic Island hides on cursor hover (hold Super to interact), fullscreen, or overlap"
                                    CtrlSelect {
                                        options: ["Always Show", "Dodge Cursor", "Hide in Fullscreen", "Auto-Hide (Overlap)"]
                                        currentText: {
                                            if (root.shellState) {
                                                if (root.shellState.dodgeCursor) return "Dodge Cursor";
                                                if (root.shellState.autoHideOnOverlap) return "Auto-Hide (Overlap)";
                                                if (root.shellState.hideBarFullscreen) return "Hide in Fullscreen";
                                                return "Always Show";
                                            }
                                            return root.hideBarFullscreen ? "Hide in Fullscreen" : "Always Show";
                                        }
                                        onSelected: (v) => {
                                            if (v === "Always Show") {
                                                root.hideBarFullscreen = false;
                                                root.islandAutoHide = false;
                                                if (root.shellState) {
                                                    root.shellState.hideBarFullscreen = false;
                                                    root.shellState.autoHideOnOverlap = false;
                                                    root.shellState.dodgeCursor = false;
                                                }
                                            } else if (v === "Dodge Cursor") {
                                                root.hideBarFullscreen = false;
                                                root.islandAutoHide = false;
                                                if (root.shellState) {
                                                    root.shellState.hideBarFullscreen = false;
                                                    root.shellState.autoHideOnOverlap = false;
                                                    root.shellState.dodgeCursor = true;
                                                }
                                            } else if (v === "Hide in Fullscreen") {
                                                root.hideBarFullscreen = true;
                                                root.islandAutoHide = true;
                                                if (root.shellState) {
                                                    root.shellState.hideBarFullscreen = true;
                                                    root.shellState.autoHideOnOverlap = false;
                                                    root.shellState.dodgeCursor = false;
                                                }
                                            } else {
                                                root.hideBarFullscreen = true;
                                                root.islandAutoHide = true;
                                                if (root.shellState) {
                                                    root.shellState.hideBarFullscreen = true;
                                                    root.shellState.autoHideOnOverlap = true;
                                                    root.shellState.dodgeCursor = false;
                                                }
                                            }
                                            root.markAppearanceChanged();
                                        }
                                    }
                                }
                            }

                            AdvancedSection {
                                subtitle: "Corner radius & screen edge offset"
                                SettingRow {
                                    showDivider: false; iconName: "square-rounded"; title: "Status bar corner radius"; subtitle: "Roundness of Dynamic Island pills"
                                    CtrlSelect {
                                        options: ["12px", "18px", "26px (Default)"]
                                        currentText: root.shellState ? root.shellState.islandCornerRadius : root.islandCornerRadius
                                        onSelected: (v) => {
                                            root.islandCornerRadius = v;
                                            if (root.shellState) root.shellState.islandCornerRadius = v;
                                            root.markAppearanceChanged();
                                        }
                                    }
                                }
                                SettingRow {
                                    iconName: "move-vertical"; title: "Screen edge offset"; subtitle: "12px at rest, 16px on hover / Dashboard"
                                    CtrlSwitch {
                                        checked: root.shellState ? root.shellState.topEdgeOffset : root.topEdgeOffset
                                        onToggled: (v) => {
                                            root.topEdgeOffset = v;
                                            if (root.shellState) root.shellState.topEdgeOffset = v;
                                            root.markAppearanceChanged();
                                        }
                                    }
                                }
                            }
                        }
                        }

                        // ==================== KEYBINDS ====================
                        Loader {
                            id: keybindPageLoader
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "keybind"
                            active: Boolean(root.loadedPages["keybind"])
                            function ensureSource() {
                                if (active && source.toString() === "") setSource("KeybindSettingsPage.qml");
                            }
                            Component.onCompleted: ensureSource()
                            onActiveChanged: ensureSource()
                        }
                        Connections {
                            target: keybindPageLoader.item
                            function onEditRequested(bindObj, comboIdx, defaultTab) {
                                keybindEditorLoader.openEditor(bindObj, comboIdx, defaultTab);
                            }
                        }

                        // ==================== 12b. LOCK SCREEN ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "lockscreen"
                            active: Boolean(root.loadedPages["lockscreen"])
                            sourceComponent: ColumnLayout {
                                id: lockScreenPage
                                spacing: 14

                                readonly property string effectLabel: {
                                    if (LockService.effectPreset === "snow") return "Snowfall";
                                    if (LockService.effectPreset === "rain") return "Rain";
                                    if (LockService.effectPreset === "wind") return "Wind Breeze";
                                    return "None";
                                }
                                readonly property string soundLabel: {
                                    if (LockService.silentMode || LockService.ambientSound === "none") return "Silent";
                                    if (LockService.ambientSound === "wind") return "Gentle Wind";
                                    if (LockService.ambientSound === "rain") return "Soft Rain";
                                    if (LockService.ambientSound === "snow") return "Winter Air";
                                    return "Silent";
                                }
                                readonly property string widgetSummary: {
                                    const parts = [];
                                    if (LockService.showNotifications) parts.push("Notifs");
                                    if (LockService.showMedia) parts.push("Media");
                                    if (LockService.showSystemAlerts) parts.push("Alerts");
                                    return parts.length > 0 ? parts.join(" + ") : "Minimal";
                                }

                                // 0. Live Lock Screen Preview Card
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: lockPreviewCol.implicitHeight + 24
                                    radius: 14
                                    color: Theme.cardBg
                                    border.width: 1
                                    border.color: Theme.borderSubtle
                                    clip: true

                                    ColumnLayout {
                                        id: lockPreviewCol
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 10

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 2
                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: "Lock Screen Preview"
                                                    color: Theme.text
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: lockScreenPage.effectLabel + " • " + (LockService.silentMode ? "Silent Lock" : lockScreenPage.soundLabel) + " • " + lockScreenPage.widgetSummary
                                                    color: Theme.textSub
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 11
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            CtrlBtn {
                                                text: SoundService.previewAmbientPlaying ? "Stop Audio" : "Preview Audio"
                                                ghost: !SoundService.previewAmbientPlaying
                                                enabled: !LockService.silentMode && LockService.ambientSound !== "none" && SoundService.enabled
                                                onClicked: SoundService.togglePreviewAmbient(LockService.ambientSound)
                                            }
                                            CtrlBtn {
                                                text: "Test Lock"
                                                ghost: true
                                                onClicked: {
                                                    SoundService.stopPreviewAmbient();
                                                    LockService.lock();
                                                }
                                            }
                                        }

                                        // Preview Canvas (Real Wallpaper + Dim Scrim + Ambient Effect + Scaled Pills + Toast)
                                        Rectangle {
                                            id: lockPreviewCanvas
                                            readonly property bool isBottomPreview: (root.shellState ? root.shellState.barPosition : root.barPosition) === "bottom"
                                            Layout.fillWidth: true
                                            height: 210
                                            radius: 10
                                            clip: true
                                            color: Theme.surfaceBg
                                            border.width: 1
                                            border.color: Theme.borderSubtle

                                            ThemeGradientFill {
                                                anchors.fill: parent
                                                cornerRadius: 10
                                                enabled: Theme.surfaceGradientEnabled
                                                color1: Theme.surfaceBg
                                                colorMid: Theme.surfaceBgMid
                                                color2: Theme.surfaceBg2
                                                angle: Theme.gradientAngle
                                            }

                                            Image {
                                                anchors.fill: parent
                                                source: (typeof bgLayer !== "undefined" && bgLayer.wallpapers && bgLayer.wallpapers.length > 0)
                                                    ? bgLayer.wallpapers[Math.max(0, Math.min(bgLayer.currentIndex, bgLayer.wallpapers.length - 1))]
                                                    : ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                smooth: true
                                                sourceSize.width: Theme.reduceMotion ? 360 : 960
                                                sourceSize.height: Theme.reduceMotion ? 202 : 540
                                                opacity: (!Theme.wallpapersDisabled && status === Image.Ready) ? 1.0 : 0.0
                                                visible: opacity > 0.002
                                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            }

                                            // Backdrop Dim Scrim
                                            Rectangle {
                                                anchors.fill: parent
                                                color: Theme.pillBg
                                                opacity: LockService.dimOpacity / 100.0
                                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            }

                                            // Live Ambient Visual Effect
                                            LockAmbientEffect {
                                                anchors.fill: parent
                                                effect: LockService.effectPreset
                                                intensity: LockService.effectIntensity
                                                active: root.currentPage === "lockscreen" && root.visible
                                                previewMode: true
                                            }

                                            // Scaled Orbiting Lock Pill Row
                                            Row {
                                                id: previewPillRow
                                                spacing: 0
                                                height: 30
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                y: lockPreviewCanvas.isBottomPreview ? (parent.height - height - 10) : 10
                                                Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                                // Main Lock Pill
                                                Rectangle {
                                                    height: 30
                                                    width: previewMainRow.implicitWidth + 22
                                                    radius: 15
                                                    color: Theme.pillBg
                                                    border.width: 1
                                                    border.color: Theme.borderSubtle
                                                    clip: true

                                                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                                    Row {
                                                        id: previewMainRow
                                                        anchors.centerIn: parent
                                                        spacing: 8

                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: WeatherService.tempText
                                                            color: Theme.text
                                                            font.family: Theme.fontSans
                                                            font.pixelSize: 11
                                                            font.weight: Font.Bold
                                                        }

                                                        SvgIcon {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            sourceName: "lock"
                                                            iconSize: 11
                                                            color: Theme.textSub
                                                        }

                                                        Item {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            height: 18
                                                            width: LockService.showNotifications ? 16 : 0
                                                            opacity: LockService.showNotifications ? 1.0 : 0.0
                                                            clip: true
                                                            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                            Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                                            SvgIcon {
                                                                anchors.centerIn: parent
                                                                sourceName: "bell"
                                                                iconSize: 11
                                                                color: Theme.text
                                                            }
                                                            Rectangle {
                                                                width: 5
                                                                height: 5
                                                                radius: 2.5
                                                                color: Theme.danger
                                                                anchors.right: parent.right
                                                                anchors.top: parent.top
                                                                anchors.topMargin: 2
                                                                anchors.rightMargin: 1
                                                            }
                                                        }

                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: Qt.formatTime(new Date(), "hh:mm")
                                                            color: Theme.text
                                                            font.family: Theme.fontMono
                                                            font.pixelSize: 11
                                                            font.weight: Font.Medium
                                                        }
                                                    }
                                                }

                                                // Scaled Media Split Pill
                                                Item {
                                                    height: 30
                                                    clip: true
                                                    width: LockService.showMedia ? (8 + previewMediaPill.width) : 0
                                                    opacity: LockService.showMedia ? 1.0 : 0.0
                                                    visible: width > 0.5 || opacity > 0.01

                                                    Behavior on width {
                                                        NumberAnimation {
                                                            duration: LockService.showMedia ? Theme.springMs : Theme.smoothMs
                                                            easing.type: LockService.showMedia ? Easing.OutBack : Easing.OutCubic
                                                            easing.overshoot: 0.75
                                                        }
                                                    }
                                                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                    Rectangle {
                                                        id: previewMediaPill
                                                        x: LockService.showMedia ? 8 : 0
                                                        height: 30
                                                        width: Math.min(138, previewMediaRow.implicitWidth + 18)
                                                        radius: 15
                                                        color: Theme.pillBg
                                                        border.width: 1
                                                        border.color: Theme.borderSubtle
                                                        scale: LockService.showMedia ? 1.0 : 0.86
                                                        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                        Behavior on scale { NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

                                                        Row {
                                                            id: previewMediaRow
                                                            anchors.centerIn: parent
                                                            spacing: 6

                                                            Row {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                spacing: 1.5
                                                                height: 10
                                                                Rectangle { width: 2; height: 6; y: 2; radius: 1; color: Theme.accent }
                                                                Rectangle { width: 2; height: 10; y: 0; radius: 1; color: Theme.accent }
                                                                Rectangle { width: 2; height: 7; y: 1.5; radius: 1; color: Theme.accent }
                                                            }

                                                            Text {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: MediaService.active ? MediaService.trackTitle : "Lofi Beats"
                                                                color: Theme.text
                                                                font.family: Theme.fontSans
                                                                font.pixelSize: 10
                                                                font.weight: Font.Medium
                                                                elide: Text.ElideRight
                                                                width: Math.min(implicitWidth, 72)
                                                            }

                                                            SvgIcon {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                sourceName: MediaService.isPlaying ? "pause" : "play"
                                                                iconSize: 9
                                                                color: Theme.textSub
                                                            }
                                                        }
                                                    }
                                                }

                                                // Scaled System Alert Split Pill
                                                Item {
                                                    height: 30
                                                    clip: true
                                                    width: LockService.showSystemAlerts ? (8 + previewAlertPill.width) : 0
                                                    opacity: LockService.showSystemAlerts ? 1.0 : 0.0
                                                    visible: width > 0.5 || opacity > 0.01

                                                    Behavior on width {
                                                        NumberAnimation {
                                                            duration: LockService.showSystemAlerts ? Theme.springMs : Theme.smoothMs
                                                            easing.type: LockService.showSystemAlerts ? Easing.OutBack : Easing.OutCubic
                                                            easing.overshoot: 0.75
                                                        }
                                                    }
                                                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                    Rectangle {
                                                        id: previewAlertPill
                                                        readonly property color alertTint: TelemetryService.overheatAlert ? Theme.dangerText : Theme.warn
                                                        x: LockService.showSystemAlerts ? 8 : 0
                                                        height: 30
                                                        width: previewAlertRow.implicitWidth + 18
                                                        radius: 15
                                                        color: Theme.pillBg
                                                        border.width: 1
                                                        border.color: Qt.rgba(alertTint.r, alertTint.g, alertTint.b, 0.45)
                                                        scale: LockService.showSystemAlerts ? 1.0 : 0.86
                                                        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                        Behavior on scale { NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }

                                                        Rectangle {
                                                            anchors.fill: parent
                                                            radius: 15
                                                            color: Qt.rgba(previewAlertPill.alertTint.r, previewAlertPill.alertTint.g, previewAlertPill.alertTint.b, 0.10)
                                                        }

                                                        Row {
                                                            id: previewAlertRow
                                                            anchors.centerIn: parent
                                                            spacing: 5
                                                            SvgIcon {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                sourceName: TelemetryService.overheatAlert ? "thermometer" : "battery-low"
                                                                iconSize: 11
                                                                color: previewAlertPill.alertTint
                                                            }
                                                            Text {
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: TelemetryService.overheatAlert
                                                                    ? (TelemetryService.cpuTempC + "℃")
                                                                    : (PowerService.lowBatteryAlert ? (PowerService.batteryPct + "%") : "12%")
                                                                color: previewAlertPill.alertTint
                                                                font.family: Theme.fontMono
                                                                font.pixelSize: 10
                                                                font.weight: Font.DemiBold
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Scaled Notification Card Preview
                                            Rectangle {
                                                id: previewNotifCard
                                                width: 224
                                                height: previewNotifCol.implicitHeight + 16
                                                radius: 12
                                                color: Theme.pillBg
                                                border.width: 1
                                                border.color: Theme.borderSubtle
                                                clip: true
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                readonly property real targetY: lockPreviewCanvas.isBottomPreview
                                                    ? (previewPillRow.y - height - 6)
                                                    : (previewPillRow.y + previewPillRow.height + 6)
                                                y: targetY + (LockService.showNotifications ? 0 : (lockPreviewCanvas.isBottomPreview ? 6 : -6))
                                                opacity: LockService.showNotifications ? 1.0 : 0.0
                                                scale: LockService.showNotifications ? 1.0 : 0.92
                                                visible: opacity > 0.01

                                                Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                                Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 0.85 } }

                                                ColumnLayout {
                                                    id: previewNotifCol
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.top: parent.top
                                                    anchors.margins: 8
                                                    spacing: 3

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 5
                                                        Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.danger }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            Layout.minimumWidth: 0
                                                            text: "Paithosh"
                                                            color: Theme.textSub
                                                            font.family: Theme.fontSans
                                                            font.pixelSize: 10
                                                            font.weight: Font.DemiBold
                                                            elide: Text.ElideRight
                                                        }
                                                        Text {
                                                            text: "now"
                                                            color: Theme.textMuted
                                                            font.family: Theme.fontMono
                                                            font.pixelSize: 9
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 0
                                                        text: LockService.hideNotifContent ? "New notification" : "Screenshot saved"
                                                        color: Theme.text
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 0
                                                        text: LockService.hideNotifContent ? "Content hidden on lock screen" : "~/Pictures/lock-preview.png"
                                                        color: LockService.hideNotifContent ? Theme.textMuted : Theme.textSub
                                                        font.family: LockService.hideNotifContent ? Theme.fontSans : Theme.fontMono
                                                        font.pixelSize: 10
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }

                                            // Subtle Audio Status Chip
                                            Rectangle {
                                                anchors.right: parent.right
                                                anchors.rightMargin: 10
                                                y: lockPreviewCanvas.isBottomPreview ? 10 : (parent.height - height - 10)
                                                height: 20
                                                width: previewAudioChipRow.implicitWidth + 14
                                                radius: 10
                                                color: Qt.rgba(Theme.pillBg.r, Theme.pillBg.g, Theme.pillBg.b, 0.85)
                                                border.width: 1
                                                border.color: SoundService.previewAmbientPlaying
                                                    ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                                                    : Theme.borderSubtle

                                                Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                                Row {
                                                    id: previewAudioChipRow
                                                    anchors.centerIn: parent
                                                    spacing: 5
                                                    SvgIcon {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        sourceName: (LockService.silentMode || LockService.ambientSound === "none") ? "volume-x" : "volume"
                                                        iconSize: 10
                                                        color: SoundService.previewAmbientPlaying ? Theme.accent : Theme.textSub
                                                    }
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: LockService.silentMode
                                                            ? "Silent Mode"
                                                            : (SoundService.previewAmbientPlaying ? ("Playing • " + lockScreenPage.soundLabel) : lockScreenPage.soundLabel)
                                                        color: SoundService.previewAmbientPlaying ? Theme.text : Theme.textSub
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 9
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // 1. Ambient Visual Effect Presets
                                SectionLabel { text: "Ambient visual effects" }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    columnSpacing: 10
                                    rowSpacing: 10

                                    PresetCard {
                                        title: "None"
                                        subtitle: "Clean wallpaper & floating pill only"
                                        iconName: "eye-off"
                                        searchKeywords: "none clean off lock screen effect"
                                        active: LockService.effectPreset === "none"
                                        onTriggered: { LockService.effectPreset = "none"; root.markAppearanceChanged(); }
                                    }
                                    PresetCard {
                                        title: "Snowfall"
                                        subtitle: "Soft layered snowflakes drifting gently"
                                        iconName: "snowflake"
                                        searchKeywords: "snow snowfall winter particles lock screen effect"
                                        active: LockService.effectPreset === "snow"
                                        onTriggered: { LockService.effectPreset = "snow"; root.markAppearanceChanged(); }
                                    }
                                    PresetCard {
                                        title: "Rain"
                                        subtitle: "Crisp angled rain over dimmed glass"
                                        iconName: "cloud-rain"
                                        searchKeywords: "rain rainfall weather particles lock screen effect"
                                        active: LockService.effectPreset === "rain"
                                        onTriggered: { LockService.effectPreset = "rain"; root.markAppearanceChanged(); }
                                    }
                                    PresetCard {
                                        title: "Wind Breeze"
                                        subtitle: "Subtle translucent air streams & motes"
                                        iconName: "wind"
                                        searchKeywords: "wind breeze air particles lock screen effect"
                                        active: LockService.effectPreset === "wind"
                                        onTriggered: { LockService.effectPreset = "wind"; root.markAppearanceChanged(); }
                                    }
                                }

                                // 2. Ambient Sound Presets
                                SectionLabel { text: "Ambient sound presets" }
                                GridLayout {
                                    Layout.fillWidth: true
                                    columns: 2
                                    columnSpacing: 10
                                    rowSpacing: 10
                                    opacity: LockService.silentMode ? 0.48 : 1.0
                                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                    PresetCard {
                                        title: "Silent"
                                        subtitle: "No background ambient sound"
                                        iconName: "volume-x"
                                        badge: LockService.silentMode ? "Muted" : ""
                                        searchKeywords: "silent none mute quiet lock screen audio"
                                        active: !LockService.silentMode && LockService.ambientSound === "none"
                                        onTriggered: {
                                            LockService.ambientSound = "none";
                                            SoundService.stopPreviewAmbient();
                                            root.markAppearanceChanged();
                                        }
                                    }
                                    PresetCard {
                                        title: "Gentle Wind"
                                        subtitle: "Soft, airy low-pass breeze"
                                        iconName: "wind"
                                        searchKeywords: "wind breeze ambient sound lock screen"
                                        active: !LockService.silentMode && LockService.ambientSound === "wind"
                                        onTriggered: {
                                            LockService.silentMode = false;
                                            LockService.ambientSound = "wind";
                                            SoundService.startPreviewAmbient("wind");
                                            root.markAppearanceChanged();
                                        }
                                    }
                                    PresetCard {
                                        title: "Soft Rain"
                                        subtitle: "Warm, distant rainfall ambience"
                                        iconName: "cloud-rain"
                                        searchKeywords: "rain rainfall ambient sound lock screen"
                                        active: !LockService.silentMode && LockService.ambientSound === "rain"
                                        onTriggered: {
                                            LockService.silentMode = false;
                                            LockService.ambientSound = "rain";
                                            SoundService.startPreviewAmbient("rain");
                                            root.markAppearanceChanged();
                                        }
                                    }
                                    PresetCard {
                                        title: "Winter Air"
                                        subtitle: "Quiet crystalline winter calm"
                                        iconName: "snowflake"
                                        searchKeywords: "snow winter ambient sound lock screen"
                                        active: !LockService.silentMode && LockService.ambientSound === "snow"
                                        onTriggered: {
                                            LockService.silentMode = false;
                                            LockService.ambientSound = "snow";
                                            SoundService.startPreviewAmbient("snow");
                                            root.markAppearanceChanged();
                                        }
                                    }
                                }

                                // 3. Sound & Quiet Mode
                                SectionLabel { text: "Audio & quiet mode" }
                                SettingGroup {
                                    SettingRow {
                                        showDivider: false
                                        iconName: "volume-x"
                                        title: "Silent Lock Screen"
                                        subtitle: "Mute all ambient loops, lock SFX, key clicks & notification chimes while locked"
                                        searchKeywords: "silent mute quiet lock screen audio sfx"
                                        CtrlSwitch {
                                            checked: LockService.silentMode
                                            onToggled: (v) => {
                                                LockService.silentMode = v;
                                                if (v) SoundService.stopPreviewAmbient();
                                                root.markAppearanceChanged();
                                            }
                                        }
                                    }
                                    SettingRow {
                                        iconName: "volume"
                                        title: "Lock & Unlock SFX"
                                        subtitle: "Tactile audio cues for lock, unlock, wrong password & typing"
                                        searchKeywords: "sfx sound chime click error password lock unlock"
                                        opacity: spotMatched ? (LockService.silentMode ? 0.48 : 1.0) : 0.28
                                        CtrlSwitch {
                                            checked: LockService.sfxEnabled
                                            onToggled: (v) => { LockService.sfxEnabled = v; root.markAppearanceChanged(); }
                                        }
                                    }
                                }

                                // 4. Lock Screen Widgets & Alerts
                                SectionLabel { text: "Lock screen widgets & alerts" }
                                SettingGroup {
                                    SettingRow {
                                        showDivider: false
                                        iconName: "bell"
                                        title: "Notifications"
                                        subtitle: "Show unread badge in lock pill and notification toast cards"
                                        searchKeywords: "notifications toast bell badge lock screen"
                                        CtrlSwitch {
                                            checked: LockService.showNotifications
                                            onToggled: (v) => { LockService.showNotifications = v; root.markAppearanceChanged(); }
                                        }
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: LockService.showNotifications ? hideContentRow.implicitHeight : 0
                                        opacity: LockService.showNotifications ? 1.0 : 0.0
                                        visible: Layout.preferredHeight > 1
                                        clip: true

                                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                        SettingRow {
                                            id: hideContentRow
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            iconName: "eye-off"
                                            title: "Hide Sensitive Content"
                                            subtitle: "Mask notification titles & message bodies until unlocked"
                                            searchKeywords: "hide sensitive content privacy notifications mask lock screen"
                                            CtrlSwitch {
                                                checked: LockService.hideNotifContent
                                                onToggled: (v) => { LockService.hideNotifContent = v; root.markAppearanceChanged(); }
                                            }
                                        }
                                    }
                                    SettingRow {
                                        iconName: "music"
                                        title: "Media Player"
                                        subtitle: "Show floating media split-pill with playback controls"
                                        searchKeywords: "media player music mpris controls lock screen"
                                        CtrlSwitch {
                                            checked: LockService.showMedia
                                            onToggled: (v) => { LockService.showMedia = v; root.markAppearanceChanged(); }
                                        }
                                    }
                                    SettingRow {
                                        iconName: "thermometer"
                                        title: "System Alerts"
                                        subtitle: "Show low battery (<= 15%), high temperature (>= 90℃) & charger status"
                                        searchKeywords: "system alerts low battery high temperature overheat thermal charger lock screen"
                                        CtrlSwitch {
                                            checked: LockService.showSystemAlerts
                                            onToggled: (v) => { LockService.showSystemAlerts = v; root.markAppearanceChanged(); }
                                        }
                                    }
                                }

                                // 5. Advanced Tuning (Collapsed by Default)
                                AdvancedSection {
                                    title: "Advanced Lock Screen Tuning"
                                    subtitle: "Particle intensity, ambient loudness & backdrop dimming"

                                    SettingRow {
                                        showDivider: false
                                        iconName: "snowflake"
                                        title: "Effect Intensity"
                                        subtitle: "Particle density and drift speed for Snow, Rain & Wind"
                                        searchKeywords: "intensity density speed snow rain wind"
                                        CtrlSlider {
                                            from: 50; to: 150; stepSize: 5; unit: "%"
                                            value: LockService.effectIntensity
                                            onMoved: (v) => { LockService.effectIntensity = Math.round(v); root.markAppearanceChanged(); }
                                        }
                                    }
                                    SettingRow {
                                        iconName: "volume"
                                        title: "Ambient Volume"
                                        subtitle: "Background ambient loudness relative to master UI sound"
                                        searchKeywords: "ambient volume loudness audio"
                                        CtrlSlider {
                                            from: 5; to: 100; stepSize: 5; unit: "%"
                                            value: LockService.ambientVolume
                                            onMoved: (v) => {
                                                LockService.ambientVolume = Math.round(v);
                                                SoundService.refreshPreviewAmbient();
                                                root.markAppearanceChanged();
                                            }
                                        }
                                    }
                                    SettingRow {
                                        iconName: "eye"
                                        title: "Backdrop Dimming"
                                        subtitle: "Scrim opacity behind the lock pill and ambient effects"
                                        searchKeywords: "dimming scrim brightness backdrop opacity"
                                        CtrlSlider {
                                            from: 15; to: 75; stepSize: 5; unit: "%"
                                            value: LockService.dimOpacity
                                            onMoved: (v) => { LockService.dimOpacity = Math.round(v); root.markAppearanceChanged(); }
                                        }
                                    }
                                }
                            }
                        }

                        // ==================== 17b. STORAGE ====================
                        Loader {
                            id: storagePageLoader
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "storage"
                            active: Boolean(root.loadedPages["storage"])
                            function ensureSource() {
                                if (active && source.toString() === "") setSource("StorageSettingsPage.qml", { shellState: root.shellState });
                            }
                            Component.onCompleted: ensureSource()
                            onActiveChanged: ensureSource()
                        }
                        Connections {
                            target: storagePageLoader.item
                            function onConfirmActionRequested(payload) {
                                storageConfirmOverlay.openWith(payload);
                            }
                        }

                        // ==================== 18. ABOUT ====================
                        Loader {
                            id: aboutPageLoader
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "about"
                            active: Boolean(root.loadedPages["about"])
                            function ensureSource() {
                                if (active && source.toString() === "") setSource("AboutSettingsPage.qml", { shellState: root.shellState });
                            }
                            Component.onCompleted: ensureSource()
                            onActiveChanged: ensureSource()
                        }
                    }
                }
            }
        }
    }

    // Hoisted Storage & Shredder Confirmation Modal (z: 215)
    Rectangle {
        id: storageConfirmOverlay
        property bool open: false
        property var payload: ({})
        property bool permanentDelete: false

        function openWith(data) {
            payload = data || ({});
            permanentDelete = false;
            open = true;
            confirmFocusScope.forceActiveFocus();
        }
        function close() {
            open = false;
            root.forceActiveFocus();
        }
        function execute() {
            const p = payload || ({});
            const perm = permanentDelete;
            open = false;
            if (p.kind === "user-cache") StorageService.cleanCache("user");
            else if (p.kind === "system-cache") StorageService.cleanCache("system");
            else if (p.kind === "shred-files") StorageService.shredFiles(p.paths || [], perm);
        }

        anchors.fill: parent
        z: 215
        color: Qt.rgba(0, 0, 0, 0.58)
        visible: open || opacity > 0.01
        opacity: open ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            enabled: storageConfirmOverlay.open
            onClicked: storageConfirmOverlay.close()
        }

        FocusScope {
            id: confirmFocusScope
            anchors.fill: parent
            focus: storageConfirmOverlay.open
            Keys.onEscapePressed: (event) => {
                if (storageConfirmOverlay.open) {
                    storageConfirmOverlay.close();
                    event.accepted = true;
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 440)
            implicitHeight: confirmCol.implicitHeight + 36
            radius: 14
            clip: true
            color: Theme.surfaceBg
            border.width: 1
            border.color: Theme.borderSubtle
            scale: storageConfirmOverlay.open ? 1.0 : 0.94
            Behavior on scale { NumberAnimation { duration: 190; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: confirmCol
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        width: 32; height: 32; radius: 8
                        color: Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.14)
                        SvgIcon {
                            anchors.centerIn: parent
                            sourceName: (storageConfirmOverlay.payload.needsRoot || storageConfirmOverlay.permanentDelete) ? "trash" : "info"
                            iconSize: 15
                            color: (storageConfirmOverlay.payload.needsRoot || storageConfirmOverlay.permanentDelete) ? Theme.dangerText : Theme.warn
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: storageConfirmOverlay.payload.title || "Confirm Cleanup"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "Reclaimable: " + StorageService.formatBytes(storageConfirmOverlay.payload.bytes || 0)
                                + (storageConfirmOverlay.payload.needsRoot ? " • Root authentication required" : "")
                            color: Theme.textSub
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: storageConfirmOverlay.payload.desc || ""
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: (storageConfirmOverlay.payload.preview || []).length > 0
                    implicitHeight: previewCol.implicitHeight + 16
                    radius: 9
                    clip: true
                    color: Theme.pillBg
                    border.width: 1
                    border.color: Theme.borderSubtle

                    ColumnLayout {
                        id: previewCol
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 4
                        Repeater {
                            model: storageConfirmOverlay.payload.preview || []
                            delegate: Text {
                                Layout.fillWidth: true
                                text: modelData
                                color: Theme.textMuted
                                font.family: Theme.fontMono
                                font.pixelSize: 10
                                elide: Text.ElideMiddle
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: !!storageConfirmOverlay.payload.allowPermanentToggle
                    spacing: 8

                    CtrlTickBox {
                        checked: storageConfirmOverlay.permanentDelete
                        onToggled: (v) => storageConfirmOverlay.permanentDelete = v
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Permanently delete (skip Trash — cannot be undone)"
                        color: storageConfirmOverlay.permanentDelete ? Theme.dangerText : Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: storageConfirmOverlay.permanentDelete = !storageConfirmOverlay.permanentDelete
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    CtrlBtn {
                        text: "Cancel"
                        ghost: true
                        onClicked: storageConfirmOverlay.close()
                    }
                    CtrlBtn {
                        text: storageConfirmOverlay.payload.needsRoot
                            ? "Continue (Root)"
                            : (storageConfirmOverlay.permanentDelete ? "Delete Permanently" : (storageConfirmOverlay.payload.kind === "shred-files" ? "Move to Trash" : "Clean Cache"))
                        danger: !!storageConfirmOverlay.payload.needsRoot || storageConfirmOverlay.permanentDelete
                        onClicked: storageConfirmOverlay.execute()
                    }
                }
            }
        }
    }

    // Shared Sudo Password Dialog (Btrfs / Storage / Package Elevation)
    Rectangle {
        id: sudoAuthOverlay
        readonly property bool activeOpen: BackupService.authPromptOpen || StorageService.authPromptOpen
        readonly property bool isBackupAuth: BackupService.authPromptOpen
        readonly property string errText: isBackupAuth ? BackupService.authPromptError : StorageService.authPromptError

        function cancelActive() {
            if (isBackupAuth) BackupService.cancelAuthPrompt();
            else StorageService.cancelAuthPrompt();
        }
        function submitActive() {
            const pwd = sudoPasswordField.text;
            sudoPasswordField.text = "";
            if (isBackupAuth) BackupService.submitAuthPassword(pwd);
            else StorageService.submitAuthPassword(pwd);
        }

        anchors.fill: parent
        z: 220
        color: Qt.rgba(0, 0, 0, 0.56)
        visible: activeOpen || opacity > 0.01
        opacity: activeOpen ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            enabled: sudoAuthOverlay.activeOpen
            onClicked: sudoAuthOverlay.cancelActive()
        }

        Connections {
            target: BackupService
            function onAuthPromptOpenChanged() {
                if (BackupService.authPromptOpen) {
                    sudoPasswordField.text = "";
                    sudoPasswordField.forceActiveFocus();
                }
            }
        }

        Connections {
            target: StorageService
            function onAuthPromptOpenChanged() {
                if (StorageService.authPromptOpen) {
                    sudoPasswordField.text = "";
                    sudoPasswordField.forceActiveFocus();
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 396)
            implicitHeight: sudoCol.implicitHeight + 36
            radius: 14
            clip: true
            color: Theme.surfaceRaised
            border.width: 1
            border.color: Theme.borderSubtle
            scale: sudoAuthOverlay.activeOpen ? 1.0 : 0.94
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: sudoCol
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    text: sudoAuthOverlay.isBackupAuth
                        ? BackupService.authPromptTitle
                        : StorageService.authPromptTitle
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: sudoAuthOverlay.isBackupAuth
                        ? BackupService.authPromptDesc
                        : StorageService.authPromptDesc
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 36
                    radius: 8
                    clip: true
                    color: Theme.pillBg
                    border.width: 1
                    border.color: sudoPasswordField.activeFocus ? Theme.accent : Theme.borderSubtle

                    AnimatedTextInput {
                        id: sudoPasswordField
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 13
                        Keys.onReturnPressed: sudoAuthOverlay.submitActive()
                        Keys.onEnterPressed: sudoAuthOverlay.submitActive()
                        Keys.onEscapePressed: sudoAuthOverlay.cancelActive()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: sudoAuthOverlay.errText !== ""
                    text: sudoAuthOverlay.errText
                    color: Theme.dangerText
                    font.family: Theme.fontSans
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    CtrlBtn {
                        text: "Cancel"
                        ghost: true
                        onClicked: sudoAuthOverlay.cancelActive()
                    }
                    CtrlBtn {
                        text: sudoAuthOverlay.isBackupAuth
                            ? BackupService.authPromptActionLabel
                            : StorageService.authPromptActionLabel
                        onClicked: sudoAuthOverlay.submitActive()
                    }
                }
            }
        }
    }

    // Backup Inspect / Verify / Rollback Confirmation Overlay
    Rectangle {
        id: inspectOverlay
        readonly property var d: BackupService.inspectData || ({})
        readonly property bool isPak: BackupService.inspectKind === "pak"
        readonly property bool isRollback: BackupService.inspectKind === "rollback"

        anchors.fill: parent
        z: 205
        color: Qt.rgba(0, 0, 0, 0.56)
        visible: BackupService.inspectModalOpen || opacity > 0.01
        opacity: BackupService.inspectModalOpen ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        MouseArea {
            anchors.fill: parent
            enabled: BackupService.inspectModalOpen
            onClicked: { if (!BackupService.inspectBusy && !BackupService.busy) BackupService.closeInspectModal(); }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 44, 520)
            implicitHeight: Math.min(parent.height - 44, inspectCol.implicitHeight + 36)
            radius: 14
            clip: true
            color: Theme.surfaceRaised
            border.width: 1
            border.color: Theme.borderSubtle
            scale: BackupService.inspectModalOpen ? 1.0 : 0.94
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: inspectCol
                anchors.fill: parent
                anchors.margins: 18
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: inspectOverlay.isPak
                                ? (".pak Backup Inspector")
                                : (inspectOverlay.isRollback ? "Confirm Btrfs System Rollback" : "Btrfs Snapshot Verification")
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: inspectOverlay.isPak ? (inspectOverlay.d.name || "") : (inspectOverlay.d.id || "")
                            color: Theme.textSub
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                    }
                    Rectangle {
                        visible: BackupService.inspectBusy
                        radius: 6
                        color: Theme.cardBg
                        implicitWidth: busyBadgeLbl.implicitWidth + 14
                        implicitHeight: 22
                        clip: true
                        Text {
                            id: busyBadgeLbl
                            anchors.centerIn: parent
                            text: "Checking..."
                            color: Theme.info
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.maximumHeight: 280
                    implicitHeight: Math.min(280, inspectBodyCol.implicitHeight)
                    contentWidth: width
                    contentHeight: inspectBodyCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: inspectBodyCol
                        width: parent.width
                        spacing: 8

                        // PAK Inspector Details
                        ColumnLayout {
                            visible: inspectOverlay.isPak
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: pakMetaCol.implicitHeight + 16
                                radius: 10
                                clip: true
                                color: Theme.cardBg
                                border.width: 1
                                border.color: Theme.borderSubtle

                                ColumnLayout {
                                    id: pakMetaCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Format: " + (inspectOverlay.d.isZip ? (inspectOverlay.d.extIsPak ? ".pak (Standard ZIP)" : "ZIP Archive") : "Not a ZIP file")
                                            + " • Store: " + (inspectOverlay.d.inStore ? "In Store" : "External File")
                                        color: Theme.text
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Entries: " + (inspectOverlay.d.entryCount || 0)
                                            + " • Size: " + BackupService.formatBytes(Number(inspectOverlay.d.sizeBytes || 0))
                                            + " (Uncompressed: " + BackupService.formatBytes(Number(inspectOverlay.d.uncompressedBytes || 0)) + ")"
                                        color: Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Folders: " + ((inspectOverlay.d.folders && inspectOverlay.d.folders.length > 0) ? inspectOverlay.d.folders.join(", ") : "None detected")
                                        color: Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "CRC-32: " + (inspectOverlay.d.crcOk === true ? "Verified OK ✓" : (inspectOverlay.d.crcOk === false ? ("FAILED (" + (inspectOverlay.d.badMember || "") + ")") : "Not run yet (click Verify)"))
                                            + " • Zip-Slip Check: " + ((inspectOverlay.d.unsafePaths && inspectOverlay.d.unsafePaths.length > 0) ? ("BLOCKED (" + inspectOverlay.d.unsafePaths.length + ")") : "Safe ✓")
                                        color: (inspectOverlay.d.crcOk === false || (inspectOverlay.d.unsafePaths && inspectOverlay.d.unsafePaths.length > 0)) ? Theme.dangerText : (inspectOverlay.d.crcOk === true ? Theme.ok : Theme.textSub)
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        visible: Boolean(inspectOverlay.d.sha256)
                                        Layout.fillWidth: true
                                        text: "SHA-256: " + (inspectOverlay.d.sha256 || "")
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        elide: Text.ElideMiddle
                                    }
                                    Text {
                                        visible: Number(inspectOverlay.d.skippedCount || 0) > 0
                                        Layout.fillWidth: true
                                        text: "Skipped special files (" + (inspectOverlay.d.skippedCount || 0) + "): " + ((inspectOverlay.d.skippedSample || []).slice(0, 4).join(", "))
                                        color: Theme.warn
                                        font.family: Theme.fontSans
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }

                        // System Snapshot Verification & Rollback Checklist
                        ColumnLayout {
                            visible: !inspectOverlay.isPak
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: sysCheckCol.implicitHeight + 16
                                radius: 10
                                clip: true
                                color: Theme.cardBg
                                border.width: 1
                                border.color: Theme.borderSubtle

                                ColumnLayout {
                                    id: sysCheckCol
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 5

                                    Repeater {
                                        model: inspectOverlay.d.checks || []
                                        delegate: RowLayout {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            spacing: 6
                                            SvgIcon {
                                                sourceName: modelData.status === "ok" ? "check" : (modelData.status === "warn" ? "alert-triangle" : "close")
                                                iconSize: 12
                                                color: modelData.status === "ok" ? Theme.ok : (modelData.status === "warn" ? Theme.warn : Theme.dangerText)
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: modelData.name + " — " + modelData.detail
                                                color: Theme.text
                                                font.family: Theme.fontSans
                                                font.pixelSize: 11
                                                wrapMode: Text.WordWrap
                                            }
                                        }
                                    }

                                    Text {
                                        visible: Boolean(inspectOverlay.d.btrfsUuid)
                                        Layout.fillWidth: true
                                        text: "Btrfs UUID: " + (inspectOverlay.d.btrfsUuid || "") + " • Subvol ID: " + (inspectOverlay.d.subvolId || 0)
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        elide: Text.ElideMiddle
                                    }
                                }
                            }

                            Rectangle {
                                visible: inspectOverlay.isRollback
                                Layout.fillWidth: true
                                implicitHeight: rbWarnLbl.implicitHeight + 14
                                radius: 10
                                clip: true
                                color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.12)
                                border.width: 1
                                border.color: Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.40)

                                Text {
                                    id: rbWarnLbl
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    text: "Safe Rollback Plan: subvol=home stays 100% untouched. Your active root is preserved at @paithosh-snapshots/pre-rollback-... and /boot default kernel syncs via grubby. Reboot activates the rollback."
                                    color: Theme.warn
                                    font.family: Theme.fontSans
                                    font.pixelSize: 11
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        Text {
                            visible: BackupService.inspectError !== ""
                            Layout.fillWidth: true
                            text: BackupService.inspectError
                            color: Theme.dangerText
                            font.family: Theme.fontSans
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // Footer Actions
                Flow {
                    Layout.fillWidth: true
                    spacing: 8

                    CtrlBtn {
                        text: "Close"
                        ghost: true
                        enabled: !BackupService.inspectBusy && !BackupService.busy
                        onClicked: BackupService.closeInspectModal()
                    }
                    CtrlBtn {
                        visible: inspectOverlay.isPak
                        text: "Verify CRC & SHA-256"
                        ghost: true
                        enabled: !BackupService.inspectBusy && !BackupService.busy && Boolean(inspectOverlay.d.path)
                        onClicked: BackupService.verifyPak(inspectOverlay.d.path)
                    }
                    CtrlBtn {
                        visible: inspectOverlay.isPak && !Boolean(inspectOverlay.d.inStore) && Boolean(inspectOverlay.d.isZip)
                        text: BackupService.importingPak ? "Importing..." : "Import to Store"
                        ghost: true
                        enabled: !BackupService.inspectBusy && !BackupService.busy
                        onClicked: BackupService.importPakToStore(inspectOverlay.d.path)
                    }
                    CtrlBtn {
                        visible: inspectOverlay.isPak && Boolean(inspectOverlay.d.isZip) && !(inspectOverlay.d.unsafePaths && inspectOverlay.d.unsafePaths.length > 0)
                        text: "Restore to ~/"
                        ghost: true
                        danger: true
                        enabled: !BackupService.inspectBusy && !BackupService.busy
                        onClicked: BackupService.restoreDataBackup(inspectOverlay.d.path, "direct", "")
                    }
                    CtrlBtn {
                        visible: inspectOverlay.isPak && Boolean(inspectOverlay.d.isZip) && !(inspectOverlay.d.unsafePaths && inspectOverlay.d.unsafePaths.length > 0)
                        text: BackupService.restoringData ? "Restoring..." : "Restore Safe Copy"
                        enabled: !BackupService.inspectBusy && !BackupService.busy
                        onClicked: BackupService.restoreDataBackup(inspectOverlay.d.path, "staged", "")
                    }
                    CtrlBtn {
                        visible: inspectOverlay.isRollback && Boolean(inspectOverlay.d.canRollback)
                        text: BackupService.rollingBack ? "Staging..." : "Confirm Stage Rollback"
                        danger: true
                        enabled: !BackupService.inspectBusy && !BackupService.busy
                        onClicked: BackupService.confirmRollbackSystemBackup(inspectOverlay.d.id)
                    }
                }
            }
        }
    }

    // Hyprland Default Config Sync Confirmation Dialog
    Rectangle {
        id: hyprConfirm
        readonly property bool isUpdate: root.pendingHyprMode === "update"
        property bool open: root.pendingHyprMode !== ""

        anchors.fill: parent
        z: 200
        color: Qt.rgba(0, 0, 0, 0.56)
        visible: open || opacity > 0.01
        opacity: open ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        focus: open
        Keys.onEscapePressed: root.pendingHyprMode = ""

        MouseArea {
            anchors.fill: parent
            enabled: hyprConfirm.open
            onClicked: root.pendingHyprMode = ""
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 44, 420)
            implicitHeight: hyprConfirmCol.implicitHeight + 40
            height: implicitHeight
            radius: 14
            clip: true
            color: Theme.surfaceBg
            border.width: 1
            border.color: Theme.borderSubtle
            scale: hyprConfirm.open ? 1.0 : 0.94
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: hyprConfirmCol
                anchors.fill: parent
                anchors.margins: 20
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: hyprConfirm.isUpdate ? "Update Hyprland config?" : "Replace Hyprland config?"
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: hyprConfirm.isUpdate
                        ? "Apply new defaults to ~/.config/hypr. Files you customized are preserved. A backup is created first."
                        : "This overwrites ~/.config/hypr with Paithosh defaults, including your custom changes. A backup is created first."
                    color: Theme.textSub
                    font.family: Theme.fontSans
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    CtrlBtn {
                        text: "Cancel"
                        ghost: true
                        onClicked: root.pendingHyprMode = ""
                    }
                    CtrlBtn {
                        text: hyprConfirm.isUpdate ? "Update" : "Replace"
                        danger: !hyprConfirm.isUpdate
                        onClicked: {
                            const m = root.pendingHyprMode;
                            root.pendingHyprMode = "";
                            PackageService.syncHyprConfig(m);
                        }
                    }
                }
            }
        }
    }

    Loader {
        id: keybindEditorLoader
        anchors.fill: parent
        z: 210
        active: false
        function openEditor(bindObj, comboIdx, defaultTab) {
            active = true;
            if (source.toString() === "") {
                setSource("KeybindEditorModal.qml", { selectMenu: settingsSelectMenu, menuRoot: root });
            }
            if (item) {
                if (bindObj) item.openEdit(bindObj, comboIdx);
                else item.openNew(defaultTab);
            }
        }
    }
}
