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

    // Display
    property string activeMonitorName: "eDP-1"
    property string displayScale: "100%"
    property string displayRes: "1920 × 1080"
    property string displayOrient: "Landscape"
    property bool rotationLock: true
    property var displayResOptions: ["1920 × 1080"]
    property var displayModeMap: ({})
    property int maxDisplayWidth: 1920
    property int maxDisplayHeight: 1080
    property string maxDisplayRes: "1920 × 1080"

    function isPresetActive(name) {
        return Theme.activePreset === name
            && !Theme.customAccentActive
            && (!root.shellState || root.shellState.activeProfile === "");
    }

    function selectThemePreset(name) {
        if (root.shellState) root.shellState.selectPreset(name);
        else Theme.applyPreset(name);
    }

    function markAppearanceChanged() {
        if (root.shellState) root.shellState.markAppearanceCustomized();
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
        if (!root.shellState) return;
        root.hideBarFullscreen = root.shellState.hideBarFullscreen;
        root.islandAutoHide = root.shellState.autoHideOnOverlap || root.shellState.hideBarFullscreen;
        root.islandCornerRadius = root.shellState.islandCornerRadius;
        root.barPosition = root.shellState.barPosition;
        root.topEdgeOffset = root.shellState.topEdgeOffset;
        root.activeBorderHighlight = root.shellState.activeBorderHighlight;
        root.globalSurfaceTheme = root.shellState.globalSurfaceTheme;
        if (root.shellState.activeProfile !== "") {
            root.profileNameInput = root.shellState.activeProfile;
        } else if (root.profileNameInput === "") {
            root.profileNameInput = "default";
        }
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

    Connections {
        target: CompositorService
        function onMonitorDetailsChanged() {
            root.syncDisplayFromCompositor();
        }
    }

    function syncDisplayFromCompositor() {
        const details = CompositorService.monitorDetails;
        if (!details || details.length === 0) return;
        let mon = details[0];
        for (let i = 0; i < details.length; ++i) {
            if (details[i].focused) { mon = details[i]; break; }
        }
        activeMonitorName = mon.name || "eDP-1";

        const opts = [];
        const modeMap = {};
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
            if (!modeMap[label]) {
                const hz = Math.round(parseFloat(m[3]));
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
            }
        }
        displayResOptions = opts;
        displayModeMap = modeMap;
        if (mon.width && mon.height) {
            const curLabel = mon.width + " × " + mon.height;
            if (opts.indexOf(curLabel) === -1) opts.unshift(curLabel);
            displayRes = curLabel;
        }
        const s = Number(mon.scale || 1);
        if (Math.abs(s - 1.0) < 0.05) displayScale = "100%";
        else if (Math.abs(s - 1.25) < 0.05) displayScale = "125% (Recommended)";
        else if (Math.abs(s - 1.5) < 0.05) displayScale = "150%";
        else if (Math.abs(s - 2.0) < 0.05) displayScale = "200%";
        else displayScale = Math.round(s * 100) + "%";

        const tr = Number(mon.transform || 0);
        displayOrient = (tr === 1 || tr === 3) ? "Portrait" : "Landscape";
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
        const parts = displayRes.split(" × ");
        const reqW = parseInt(parts[0], 10);
        const reqH = parseInt(parts[1], 10);
        if (maxDisplayWidth > 0 && maxDisplayHeight > 0 && (reqW > maxDisplayWidth || reqH > maxDisplayHeight)) {
            displayRes = maxDisplayRes;
        }
        const mode = displayModeMap[displayRes] || (displayRes.replace(" × ", "x") + "@60");
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

    // Themes
    property bool exportIncHypr: true
    property bool exportIncPalette: true
    property string themeExportStatus: ""
    property bool themeExportOk: true
    property string themeImportInput: ""
    property string profileNameInput: "default"

    readonly property var navItems: [
        { key: "home", label: "Home", icon: "⌂", group: "", sub: false },
        { key: "system", label: "System", icon: "⚙", group: "system", sub: false, hasChildren: true },
        { key: "display", label: "Display", icon: "", group: "system", sub: true },
        { key: "sound", label: "Sound & Audio", icon: "", group: "system", sub: true },
        { key: "power", label: "Power & Battery", icon: "", group: "system", sub: true },
        { key: "updates", label: "Updates", icon: "", group: "system", sub: true },
        { key: "backup", label: "Backup & Restore", icon: "", group: "system", sub: true },
        { key: "storage", label: "Storage", icon: "", group: "system", sub: true },
        { key: "accessibility", label: "Accessibility", icon: "", group: "system", sub: true },
        { key: "network", label: "Network & internet", icon: "◈", group: "network", sub: false, hasChildren: true },
        { key: "wifi", label: "Wi-Fi", icon: "", group: "network", sub: true },
        { key: "vpn", label: "VPN & Proxy", icon: "", group: "network", sub: true },
        { key: "personalization", label: "Personalization", icon: "✎", group: "personalization", sub: false, hasChildren: true },
        { key: "appearance", label: "Appearance", icon: "", group: "personalization", sub: true },
        { key: "keybind", label: "Binding", icon: "", group: "personalization", sub: true },
        { key: "layout", label: "Layout", icon: "", group: "personalization", sub: true },
        { key: "about", label: "About", icon: "ⓘ", group: "", sub: false }
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
            "fonts": "appearance",
            "decoration": "appearance",
            "animations": "appearance",
            "wallpaper": "appearance",
            "themes": "appearance",
            "hyprland": "layout",
            "layouts": "layout",
            "island": "layout",
            "binding": "keybind"
        };
        return legacyMap[pageKey] || pageKey || "home";
    }

    function openPage(pageKey) {
        const resolved = resolvePageKey(pageKey);
        if (currentPage === resolved) return;
        if (!root.loadedPages[resolved]) {
            const next = Object.assign({}, root.loadedPages);
            next[resolved] = true;
            root.loadedPages = next;
        }
        if (resolved === "updates") {
            if (!PackageService.shellCheckedOnce) PackageService.checkShellUpdate();
            PackageService.checkHyprSyncStatus();
        }
        if (resolved === "backup") BackupService.refreshAll();
        if (resolved === "storage") StorageService.scanIfStale();
        if (resolved === "about") TelemetryService.refreshSpecs();
        if (resolved === "keybind") KeybindService.refresh();
        else if (keybindEditorLoader.item && keybindEditorLoader.item.open) keybindEditorLoader.item.close();
        currentPage = resolved;
        if (root.shellState && root.shellState.settingsPage !== resolved) root.shellState.settingsPage = resolved;
        if (["display", "sound", "power", "updates", "backup", "storage", "accessibility"].indexOf(resolved) !== -1) systemOpen = true;
        if (["wifi", "vpn"].indexOf(resolved) !== -1) networkOpen = true;
        if (["appearance", "keybind", "layout"].indexOf(resolved) !== -1) personalizationOpen = true;
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
        if (item.hasChildren && item.group !== "") {
            for (let i = 0; i < navItems.length; ++i) {
                const child = navItems[i];
                if (child.sub && child.group === item.group) {
                    if (child.label.toLowerCase().indexOf(q.toLowerCase()) !== -1 || SettingsSearchService.pageHasMatch(child.key, q)) {
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
        Layout.fillWidth: true
        implicitHeight: groupCol.implicitHeight
        radius: 12
        color: Theme.cardBg
        border.width: 1
        border.color: Theme.borderSubtle
        clip: true

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
            : (active ? Theme.cardHover : (pMouse.containsMouse ? Theme.cardHover : Theme.cardBg))
        border.width: (active || (spotActive && spotMatched)) ? 2 : 1
        border.color: (active || (spotActive && spotMatched)) ? Theme.accent : (pMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
        scale: pMouse.pressed ? 0.98 : 1.0
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
                Text {
                    Layout.fillWidth: true
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
                    color: pCard.active ? Theme.accent : Theme.pillBg
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
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
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
        border.color: advMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40) : Theme.borderSubtle
        scale: advMouse.pressed ? 0.99 : 1.0
        clip: true
        Behavior on implicitHeight { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Rectangle {
            id: advHeader
            width: parent.width
            height: 50
            color: advMouse.containsMouse ? Theme.cardHover : "transparent"
            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10
                Text { text: "⚙"; color: advMouse.containsMouse ? Theme.text : Theme.textMuted; font.pixelSize: 14; Behavior on color { ColorAnimation { duration: 140 } } }
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
                    color: advMouse.containsMouse ? Theme.surfaceRaised : Theme.pillBg
                    border.width: 1
                    border.color: advMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Behavior on border.color { ColorAnimation { duration: 140 } }
                    Text {
                        id: advToggleLbl
                        anchors.centerIn: parent
                        text: advRoot.expanded ? "Hide ▴" : "Show ▾"
                        color: advMouse.containsMouse ? Theme.text : Theme.textSub
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
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
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
        property string iconChar: ""
        property string iconName: ""
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
                visible: sRow.iconName !== "" || sRow.iconChar !== ""
                width: 30; height: 30; radius: 8
                color: Theme.surfaceRaised
                border.width: 1; border.color: Theme.borderSubtle
                SvgIcon {
                    visible: sRow.iconName !== ""
                    anchors.centerIn: parent
                    sourceName: sRow.iconName
                    iconSize: 15
                    color: Theme.textSub
                }
                Text {
                    visible: sRow.iconName === "" && sRow.iconChar !== ""
                    anchors.centerIn: parent
                    text: sRow.iconChar
                    color: Theme.textSub
                    font.pixelSize: 13
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
        property string iconChar: ""
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
                Text { anchors.centerIn: parent; text: hCard.iconChar; color: Theme.text; font.pixelSize: 14 }
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

            Text {
                text: "›"
                color: hMouse.containsMouse ? Theme.text : Theme.textMuted
                font.pixelSize: 16
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
        color: checked ? Theme.accent : (swMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.14))
        border.width: 1
        border.color: checked ? Theme.accent : (swMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
        scale: swMouse.pressed ? 0.94 : 1.0
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

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
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
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

        Text {
            anchors.centerIn: parent
            visible: tb.checked
            text: "✓"
            color: Theme.accentFg
            font.pixelSize: 11
            font.weight: Font.Bold
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
                cursorShape: Qt.PointingHandCursor
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
                    color: Theme.accent
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
            cursorShape: Qt.PointingHandCursor
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
        color: selMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised
        border.width: 1
        border.color: Theme.borderSubtle

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
            Text { text: "▾"; color: Theme.textMuted; font.pixelSize: 11 }
        }

        MouseArea {
            id: selMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
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
                selectMenu.menuWidth = mw;
                selectMenu.openAt(pt.x, pt.y, opts);
            }
        }
    }

    ContextMenu {
        id: selectMenu
        z: 250
    }

    component CtrlBtn: Rectangle {
        id: cBtn
        property string text: ""
        property bool ghost: false
        property bool danger: false
        signal clicked()

        height: 30
        implicitWidth: btnLbl.implicitWidth + 22
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

        Text {
            id: btnLbl
            anchors.centerIn: parent
            text: cBtn.text
            color: cBtn.danger ? (cBtn.ghost ? Theme.dangerText : "#ffffff") : (cBtn.ghost ? Theme.text : Theme.accentFg)
            font.family: Theme.fontSans
            font.pixelSize: 12
            font.weight: Font.DemiBold
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
                        Text { text: "⌕"; font.pixelSize: 13; color: Theme.textMuted }
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
                        Text {
                            visible: searchInput.text.length > 0
                            text: "✕"
                            font.pixelSize: 11
                            color: clearSearchMouse.containsMouse ? Theme.text : Theme.textMuted
                            scale: clearSearchMouse.pressed ? 0.85 : 1.0
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
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
                                color: Theme.accent
                                opacity: navDelegate.isActive ? 1.0 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 160 } }
                                Behavior on anchors.leftMargin { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
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
                                Text {
                                    visible: modelData.hasChildren === true && root.searchQuery.trim() === ""
                                    text: "›"
                                    font.pixelSize: 14
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
                        NumberAnimation { target: pageCol; property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
                        NumberAnimation { target: pageCol; property: "y"; from: 10; to: 0; duration: 180; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        id: pageCol
                        width: parent.width
                        spacing: 12

                        // Page Heading
                        Text {
                            Layout.fillWidth: true
                            text: {
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

                        // ==================== 1. HOME ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "home"
                            active: Boolean(root.loadedPages["home"])
                            sourceComponent: ColumnLayout {
                            spacing: 12

                            Rectangle {
                                Layout.fillWidth: true; height: 68; radius: 12
                                color: Theme.cardBg; border.width: 1; border.color: Theme.borderSubtle
                                clip: true
                                RowLayout {
                                    anchors.fill: parent; anchors.margins: 14; spacing: 12
                                    Rectangle {
                                        width: 40; height: 40; radius: 10; color: Theme.surfaceRaised; border.width: 1; border.color: Theme.borderSubtle
                                        Text { anchors.centerIn: parent; text: "λ"; font.family: Theme.fontMono; font.pixelSize: 18; font.weight: Font.Bold; color: Theme.text }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                        Text {
                                            Layout.fillWidth: true
                                            text: TelemetryService.osName + " — " + TelemetryService.arch
                                            font.family: Theme.fontSans; font.pixelSize: 14; font.weight: Font.DemiBold
                                            color: Theme.text; elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: TelemetryService.hyprVersion
                                                + (TelemetryService.kernel !== "" ? " • Kernel " + TelemetryService.kernel : "")
                                                + (TelemetryService.shellName !== "" ? " • " + TelemetryService.shellName : "")
                                            font.family: Theme.fontSans; font.pixelSize: 11
                                            color: Theme.textSub; elide: Text.ElideRight
                                        }
                                    }
                                    Rectangle {
                                        implicitWidth: Math.max(78, uptimeLbl.implicitWidth + 18)
                                        height: 24; radius: 12; color: Theme.surfaceRaised; border.width: 1; border.color: Theme.borderSubtle
                                        clip: true
                                        Text {
                                            id: uptimeLbl
                                            anchors.centerIn: parent
                                            text: TelemetryService.uptimeText
                                            font.family: Theme.fontMono; font.pixelSize: 10; color: Theme.textSub
                                        }
                                    }
                                }
                            }

                            SectionLabel { text: "System specifications" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 2; columnSpacing: 10; rowSpacing: 10
                                Repeater {
                                    model: [
                                        {
                                            title: "PROCESSOR",
                                            main: TelemetryService.cpuModel,
                                            sub: (TelemetryService.cpuCores !== "" ? TelemetryService.cpuCores + " • " : "")
                                                + "Load " + TelemetryService.cpuPct + "% • " + TelemetryService.cpuTempC + "°C"
                                        },
                                        {
                                            title: "MEMORY",
                                            main: TelemetryService.ramTotalGb,
                                            sub: TelemetryService.memDetail + " (" + TelemetryService.ramPct + "%) • " + TelemetryService.swapSummary
                                        },
                                        {
                                            title: "GRAPHICS",
                                            main: TelemetryService.gpuName,
                                            sub: root.focusedMonitorSummary()
                                        },
                                        {
                                            title: "STORAGE",
                                            main: TelemetryService.storageTotal,
                                            sub: TelemetryService.storageDetail !== "" ? TelemetryService.storageDetail : "Root filesystem (/)"
                                        }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true; height: 68; radius: 10
                                        color: Theme.cardBg; border.width: 1; border.color: Theme.borderSubtle
                                        clip: true
                                        ColumnLayout {
                                            anchors.fill: parent; anchors.margins: 12; spacing: 2
                                            Text { text: modelData.title; font.family: Theme.fontSans; font.pixelSize: 9; font.weight: Font.DemiBold; color: Theme.textMuted }
                                            Text { Layout.fillWidth: true; text: modelData.main; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; text: modelData.sub; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
                                        }
                                    }
                                }
                            }

                            SectionLabel { text: "Quick Settings & Theme" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 3; columnSpacing: 8; rowSpacing: 8
                                Repeater {
                                    model: Theme.presetCatalog
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool active: root.isPresetActive(modelData.name)
                                        Layout.fillWidth: true; height: 74; radius: 10
                                        color: (themeMouse.containsMouse || active) ? Theme.cardHover : Theme.cardBg
                                        border.width: active ? 2 : 1
                                        border.color: active ? Theme.accent : (themeMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
                                        scale: themeMouse.pressed ? 0.97 : 1.0
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
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.selectThemePreset(modelData.name);
                                            }
                                        }
                                    }
                                }
                            }

                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconChar: AudioService.muted ? "🔇" : "🔊"
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
                                    iconChar: "☀"
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
                                    Layout.fillWidth: true; height: 56; radius: 10
                                    color: wifiTileMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                                    border.width: 1
                                    border.color: NetworkService.wifiEnabled ? Theme.accent : (wifiTileMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
                                    scale: wifiTileMouse.pressed ? 0.98 : 1.0
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 12; spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                            Text { Layout.fillWidth: true; text: "Wi-Fi"; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; text: NetworkService.wifiEnabled ? (NetworkService.activeSsid !== "" ? NetworkService.activeSsid : "On • Disconnected") : "Disabled"; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
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
                                    Layout.fillWidth: true; height: 56; radius: 10
                                    color: dndTileMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                                    border.width: 1
                                    border.color: NotificationService.dnd ? Theme.accent : (dndTileMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
                                    scale: dndTileMouse.pressed ? 0.98 : 1.0
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 12; spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                            Text { Layout.fillWidth: true; text: "Do Not Disturb"; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; text: NotificationService.dnd ? "Popups silenced" : (NotificationService.unreadCount + " unread notifications"); font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
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
                                    Layout.fillWidth: true; height: 56; radius: 10
                                    color: pwrTileMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                                    border.width: 1; border.color: pwrTileMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle
                                    scale: pwrTileMouse.pressed ? 0.98 : 1.0
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 12; spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                            Text { Layout.fillWidth: true; text: "Power Profile"; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                                            Text { Layout.fillWidth: true; text: root.formatPowerProfile(PowerService.powerProfile) + " • Battery " + PowerService.batteryPct + "%"; font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight }
                                        }
                                        Rectangle {
                                            implicitWidth: pwrPill.implicitWidth + 16; height: 24; radius: 12
                                            color: Theme.surfaceRaised; border.width: 1; border.color: pwrTileMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                                            Behavior on border.color { ColorAnimation { duration: 140 } }
                                            Text { id: pwrPill; anchors.centerIn: parent; text: "Cycle"; font.family: Theme.fontSans; font.pixelSize: 11; color: pwrTileMouse.containsMouse ? Theme.text : Theme.textSub; Behavior on color { ColorAnimation { duration: 140 } } }
                                        }
                                    }
                                    MouseArea {
                                        id: pwrTileMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.cyclePowerProfile()
                                    }
                                }

                                // System Updates Quick Card
                                Rectangle {
                                    Layout.fillWidth: true; height: 56; radius: 10
                                    color: updTileMouse.containsMouse ? Theme.cardHover : Theme.cardBg
                                    border.width: 1
                                    border.color: PackageService.updateCount > 0 ? Theme.accent : (updTileMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Theme.borderSubtle)
                                    scale: updTileMouse.pressed ? 0.98 : 1.0
                                    clip: true
                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                    RowLayout {
                                        anchors.fill: parent; anchors.margins: 12; spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 2
                                            Text { Layout.fillWidth: true; text: "System Updates"; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; elide: Text.ElideRight }
                                            Text {
                                                Layout.fillWidth: true
                                                text: PackageService.checking
                                                    ? "Checking repositories..."
                                                    : (PackageService.updateCount > 0 ? PackageService.updateCount + " updates ready" : "All packages up to date")
                                                font.family: Theme.fontSans; font.pixelSize: 11; color: Theme.textSub; elide: Text.ElideRight
                                            }
                                        }
                                        Rectangle {
                                            implicitWidth: updPill.implicitWidth + 16; height: 24; radius: 12
                                            color: Theme.surfaceRaised; border.width: 1; border.color: updTileMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.borderSubtle
                                            Behavior on border.color { ColorAnimation { duration: 140 } }
                                            Text { id: updPill; anchors.centerIn: parent; text: "Open"; font.family: Theme.fontSans; font.pixelSize: 11; color: updTileMouse.containsMouse ? Theme.text : Theme.textSub; Behavior on color { ColorAnimation { duration: 140 } } }
                                        }
                                    }
                                    MouseArea {
                                        id: updTileMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openPage("updates")
                                    }
                                }
                            }

                            SectionLabel { text: "Most used pages" }
                            Flow {
                                Layout.fillWidth: true; spacing: 8
                                CtrlBtn { text: "Display"; ghost: true; onClicked: root.openPage("display") }
                                CtrlBtn { text: "Sound & Audio"; ghost: true; onClicked: root.openPage("sound") }
                                CtrlBtn { text: "Appearance"; ghost: true; onClicked: root.openPage("appearance") }
                                CtrlBtn { text: "Binding"; ghost: true; onClicked: root.openPage("keybind") }
                                CtrlBtn { text: "Layout"; ghost: true; onClicked: root.openPage("layout") }
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
                            HubCard { iconChar: "▭"; title: "Display"; subtitle: "Resolution, scaling & orientation"; pillText: root.displayRes + " • " + root.displayScale.replace(" (Recommended)", ""); onTriggered: root.openPage("display") }
                            HubCard { iconChar: "♪"; title: "Sound & Audio"; subtitle: "PipeWire sinks, input & balance"; pillText: AudioService.muted ? "Muted" : (AudioService.volumePct + "%"); onTriggered: root.openPage("sound") }
                            HubCard { iconChar: "⚡"; title: "Power & Battery"; subtitle: "Profiles, sleep & AC behavior"; pillText: root.formatPowerProfile(PowerService.powerProfile); onTriggered: root.openPage("power") }
                            HubCard {
                                iconChar: "↻"
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
                                iconChar: "⛁"
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
                                iconChar: "⛁"
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
                                iconChar: "♿"; title: "Accessibility"; subtitle: "Screen recording presets, resolution, fps & audio"
                                pillText: ScreenRecordService.preset === "low" ? "Low Storage" : (ScreenRecordService.preset === "high" ? "High Quality" : (ScreenRecordService.preset === "custom" ? "Custom" : "Standard"))
                                onTriggered: root.openPage("accessibility")
                            }

                            SectionLabel { text: "Nearby settings" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "◐"; title: "Night Light"; subtitle: "Shift display to warmer colors after sunset"
                                    CtrlSwitch { checked: root.nightLight; onToggled: (v) => root.nightLight = v }
                                }
                                SettingRow {
                                    iconChar: "🔊"; title: "Master Volume"; subtitle: "Quick output level for default PipeWire sink"
                                    CtrlSlider { from: 0; to: 100; value: AudioService.volumePct; unit: "%"; onMoved: (v) => AudioService.setVolume(v, false) }
                                }
                                SettingRow {
                                    iconChar: "⚡"; title: "Power mode"; subtitle: "Tune CPU governor and thermal profile"
                                    CtrlSelect { options: ["Power Saver", "Balanced", "Performance"]; currentText: root.formatPowerProfile(PowerService.powerProfile); onSelected: (v) => PowerService.setPowerProfile(root.powerProfileKey(v)) }
                                }
                                SettingRow {
                                    iconChar: "🔕"; title: "Do Not Disturb"; subtitle: "Silence popups on the Dynamic Island status bar"
                                    CtrlSwitch { checked: NotificationService.dnd; onToggled: (v) => NotificationService.dnd = v }
                                }
                                SettingRow {
                                    iconChar: "↻"; title: "Reload Shell"; subtitle: "Restart Quickshell (pkill qs) and reload Hyprland config"
                                    searchKeywords: "reload shell restart quickshell qs hyprctl"
                                    CtrlBtn {
                                        text: "Reload"
                                        ghost: true
                                        onClicked: Quickshell.execDetached([
                                            "setsid", "-f", "sh", "-c",
                                            "shell_dir=\"$1\"; " +
                                            "pkill -x qs 2>/dev/null || true; " +
                                            "pkill -x quickshell 2>/dev/null || true; " +
                                            "i=0; while [ $i -lt 30 ] && (pgrep -x qs >/dev/null 2>&1 || pgrep -x quickshell >/dev/null 2>&1); do " +
                                            "  sleep 0.1; i=$((i + 1)); " +
                                            "done; " +
                                            "pkill -9 -x qs 2>/dev/null || true; " +
                                            "pkill -9 -x quickshell 2>/dev/null || true; " +
                                            "hyprctl reload >/dev/null 2>&1 || true; " +
                                            "if command -v qs >/dev/null 2>&1; then " +
                                            "  exec qs -d -p \"$shell_dir\" </dev/null >/dev/null 2>&1; " +
                                            "else " +
                                            "  exec quickshell -d -p \"$shell_dir\" </dev/null >/dev/null 2>&1; " +
                                            "fi",
                                            "_",
                                            Quickshell.shellDir
                                        ])
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
                            property bool advancedOpen: false

                            readonly property string activeRecPreset: root.shellState ? root.shellState.recordPreset : ScreenRecordService.preset
                            readonly property string activeRecRes: root.shellState ? root.shellState.recordResolution : ScreenRecordService.resolution
                            readonly property int activeRecFps: root.shellState ? root.shellState.recordFps : ScreenRecordService.fps
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

                                            // Wallpaper scaled to preview resolution so sharpness difference is visible
                                            Image {
                                                anchors.fill: parent
                                                source: (typeof bgLayer !== "undefined" && bgLayer.currentWallpaperPath) ? ("file://" + bgLayer.currentWallpaperPath) : ""
                                                fillMode: Image.PreserveAspectCrop
                                                smooth: accessibilityPage.activeRecRes !== "480p"
                                                sourceSize.width: accessibilityPage.activeRecRes === "480p" ? 160 : (accessibilityPage.activeRecRes === "720p" ? 360 : 960)
                                                opacity: status === Image.Ready ? 0.55 : 0.0
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
                                                anchors.margins: 10; height: 24; radius: 6
                                                color: Qt.rgba(0, 0, 0, 0.55)
                                                Row {
                                                    anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10; spacing: 8
                                                    Text {
                                                        text: "H.264 • " + (accessibilityPage.activeRecPreset === "low" ? "CRF 32" : (accessibilityPage.activeRecPreset === "high" ? "CRF 20" : "CRF 26"))
                                                            + " • Audio: " + ((ScreenRecordService.recordAudio && ScreenRecordService.recordMic) ? "Output + Mic" : (ScreenRecordService.recordAudio ? "Output" : (ScreenRecordService.recordMic ? "Mic" : "Off")))
                                                        color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 10
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
                                            if (modelData.key === "custom") accessibilityPage.advancedOpen = true;
                                        }
                                    }
                                }
                            }

                            // 3. Audio & Storage
                            SectionLabel { text: "General" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconChar: "🔊"; title: "Record with Audio"; subtitle: "Include audio when recording screen"
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
                                    iconChar: "📁"; title: "Save Location (>20MB)"; subtitle: (root.shellState && root.shellState.recordSaveDir !== "") ? root.shellState.recordSaveDir : (ScreenRecordService.saveDir !== "" ? ScreenRecordService.saveDir : "~/Videos (default)")
                                    PillButton {
                                        text: "Browse..."
                                        onClicked: if (root.shellState) root.shellState.openScreenRecordDirPicker()
                                    }
                                }
                            }

                            // 4. Advanced Settings (collapsible card matching Personalization)
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconChar: "⚙"; title: "Advanced Settings"; subtitle: "Resolution, frame rate, output & microphone audio"
                                    PillButton {
                                        text: accessibilityPage.advancedOpen ? "Hide ▲" : "Show ▼"
                                        onClicked: accessibilityPage.advancedOpen = !accessibilityPage.advancedOpen
                                    }
                                }
                                SettingRow {
                                    visible: accessibilityPage.advancedOpen
                                    iconChar: "▭"; title: "Resolution"; subtitle: "Output video scale (Native = monitor resolution)"
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
                                    visible: accessibilityPage.advancedOpen
                                    iconChar: "⏱"; title: "Frame Rate (FPS)"; subtitle: "Lower FPS reduces CPU usage and file size"
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
                                    visible: accessibilityPage.advancedOpen
                                    iconChar: "🔊"; title: "Output Audio (System)"; subtitle: "Capture desktop sound from default speaker monitor"
                                    CtrlSwitch {
                                        checked: root.shellState ? root.shellState.recordAudio : ScreenRecordService.recordAudio
                                        onToggled: (v) => {
                                            ScreenRecordService.recordAudio = v;
                                            if (root.shellState) root.shellState.recordAudio = v;
                                        }
                                    }
                                }
                                SettingRow {
                                    visible: accessibilityPage.advancedOpen
                                    iconChar: "🎙"; title: "Input Audio (Microphone)"; subtitle: "Capture default microphone (mixed if Output is also on)"
                                    CtrlSwitch {
                                        checked: root.shellState ? root.shellState.recordMic : ScreenRecordService.recordMic
                                        onToggled: (v) => {
                                            ScreenRecordService.recordMic = v;
                                            if (root.shellState) root.shellState.recordMic = v;
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
                                                text: root.displayRes + " • " + root.displayScale.replace(" (Recommended)", "") + " • " + root.displayOrient
                                                color: Theme.text
                                                font.family: Theme.fontMono
                                                font.pixelSize: 10
                                                font.weight: Font.Medium
                                            }
                                        }
                                    }

                                    // Monitor frame centered in preview
                                    Item {
                                        anchors.fill: parent
                                        anchors.margins: 14
                                        anchors.topMargin: 28

                                        readonly property bool isPortrait: root.displayOrient === "Portrait"
                                        readonly property real scaleFactor: {
                                            const s = parseFloat(root.displayScale);
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

                                            // Live Wallpaper
                                            Image {
                                                anchors.fill: parent
                                                source: (typeof bgLayer !== "undefined" && bgLayer.wallpapers && bgLayer.wallpapers.length > 0)
                                                    ? bgLayer.wallpapers[Math.max(0, Math.min(bgLayer.currentIndex, bgLayer.wallpapers.length - 1))]
                                                    : ""
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                smooth: true
                                                visible: status === Image.Ready
                                            }

                                            // Subtle vignette for contrast
                                            Rectangle {
                                                anchors.fill: parent
                                                color: Qt.rgba(0, 0, 0, 0.22)
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

                            SectionLabel { text: "Scale & layout" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "⤢"; title: "Scale"; subtitle: "Change the size of text, apps, and other items"
                                    CtrlSelect { options: ["100%", "125% (Recommended)", "150%", "200%"]; currentText: root.displayScale; onSelected: (v) => { root.displayScale = v; root.applyDisplayChange(); } }
                                }
                                SettingRow {
                                    iconChar: "▭"; title: "Display resolution"; subtitle: "Adjust the resolution to fit your connected display (Max: " + root.maxDisplayRes + ")"
                                    CtrlSelect { options: root.displayResOptions; currentText: root.displayRes; onSelected: (v) => { root.displayRes = v; root.applyDisplayChange(); } }
                                }
                                SettingRow {
                                    iconChar: "↻"; title: "Display orientation"; subtitle: "Rotate screen layout for Wayland output"
                                    CtrlSelect { options: ["Landscape", "Portrait"]; currentText: root.displayOrient; onSelected: (v) => { root.displayOrient = v; root.applyDisplayChange(); } }
                                }
                                SettingRow {
                                    iconChar: "🔒"; title: "Rotation lock"; subtitle: "Prevent automatic orientation changes"
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
                                    iconChar: AudioService.muted ? "🔇" : "🔊"
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
                                    iconChar: "♪"
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

                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconChar: "🎧"
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
                                        iconChar: isDefault ? "●" : "○"
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
                                    iconChar: "—"
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
                                    iconChar: AudioService.inputMuted ? "🎙" : "🎤"
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
                                    iconChar: "🎚"
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
                                    iconChar: "🎙"
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
                                        iconChar: isDefault ? "●" : "○"
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
                                    iconChar: "—"
                                    title: "No input devices found"
                                    subtitle: "Connect a microphone"
                                }
                            }
                        }
                        }

                        // ==================== 5. POWER ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "power"
                            active: Boolean(root.loadedPages["power"])
                            sourceComponent: ColumnLayout {
                            spacing: 10
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "⚡"; title: "Power profile"; subtitle: root.formatPowerProfile(PowerService.powerProfile) + " • Battery " + PowerService.batteryPct + "% (" + PowerService.timeRemaining + ")"
                                    CtrlSelect { options: ["Power Saver", "Balanced", "Performance"]; currentText: root.formatPowerProfile(PowerService.powerProfile); onSelected: (v) => PowerService.setPowerProfile(root.powerProfileKey(v)) }
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
                                    showDivider: PackageService.shellUpdateBehind > 0 && PackageService.shellCommits.length > 0
                                    iconChar: "⚡"
                                    title: PackageService.shellBranch !== ""
                                        ? ("Paithosh Shell  •  " + PackageService.shellBranch + (PackageService.shellCommit !== "" ? "@" + PackageService.shellCommit : ""))
                                        : "Paithosh Shell"
                                    subtitle: {
                                        if (PackageService.shellChecking) return "Checking git repository for shell updates...";
                                        if (PackageService.shellUpdating) return "Pulling latest changes and reloading shell...";
                                        if (PackageService.shellUpdateError !== "") return PackageService.shellUpdateError;
                                        if (PackageService.shellUpdateBehind > 0) {
                                            return PackageService.shellUpdateBehind + (PackageService.shellUpdateBehind === 1 ? " new commit available" : " new commits available")
                                                + (PackageService.shellLatestSummary !== "" ? " — " + PackageService.shellLatestSummary : "");
                                        }
                                        if (PackageService.shellCheckedOnce) return "Shell is up to date with your repository";
                                        return "Update Paithosh Shell directly from your git repository";
                                    }
                                    searchKeywords: "paithosh shell git repo pull self update reload"
                                    RowLayout {
                                        spacing: 8
                                        CtrlBtn {
                                            text: PackageService.shellChecking ? "Checking..." : "Check"
                                            ghost: true
                                            enabled: !PackageService.shellChecking && !PackageService.shellUpdating
                                            onClicked: PackageService.checkShellUpdate()
                                        }
                                        CtrlBtn {
                                            text: PackageService.shellUpdating
                                                ? "Updating..."
                                                : (PackageService.shellUpdateBehind > 0 ? ("Update (" + PackageService.shellUpdateBehind + ")") : "Update")
                                            enabled: !PackageService.shellChecking && !PackageService.shellUpdating && PackageService.shellUpdateBehind > 0
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
                                    visible: PackageService.shellUpdateBehind > 0 && PackageService.shellCommits.length > 0
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
                            }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconChar: "↻"
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
                                    iconChar: "🛡"
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
                                    iconChar: "🕒"
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
                                    iconChar: "🧪"
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
                                    iconChar: "🧹"
                                    title: PackageService.cacheSizeText !== "" ? ("Package Cache  •  " + PackageService.cacheSizeText) : "Package Cache"
                                    subtitle: {
                                        if (PackageService.cleaningCache) return "Cleaning package manager cache... " + PackageService.cleanCacheProgress + "%";
                                        if (PackageService.isArch) return "Remove old & uninstalled packages from pacman cache (pacman -Sc)";
                                        if (PackageService.isFedora) return "Remove cached repository metadata and packages (dnf clean all)";
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
                                    iconChar: "✓"
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
                                    iconChar: "⛁"
                                    title: BackupService.isBtrfsRoot
                                        ? ("Btrfs Root: subvol=" + (BackupService.btrfsInfo.rootSubvol || "root") + " (" + (BackupService.btrfsInfo.rootDevice || "/") + ")")
                                        : ("Root Filesystem: " + (BackupService.btrfsInfo.rootFstype || "unknown"))
                                    subtitle: (BackupService.btrfsInfo.homeSeparateSubvol ? "/home on separate subvolume (safe)" : "/home shared with /")
                                        + (BackupService.btrfsInfo.bootSeparate ? (" • /boot " + (BackupService.btrfsInfo.bootFstype || "") + " (" + (BackupService.btrfsInfo.kernelRunning || "") + (BackupService.btrfsInfo.vmlinuzExists ? " ✓" : " ⚠") + ")") : "")
                                    searchKeywords: "btrfs subvolume root home boot kernel transparency"
                                    CtrlBtn {
                                        text: "Refresh"
                                        ghost: true
                                        enabled: !BackupService.busy
                                        onClicked: BackupService.refreshAll()
                                    }
                                }
                                SettingRow {
                                    iconChar: "🛡"
                                    title: BackupService.btrfsInfo.polkitAgentActive ? "Privilege Mode: Polkit Agent" : "Privilege Mode: Secure Sudo Prompt (stdin)"
                                    subtitle: "Free disk space: " + BackupService.formatBytes(Number(BackupService.btrfsInfo.diskAvailBytes || 0))
                                        + " (" + (BackupService.btrfsInfo.diskUsedPct || 0) + "% used)"
                                        + ((BackupService.btrfsInfo.diskUsedPct || 0) >= 85 ? " • ⚠ Low disk space" : "")
                                        + (BackupService.systemBackups.length > 10 ? (" • " + BackupService.systemBackups.length + " snapshots stored") : "")
                                    searchKeywords: "polkit sudo disk space elevation"
                                }
                            }

                            SectionLabel { text: "System Backup (Btrfs Snapshot & Rollback)" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false
                                    iconChar: "🛡"
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
                                    iconChar: "↻"
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
                                    iconChar: "⛁"
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
                                            Text {
                                                text: modelData.status === "ok" ? "✓" : (modelData.status === "warn" ? "!" : (modelData.status === "fail" ? "✗" : "•"))
                                                color: modelData.status === "ok" ? Theme.ok : (modelData.status === "warn" ? Theme.warn : (modelData.status === "fail" ? Theme.dangerText : Theme.info))
                                                font.family: Theme.fontMono
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
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
                                    iconChar: "⛁"
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
                                    iconChar: "📁"
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
                                    iconChar: "⚡"
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
                                        iconChar: modelData.hasBtrfsSnap ? "🛡" : "⛁"
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
                                    iconChar: "—"
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
                                        iconChar: "⛁"
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
                                    iconChar: "—"
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
                            HubCard { iconChar: "◈"; title: "Wi-Fi"; subtitle: "Wireless networks, SSID & signal"; pillText: NetworkService.wifiEnabled ? NetworkService.activeSsid : "Off"; onTriggered: { root.openPage("wifi"); NetworkService.refreshNetworks(true); } }
                            HubCard { iconChar: "🛡"; title: "VPN & Proxy"; subtitle: "WireGuard tunnels & HTTP proxy"; pillText: VpnProxyService.vpnActive ? ("WireGuard • " + VpnProxyService.activeTunnel) : "WireGuard • Standby"; onTriggered: root.openPage("vpn") }
                            HubCard { iconChar: "◉"; title: "DNS & Routing"; subtitle: "Encrypted DoH & split-horizon"; pillText: "1.1.1.1 • DoH Active"; onTriggered: {} }
                            HubCard { iconChar: "📱"; title: "KDE Connect & Share"; subtitle: "Local LAN pairing & file drop"; pillText: "Pixel 8 Pro • Paired"; onTriggered: {} }

                            SectionLabel { text: "Nearby settings" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "◈"; title: "Wi-Fi Radio (wlan0)"; subtitle: "Connected to Paithon_5G • 5 GHz WPA3"
                                    CtrlSwitch { checked: NetworkService.wifiEnabled; onToggled: (v) => NetworkService.setWifiEnabled(v) }
                                }
                                SettingRow {
                                    iconChar: "✈"; title: "Airplane mode"; subtitle: "Stop all wireless communication"
                                    CtrlSwitch { checked: root.airplaneMode; onToggled: (v) => root.airplaneMode = v }
                                }
                                SettingRow {
                                    iconChar: "◉"; title: "DNS Provider"; subtitle: "Resolver used for all system queries"
                                    CtrlSelect { options: ["Cloudflare (1.1.1.1)", "Quad9 (9.9.9.9)", "System Auto (DHCP)"]; currentText: root.dnsProvider; onSelected: (v) => root.dnsProvider = v }
                                }
                                SettingRow {
                                    iconChar: "◔"; title: "Metered connection"; subtitle: "Pause automatic background package sync"
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
                                    showDivider: false; iconChar: "◈"
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
                                        iconChar: modelData.inUse ? "●" : "○"
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
                                    iconChar: "+"; title: "Hidden network"; subtitle: "Enter SSID manually"
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
                                    iconChar: "🛡"
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
                                            text: "↻"
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
                                        iconChar: modelData.active ? "●" : "○"
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
                                    iconChar: "⇄"
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
                                                text: Theme.activePreset + " • Rounding " + CompositorService.cornerRounding + "px • Gaps " + CompositorService.gapsIn + "/" + CompositorService.gapsOut + "px • " + (CompositorService.blurEnabled ? ("Blur " + CompositorService.blurSize + "px") : "Blur Off")
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

                                        // Real active wallpaper from bgLayer
                                        Image {
                                            anchors.fill: parent
                                            source: (typeof bgLayer !== "undefined" && bgLayer.wallpapers && bgLayer.wallpapers.length > 0)
                                                ? bgLayer.wallpapers[Math.max(0, Math.min(bgLayer.currentIndex, bgLayer.wallpapers.length - 1))]
                                                : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            smooth: true
                                            visible: status === Image.Ready
                                        }

                                        // Subtle vignette for contrast
                                        Rectangle {
                                            anchors.fill: parent
                                            color: Qt.rgba(0, 0, 0, 0.22)
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
                                            Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

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
                                                color: Qt.rgba(Theme.surfaceBg.r, Theme.surfaceBg.g, Theme.surfaceBg.b, CompositorService.blurEnabled ? 0.80 : 0.97)
                                                border.width: Math.max(0, Math.min(4, CompositorService.borderSize))
                                                border.color: root.activeBorderHighlight ? Theme.accent : Theme.borderSubtle
                                                Behavior on radius { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                                ColumnLayout {
                                                    anchors.fill: parent; anchors.margins: 10; spacing: 6
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        Text { text: "Settings • Personalization"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 10; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                                                        Rectangle { width: 6; height: 6; radius: 3; color: Theme.accent }
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

                            // 2. Theme Presets (Pre-configured + Local .paish + Share Code)
                            SectionLabel { text: "Theme presets" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 2; columnSpacing: 10; rowSpacing: 10
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

                            SectionLabel { text: "Quick Share Code (Personalization + Advanced)" }
                            SettingGroup {
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: shareCodeCol.implicitHeight + 24
                                    ColumnLayout {
                                        id: shareCodeCol
                                        anchors.fill: parent; anchors.margins: 12; spacing: 8

                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 2
                                                Text { text: "Export current settings as compact code"; color: Theme.text; font.family: Theme.fontSans; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight; Layout.fillWidth: true }
                                                Text {
                                                    readonly property string previewCode: root.shellState ? root.shellState.exportThemeCode().code : Theme.encodeState(null, CompositorService, bgLayer).code
                                                    text: previewCode
                                                    color: Theme.textSub; font.family: Theme.fontMono; font.pixelSize: 10
                                                    elide: Text.ElideMiddle; Layout.fillWidth: true
                                                }
                                            }
                                            CtrlBtn {
                                                text: "Copy Raw"
                                                ghost: true
                                                onClicked: {
                                                    const b = root.shellState ? root.shellState.exportThemeCode() : Theme.encodeState(null, CompositorService, bgLayer);
                                                    FileService.copyToClipboard(b.raw);
                                                    root.themeExportOk = true;
                                                    root.themeExportStatus = "Copied raw values (" + b.raw.length + " chars)";
                                                }
                                            }
                                            CtrlBtn {
                                                text: "Copy Code"
                                                onClicked: {
                                                    const b = root.shellState ? root.shellState.exportThemeCode() : Theme.encodeState(null, CompositorService, bgLayer);
                                                    FileService.copyToClipboard(b.code);
                                                    root.themeExportOk = true;
                                                    root.themeExportStatus = "Copied share code (" + b.code.length + " chars)";
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true; height: 1; color: Theme.borderSubtle
                                        }

                                        Text { text: "Paste share code (PAISH1:...) or raw ';' string to apply"; color: Theme.textSub; font.family: Theme.fontSans; font.pixelSize: 11 }
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
                                                        if (root.shellState && root.shellState.importThemeCode(root.themeImportInput)) {
                                                            root.themeExportOk = true;
                                                            root.themeExportStatus = "Applied theme code & synced!";
                                                            root.themeImportInput = "";
                                                        } else {
                                                            root.themeExportOk = false;
                                                            root.themeExportStatus = "Invalid theme code or format";
                                                        }
                                                    }
                                                    Text {
                                                        anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                                                        text: "PAISH1:... or 1;0;0;26;..."
                                                        color: Theme.textMuted; font: parent.font
                                                        visible: parent.text === ""
                                                    }
                                                }
                                            }
                                            CtrlBtn {
                                                text: "Apply Code"
                                                onClicked: {
                                                    if (root.shellState && root.shellState.importThemeCode(root.themeImportInput)) {
                                                        root.themeExportOk = true;
                                                        root.themeExportStatus = "Applied theme code & synced!";
                                                        root.themeImportInput = "";
                                                    } else {
                                                        root.themeExportOk = false;
                                                        root.themeExportStatus = "Invalid theme code or format";
                                                    }
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
                                    showDivider: false; iconChar: "✦"; title: "Window Blur (Kawase)"; subtitle: "Frosted translucency behind panels"
                                    CtrlSwitch { checked: CompositorService.blurEnabled; onToggled: (v) => { CompositorService.setBlurConfig(v, CompositorService.blurSize, CompositorService.blurPasses, CompositorService.blurVibrancy); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "⚡"; title: "Hyprland Animations"; subtitle: "Smooth spring window transitions"
                                    CtrlSwitch { checked: CompositorService.animationsEnabled; onToggled: (v) => { CompositorService.setAnimationsEnabled(v); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "⛶"; title: "Dynamic Island Auto-Hide"; subtitle: "Hide status bar when fullscreen or overlapped"
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
                                    iconChar: "▢"; title: "Active Border Highlight"; subtitle: "Crisp outline on focused window"
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
                            HubCard { iconChar: "◐"; title: "Appearance"; subtitle: "Themes, colors, wallpaper, decoration & blur"; pillText: Theme.activePreset + " • " + (CompositorService.blurEnabled ? "Blur" : "No Blur"); onTriggered: root.openPage("appearance") }
                            HubCard { iconChar: "⌨"; title: "Binding"; subtitle: "Shortcuts, apps, capture & Island IPC"; pillText: KeybindService.totalComboCount + " binds"; onTriggered: root.openPage("keybind") }
                            HubCard { iconChar: "◫"; title: "Layout"; subtitle: "Tiling, gaps, borders & Dynamic Island"; pillText: CompositorService.layoutName + " • " + CompositorService.gapsIn + "/" + CompositorService.gapsOut + "px"; onTriggered: root.openPage("layout") }
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

                            SectionLabel { text: "Surface & Accent" }
                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "◐"; title: "Global Surface Theme"; subtitle: "Contrast & backdrop style synced across apps"
                                    CtrlSelect { options: ["OLED Pure", "Mica Dark", "Adaptive"]; currentText: root.globalSurfaceTheme; onSelected: (v) => { root.globalSurfaceTheme = v; if (root.shellState) root.shellState.globalSurfaceTheme = v; root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "Aa"; title: "Accent Style"; subtitle: "Solid monochrome or directional gradient"
                                    CtrlSelect { options: ["Solid", "Gradient"]; currentText: root.accentMode; onSelected: (v) => { root.accentMode = v; Theme.accentMode = v; root.markAppearanceChanged(); } }
                                }
                            }

                            AdvancedSection {
                                subtitle: "HSV Accent & Contrast Studio, Hue & Gradient Angle"
                                Item {
                                    Layout.fillWidth: true
                                    implicitHeight: hsvStudioCol.implicitHeight + 24
                                    ColumnLayout {
                                        id: hsvStudioCol
                                        anchors.fill: parent; anchors.margins: 12; spacing: 10
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { Layout.fillWidth: true; text: "Accent & Contrast Studio"; color: Theme.text; font.pixelSize: 13; font.weight: Font.DemiBold }
                                            CtrlBtn { text: "Reset Preset Accent"; ghost: true; onClicked: root.selectThemePreset(Theme.activePreset) }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 14
                                            Rectangle {
                                                id: svBox
                                                width: 130; height: 130; radius: 8
                                                color: Qt.hsva(root.hueVal, 1.0, 1.0, 1.0)
                                                border.width: 1; border.color: Theme.borderSubtle
                                                Rectangle {
                                                    anchors.fill: parent; radius: 8
                                                    gradient: Gradient {
                                                        orientation: Gradient.Horizontal
                                                        GradientStop { position: 0.0; color: "#ffffff" }
                                                        GradientStop { position: 1.0; color: "transparent" }
                                                    }
                                                }
                                                Rectangle {
                                                    anchors.fill: parent; radius: 8
                                                    gradient: Gradient {
                                                        orientation: Gradient.Vertical
                                                        GradientStop { position: 0.0; color: "transparent" }
                                                        GradientStop { position: 1.0; color: "#000000" }
                                                    }
                                                }
                                                Rectangle {
                                                    width: 10; height: 10; radius: 5
                                                    x: root.satVal * (svBox.width - 10)
                                                    y: (1.0 - root.valVal) * (svBox.height - 10)
                                                    color: "transparent"; border.width: 2; border.color: "#ffffff"
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    onPositionChanged: (m) => { if (pressed) { root.satVal = Math.max(0, Math.min(1, m.x / width)); root.valVal = Math.max(0, Math.min(1, 1.0 - m.y / height)); if (root.shellState) root.shellState.applyCustomAccent(root.hueVal, root.satVal, root.valVal); else Theme.applyAccentHsv(root.hueVal, root.satVal, root.valVal); } }
                                                    onClicked: (m) => { root.satVal = Math.max(0, Math.min(1, m.x / width)); root.valVal = Math.max(0, Math.min(1, 1.0 - m.y / height)); if (root.shellState) root.shellState.applyCustomAccent(root.hueVal, root.satVal, root.valVal); else Theme.applyAccentHsv(root.hueVal, root.satVal, root.valVal); }
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 8
                                                Text { text: "Hue"; color: Theme.textSub; font.pixelSize: 11 }
                                                HueSlider { Layout.fillWidth: true; value: root.hueVal; onMoved: { root.hueVal = value; if (root.shellState) root.shellState.applyCustomAccent(root.hueVal, root.satVal, root.valVal); else Theme.applyAccentHsv(root.hueVal, root.satVal, root.valVal); } }
                                                Text { text: "Gradient Angle: " + root.gradientAngle + "°"; color: Theme.textSub; font.pixelSize: 11 }
                                                CtrlSlider { Layout.fillWidth: true; fillSlider: true; showValue: false; from: 0; to: 360; value: root.gradientAngle; onMoved: (v) => { root.gradientAngle = v; Theme.gradientAngle = v; root.markAppearanceChanged(); } }
                                                Rectangle {
                                                    Layout.fillWidth: true; height: 28; radius: 14
                                                    color: Theme.pillBg; border.width: 1; border.color: Theme.borderSubtle
                                                    RowLayout {
                                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                                        Text { text: "27°C"; color: Theme.text; font.pixelSize: 11; font.weight: Font.Bold }
                                                        Item { Layout.fillWidth: true }
                                                        Rectangle { width: 42; height: 14; radius: 7; color: Qt.hsva(root.hueVal, root.satVal, root.valVal, 1.0) }
                                                        Item { Layout.fillWidth: true }
                                                        Text { text: "09:12"; color: Theme.text; font.pixelSize: 11 }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            SectionLabel { text: "Wallpaper & Transitions" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 3; columnSpacing: 8; rowSpacing: 8
                                PresetCard {
                                    title: "Crossfade + Scale"
                                    subtitle: "Smooth zoom & fade"
                                    active: bgLayer.transitionMode === "crossfade-scale"
                                    onTriggered: { bgLayer.transitionMode = "crossfade-scale"; root.markAppearanceChanged(); }
                                }
                                PresetCard {
                                    title: "Crossfade"
                                    subtitle: "Clean opacity blend"
                                    active: bgLayer.transitionMode === "crossfade"
                                    onTriggered: { bgLayer.transitionMode = "crossfade"; root.markAppearanceChanged(); }
                                }
                                PresetCard {
                                    title: "Instant"
                                    subtitle: "Zero transition delay"
                                    active: bgLayer.transitionMode === "instant"
                                    onTriggered: { bgLayer.transitionMode = "instant"; root.markAppearanceChanged(); }
                                }
                            }
                            GridLayout {
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
                                                    sourceSize.width: 480
                                                    sourceSize.height: 270
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
                                                    color: wpCard.isActive ? Theme.accent : Qt.rgba(0, 0, 0, 0.58)
                                                    border.width: wpCard.isActive ? 0 : 1
                                                    border.color: wpMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) : Qt.rgba(1, 1, 1, 0.16)
                                                    opacity: wpCard.isActive ? 1.0 : (wpMouse.containsMouse ? 1.0 : 0.78)

                                                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                                    Text {
                                                        id: wpBadgeLbl
                                                        anchors.centerIn: parent
                                                        text: wpCard.isActive ? "Active" : "Apply"
                                                        color: wpCard.isActive ? Theme.accentFg : "#FFFFFF"
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 10
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: wpCard.modelData.split("/").pop()
                                                    color: Theme.text
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 12
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: wpCard.modelData.replace("file://", "")
                                                    color: Theme.textSub
                                                    font.family: Theme.fontSans
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
                                                bgLayer.currentIndex = wpCard.index;
                                                bgLayer.setWallpaper(wpCard.modelData);
                                                root.markAppearanceChanged();
                                            }
                                        }
                                    }
                                }
                            }

                            SectionLabel { text: "Window Decoration" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 3; columnSpacing: 8; rowSpacing: 8
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
                                SettingRow {
                                    showDivider: false; iconChar: "◐"; title: "Drop Shadows"; subtitle: "Render soft ambient window shadows"
                                    CtrlSwitch { checked: CompositorService.shadowEnabled; onToggled: (v) => { CompositorService.setDecoration(CompositorService.cornerRounding, v, CompositorService.inactiveOpacity); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "◈"; title: "Dim inactive windows"; subtitle: "Subtle translucency on unfocused windows"
                                    CtrlSwitch { checked: CompositorService.inactiveOpacity < 0.99; onToggled: (v) => { CompositorService.setDecoration(CompositorService.cornerRounding, CompositorService.shadowEnabled, v ? 0.94 : 1.0); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "✦"; title: "Hyprland Animations"; subtitle: CompositorService.animationsEnabled ? "Enabled • Spring & bezier motion active" : "Disabled • Instant window transitions"
                                    CtrlSwitch { checked: CompositorService.animationsEnabled; onToggled: (v) => { CompositorService.setAnimationsEnabled(v); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "◎"; title: "Kawase Blur"; subtitle: CompositorService.blurEnabled ? ("Enabled • " + CompositorService.blurSize + "px • " + CompositorService.blurPasses + " passes") : "Disabled"
                                    CtrlSwitch { checked: CompositorService.blurEnabled; onToggled: (v) => { CompositorService.setBlurConfig(v, CompositorService.blurSize, CompositorService.blurPasses, CompositorService.blurVibrancy); root.markAppearanceChanged(); } }
                                }
                            }

                            AdvancedSection {
                                subtitle: "Corner rounding, shadow spread, spring physics & Kawase blur"
                                SettingRow {
                                    showDivider: false; iconChar: "▢"; title: "Corner rounding"; subtitle: "Window border radius"
                                    CtrlSlider { from: 0; to: 28; value: CompositorService.cornerRounding; unit: "px"; onMoved: (v) => { CompositorService.setDecoration(v, CompositorService.shadowEnabled, CompositorService.inactiveOpacity); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "◈"; title: "Inactive opacity"; subtitle: "Opacity of unfocused windows"
                                    CtrlSlider { from: 60; to: 100; value: Math.round(CompositorService.inactiveOpacity * 100); unit: "%"; onMoved: (v) => { CompositorService.setDecoration(CompositorService.cornerRounding, CompositorService.shadowEnabled, v / 100.0); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "◐"; title: "Shadow range"; subtitle: "Drop shadow spread radius"
                                    CtrlSlider { from: 0; to: 48; value: root.shadowRange; unit: "px"; onMoved: (v) => { root.shadowRange = v; Theme.shadowRange = v; root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "⚡"; title: "Spring Stiffness"; subtitle: "Motion responsiveness (" + CompositorService.springStiffness + ")"
                                    CtrlSlider { from: 80; to: 600; value: CompositorService.springStiffness; unit: ""; enabled: CompositorService.animationsEnabled; onMoved: (v) => { CompositorService.setSpringCurve(v, CompositorService.springDamping); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "〰"; title: "Spring Damping"; subtitle: "Settle resistance (" + CompositorService.springDamping + ")"
                                    CtrlSlider { from: 5; to: 60; value: CompositorService.springDamping; unit: ""; enabled: CompositorService.animationsEnabled; onMoved: (v) => { CompositorService.setSpringCurve(CompositorService.springStiffness, v); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "◎"; title: "Blur Size"; subtitle: "Kawase blur radius in pixels"
                                    CtrlSlider { from: 1; to: 24; value: CompositorService.blurSize; unit: "px"; enabled: CompositorService.blurEnabled; onMoved: (v) => { CompositorService.setBlurConfig(CompositorService.blurEnabled, v, CompositorService.blurPasses, CompositorService.blurVibrancy); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "≡"; title: "Blur Passes"; subtitle: "Dual-pass iterations (1–6)"
                                    CtrlSlider { from: 1; to: 6; value: CompositorService.blurPasses; unit: ""; enabled: CompositorService.blurEnabled; onMoved: (v) => { CompositorService.setBlurConfig(CompositorService.blurEnabled, CompositorService.blurSize, v, CompositorService.blurVibrancy); root.markAppearanceChanged(); } }
                                }
                                SettingRow {
                                    iconChar: "✨"; title: "Blur Vibrancy"; subtitle: "Color boost (" + Math.round(CompositorService.blurVibrancy * 100) + "%)"
                                    CtrlSlider { from: 0; to: 100; value: Math.round(CompositorService.blurVibrancy * 100); unit: "%"; enabled: CompositorService.blurEnabled; onMoved: (v) => { CompositorService.setBlurConfig(CompositorService.blurEnabled, CompositorService.blurSize, CompositorService.blurPasses, v / 100.0); root.markAppearanceChanged(); } }
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
                                    showDivider: false; iconChar: "◫"; title: "Master split ratio"; subtitle: "Percentage width reserved for primary window"
                                    CtrlSlider { from: 30; to: 80; value: root.masterRatio; unit: "%"; onMoved: (v) => { root.masterRatio = v; Theme.masterRatio = v; } }
                                }
                                SettingRow {
                                    title: "Preserve split direction"; subtitle: "Keep orientation consistent when closing windows"
                                    CtrlTickBox { checked: root.preserveSplit; onToggled: (v) => { root.preserveSplit = v; Theme.preserveSplit = v; } }
                                }
                            }

                            SectionLabel { text: "Gaps & Borders" }
                            GridLayout {
                                Layout.fillWidth: true; columns: 3; columnSpacing: 8; rowSpacing: 8
                                PresetCard {
                                    title: "Compact"
                                    subtitle: "In 3px • Out 6px • 1px"
                                    active: CompositorService.gapsIn === 3 && CompositorService.gapsOut === 6
                                    onTriggered: CompositorService.setGapsAndBorder(3, 6, 1)
                                }
                                PresetCard {
                                    title: "Balanced"
                                    subtitle: "In 6px • Out 12px • 1px"
                                    active: CompositorService.gapsIn === 6 && CompositorService.gapsOut === 12
                                    onTriggered: CompositorService.setGapsAndBorder(6, 12, 1)
                                }
                                PresetCard {
                                    title: "Spacious"
                                    subtitle: "In 12px • Out 24px • 2px"
                                    active: CompositorService.gapsIn === 12 && CompositorService.gapsOut === 24
                                    onTriggered: CompositorService.setGapsAndBorder(12, 24, 2)
                                }
                            }

                            SettingGroup {
                                SettingRow {
                                    showDivider: false; iconChar: "▢"; title: "Active Border Highlight"; subtitle: "Show crisp outline on focused window"
                                    CtrlSwitch {
                                        checked: root.shellState ? root.shellState.activeBorderHighlight : root.activeBorderHighlight
                                        onToggled: (v) => {
                                            root.activeBorderHighlight = v;
                                            if (root.shellState) root.shellState.activeBorderHighlight = v;
                                        }
                                    }
                                }
                            }

                            AdvancedSection {
                                subtitle: "Raw inner/outer pixel gaps & border thickness"
                                SettingRow {
                                    showDivider: false; iconChar: "❖"; title: "Inner gaps"; subtitle: "Space between tiled windows"
                                    CtrlSlider { from: 0; to: 32; value: CompositorService.gapsIn; unit: "px"; onMoved: (v) => CompositorService.setGapsAndBorder(v, CompositorService.gapsOut, CompositorService.borderSize) }
                                }
                                SettingRow {
                                    iconChar: "◰"; title: "Outer gaps"; subtitle: "Margin around screen edges"
                                    CtrlSlider { from: 0; to: 48; value: CompositorService.gapsOut; unit: "px"; onMoved: (v) => CompositorService.setGapsAndBorder(CompositorService.gapsIn, v, CompositorService.borderSize) }
                                }
                                SettingRow {
                                    iconChar: "□"; title: "Border thickness"; subtitle: "Window stroke width"
                                    CtrlSlider { from: 0; to: 6; value: CompositorService.borderSize; unit: "px"; onMoved: (v) => CompositorService.setGapsAndBorder(CompositorService.gapsIn, CompositorService.gapsOut, v) }
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
                                        }
                                    }
                                }
                            }

                            SettingGroup {
                                SettingRow {
                                    iconChar: "⇵"
                                    title: "Status bar position"
                                    subtitle: "Place Dynamic Island at the top or bottom edge of the screen"
                                    CtrlSelect {
                                        options: ["Top", "Bottom"]
                                        currentText: (root.shellState ? root.shellState.barPosition : root.barPosition) === "bottom" ? "Bottom" : "Top"
                                        onSelected: (v) => {
                                            const pos = (v === "Bottom") ? "bottom" : "top";
                                            root.barPosition = pos;
                                            if (root.shellState) root.shellState.barPosition = pos;
                                        }
                                    }
                                }
                                SettingRow {
                                    showDivider: false
                                    iconChar: "⛶"
                                    title: "Behavior"
                                    subtitle: "Control when Dynamic Island hides on fullscreen or window overlap"
                                    CtrlSelect {
                                        options: ["Always Show", "Hide in Fullscreen", "Auto-Hide (Overlap)"]
                                        currentText: {
                                            if (root.shellState) {
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
                                                }
                                            } else if (v === "Hide in Fullscreen") {
                                                root.hideBarFullscreen = true;
                                                root.islandAutoHide = true;
                                                if (root.shellState) {
                                                    root.shellState.hideBarFullscreen = true;
                                                    root.shellState.autoHideOnOverlap = false;
                                                }
                                            } else {
                                                root.hideBarFullscreen = true;
                                                root.islandAutoHide = true;
                                                if (root.shellState) {
                                                    root.shellState.hideBarFullscreen = true;
                                                    root.shellState.autoHideOnOverlap = true;
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            AdvancedSection {
                                subtitle: "Corner radius & screen edge offset"
                                SettingRow {
                                    showDivider: false; iconChar: "◐"; title: "Status bar corner radius"; subtitle: "Roundness of Dynamic Island pills"
                                    CtrlSelect {
                                        options: ["12px", "18px", "26px (Default)"]
                                        currentText: root.shellState ? root.shellState.islandCornerRadius : root.islandCornerRadius
                                        onSelected: (v) => {
                                            root.islandCornerRadius = v;
                                            if (root.shellState) root.shellState.islandCornerRadius = v;
                                        }
                                    }
                                }
                                SettingRow {
                                    iconChar: "↕"; title: "Screen edge offset"; subtitle: "12px at rest, 16px on hover / Dashboard"
                                    CtrlSwitch {
                                        checked: root.shellState ? root.shellState.topEdgeOffset : root.topEdgeOffset
                                        onToggled: (v) => {
                                            root.topEdgeOffset = v;
                                            if (root.shellState) root.shellState.topEdgeOffset = v;
                                        }
                                    }
                                }
                            }
                        }
                        }

                        // ==================== KEYBINDS ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "keybind"
                            active: Boolean(root.loadedPages["keybind"])
                            sourceComponent: KeybindSettingsPage {
                                onEditRequested: (bindObj, comboIdx, defaultTab) => {
                                    keybindEditorLoader.active = true;
                                    if (keybindEditorLoader.item) {
                                        if (bindObj) keybindEditorLoader.item.openEdit(bindObj, comboIdx);
                                        else keybindEditorLoader.item.openNew(defaultTab);
                                    }
                                }
                            }
                        }

                        // ==================== 17b. STORAGE ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "storage"
                            active: Boolean(root.loadedPages["storage"])
                            sourceComponent: StorageSettingsPage {
                                shellState: root.shellState
                                onConfirmActionRequested: (payload) => storageConfirmOverlay.openWith(payload)
                            }
                        }

                        // ==================== 18. ABOUT ====================
                        Loader {
                            Layout.fillWidth: true
                            Layout.preferredHeight: item ? item.implicitHeight : 0
                            visible: root.currentPage === "about"
                            active: Boolean(root.loadedPages["about"])
                            sourceComponent: AboutSettingsPage {
                                shellState: root.shellState
                            }
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

    // Shared Sudo Password Dialog (Package Cache Cleaning + Btrfs / Storage Elevation)
    Rectangle {
        id: sudoAuthOverlay
        readonly property bool activeOpen: PackageService.sudoPromptOpen || BackupService.authPromptOpen || StorageService.authPromptOpen
        readonly property bool isBackupAuth: BackupService.authPromptOpen
        readonly property bool isStorageAuth: StorageService.authPromptOpen
        readonly property string errText: isBackupAuth ? BackupService.authPromptError : (isStorageAuth ? StorageService.authPromptError : PackageService.sudoPromptError)

        function cancelActive() {
            if (isBackupAuth) BackupService.cancelAuthPrompt();
            else if (isStorageAuth) StorageService.cancelAuthPrompt();
            else PackageService.cancelSudoPrompt();
        }
        function submitActive() {
            const pwd = sudoPasswordField.text;
            sudoPasswordField.text = "";
            if (isBackupAuth) BackupService.submitAuthPassword(pwd);
            else if (isStorageAuth) StorageService.submitAuthPassword(pwd);
            else PackageService.submitSudoPassword(pwd);
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
            target: PackageService
            function onSudoPromptOpenChanged() {
                if (PackageService.sudoPromptOpen) {
                    sudoPasswordField.text = "";
                    sudoPasswordField.forceActiveFocus();
                }
            }
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
                        : (sudoAuthOverlay.isStorageAuth ? StorageService.authPromptTitle : "Sudo Password Required")
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
                        : (sudoAuthOverlay.isStorageAuth ? StorageService.authPromptDesc : "Enter your sudo password to clean package manager cache.")
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
                            : (sudoAuthOverlay.isStorageAuth ? StorageService.authPromptActionLabel : "Clean Cache")
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
                                            Text {
                                                text: modelData.status === "ok" ? "✓" : (modelData.status === "warn" ? "!" : "✗")
                                                color: modelData.status === "ok" ? Theme.ok : (modelData.status === "warn" ? Theme.warn : Theme.dangerText)
                                                font.family: Theme.fontMono
                                                font.pixelSize: 11
                                                font.weight: Font.Bold
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
        sourceComponent: KeybindEditorModal {
            selectMenu: selectMenu
            menuRoot: root
        }
    }
}
