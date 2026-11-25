pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    // Core Monochrome OLED Palette
    property color pillBg: "#000000"
    property color surfaceBg: "#0b0b0c"
    property color surfaceRaised: "#101012"
    property color cardBg: Qt.rgba(1, 1, 1, 0.08)
    property color cardHover: Qt.rgba(1, 1, 1, 0.14)
    property color borderSubtle: Qt.rgba(1, 1, 1, 0.14)
    property color text: "#ffffff"
    property color textSub: Qt.rgba(1, 1, 1, 0.60)
    property color textMuted: Qt.rgba(1, 1, 1, 0.45)
    property color accent: "#ffffff"
    property color accentFg: "#000000"

    // Semantic Status Accents
    readonly property color ok: "#30d158"
    readonly property color info: "#0a84ff"
    readonly property color danger: "#ff453a"
    readonly property color dangerText: "#ff6961"
    readonly property color warn: "#ff9f0a"

    // Typography
    property string fontSans: "Open Sans"
    property string fontMono: "JetBrains Mono"

    // Island Dimensions & Spacing
    property int islandHeight: 54
    property int islandRadius: 26
    property int topOffsetRest: 12
    property int topOffsetHover: 16
    property int splitGap: 14
    property int shaderPad: 32

    // Motion Curves (Zero Dead Animations)
    property real speedMultiplier: 1.0
    property int springMs: Math.max(80, Math.round(420 / speedMultiplier))
    property int smoothMs: Math.max(60, Math.round(320 / speedMultiplier))
    property real springOvershoot: 1.35

    // Visual Features
    property bool gooeyEnabled: true
    property string activePreset: "OLED Pure"

    // Extended Personalization State (shared across SettingsView & .paish profiles)
    property string accentMode: "Solid"
    property real hueVal: 0.0
    property real satVal: 0.0
    property real valVal: 0.92
    property int gradientAngle: 135
    property int masterRatio: 55
    property bool preserveSplit: true
    property int shadowRange: 24
    property bool customAccentActive: false

    readonly property var presetNames: ["OLED Pure", "Mica Dark", "Adaptive", "Nord Frost", "Mica Monochrome", "Catppuccin Mocha"]
    readonly property var surfaceThemeNames: ["OLED Pure", "Mica Dark", "Adaptive"]
    readonly property var transitionModes: ["crossfade-scale", "crossfade", "instant"]
    readonly property var cursorStyles: ["sharp", "soft", "wedge"]
    readonly property var cursorColorModes: ["auto", "theme", "fixed"]
    readonly property var lockEffectPresets: ["none", "snow", "rain", "wind"]
    readonly property var lockAmbientSounds: ["none", "wind", "rain", "snow"]

    readonly property var presetCatalog: [
        {
            name: "OLED Pure",
            subtitle: "Pure black • 18px • Blur 6px",
            shortDesc: "High Contrast • Default",
            surfaceTheme: "OLED Pure",
            compositorKey: "oled",
            previewBg: "#050505",
            previewAccent: "#ffffff",
            pillBg: "#000000",
            surfaceBg: "#0b0b0c",
            surfaceRaised: "#101012",
            text: "#ffffff",
            accent: "#ffffff",
            accentFg: "#000000",
            cardAlpha: 0.08,
            hoverAlpha: 0.14,
            borderAlpha: 0.14
        },
        {
            name: "Nord Frost",
            subtitle: "Cool cyan • 16px • Blur 9px",
            shortDesc: "Cool Slate • Cyan",
            surfaceTheme: "Adaptive",
            compositorKey: "ocean",
            previewBg: "#1a1f29",
            previewAccent: "#88c0d0",
            pillBg: "#1a1f29",
            surfaceBg: "#212734",
            surfaceRaised: "#293040",
            text: "#eceff4",
            accent: "#88c0d0",
            accentFg: "#141a24",
            cardAlpha: 0.09,
            hoverAlpha: 0.15,
            borderAlpha: 0.18
        },
        {
            name: "Mica Monochrome",
            subtitle: "Frosted slate • 14px • Blur 12px",
            shortDesc: "Frosted Blur • Glass",
            surfaceTheme: "Mica Dark",
            compositorKey: "mica",
            previewBg: "#141416",
            previewAccent: "#d4d4d8",
            pillBg: "#141416",
            surfaceBg: "#1b1b1e",
            surfaceRaised: "#232327",
            text: "#f2f2f4",
            accent: "#d4d4d8",
            accentFg: "#111113",
            cardAlpha: 0.09,
            hoverAlpha: 0.15,
            borderAlpha: 0.16
        },
        {
            name: "Catppuccin Mocha",
            subtitle: "Warm mauve • 16px • Blur 10px",
            shortDesc: "Soothing Pastel • Mauve",
            surfaceTheme: "Adaptive",
            compositorKey: "ocean",
            previewBg: "#1e1e2e",
            previewAccent: "#cba6f7",
            pillBg: "#1e1e2e",
            surfaceBg: "#181825",
            surfaceRaised: "#313244",
            text: "#cdd6f4",
            accent: "#cba6f7",
            accentFg: "#11111b",
            cardAlpha: 0.09,
            hoverAlpha: 0.15,
            borderAlpha: 0.18
        },
        {
            name: "Mica Dark",
            subtitle: "Soft blue • 6px • Crisp",
            shortDesc: "Soft Blue • Minimal",
            surfaceTheme: "Mica Dark",
            compositorKey: "minimal",
            previewBg: "#14161a",
            previewAccent: "#a8c7fa",
            pillBg: "#121418",
            surfaceBg: "#161920",
            surfaceRaised: "#1d212a",
            text: "#eef2f9",
            accent: "#a8c7fa",
            accentFg: "#0b1220",
            cardAlpha: 0.09,
            hoverAlpha: 0.15,
            borderAlpha: 0.16
        },
        {
            name: "Adaptive",
            subtitle: "Teal glass • 16px • Blur 8px",
            shortDesc: "Dynamic • Teal",
            surfaceTheme: "Adaptive",
            compositorKey: "adaptive",
            previewBg: "#0d1216",
            previewAccent: "#80cbc4",
            pillBg: "#0d1216",
            surfaceBg: "#10161c",
            surfaceRaised: "#161e26",
            text: "#edf6f5",
            accent: "#80cbc4",
            accentFg: "#071a18",
            cardAlpha: 0.09,
            hoverAlpha: 0.15,
            borderAlpha: 0.16
        }
    ]

    signal presetApplied(string name)

    function presetMeta(name) {
        for (let i = 0; i < presetCatalog.length; ++i) {
            if (presetCatalog[i].name === name) return presetCatalog[i];
        }
        return null;
    }

    function applyAccentHsv(h, s, v) {
        root.hueVal = Math.max(0, Math.min(1, Number(h) || 0));
        root.satVal = Math.max(0, Math.min(1, Number(s) || 0));
        root.valVal = Math.max(0, Math.min(1, Number(v) || 0));
        root.customAccentActive = true;
        const c = Qt.hsva(root.hueVal, root.satVal, root.valVal, 1.0);
        root.accent = c;
        const lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        root.accentFg = lum > 0.52 ? "#000000" : "#ffffff";
    }

    function applyPreset(name) {
        const p = presetMeta(name);
        if (!p) return false;
        root.activePreset = name;
        root.customAccentActive = false;
        root.accentMode = "Solid";
        root.hueVal = 0;
        root.satVal = 0;
        root.valVal = 0.92;
        root.pillBg = p.pillBg;
        root.surfaceBg = p.surfaceBg;
        root.surfaceRaised = p.surfaceRaised;
        root.text = p.text;
        root.accent = p.accent;
        root.accentFg = p.accentFg;
        root.textSub = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.62);
        root.textMuted = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.45);
        root.cardBg = Qt.rgba(root.text.r, root.text.g, root.text.b, p.cardAlpha);
        root.cardHover = Qt.rgba(root.text.r, root.text.g, root.text.b, p.hoverAlpha);
        root.borderSubtle = Qt.rgba(root.text.r, root.text.g, root.text.b, p.borderAlpha);
        root.presetApplied(name);
        return true;
    }

    function loadBundle(jsonStr) {
        try {
            const obj = JSON.parse(jsonStr);
            if (!obj || typeof obj !== "object") return false;
            const colors = obj.palette && obj.palette.colors ? obj.palette.colors : obj.colors;
            if (Array.isArray(colors) && colors.length >= 2) {
                root.pillBg = colors[0];
                root.text = colors[1];
                root.accent = colors[1];
                root.accentFg = colors[0];
                root.textSub = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.62);
                root.textMuted = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.45);
                root.cardBg = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.07);
                root.cardHover = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.13);
                root.borderSubtle = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.15);
                if (colors.length >= 3) {
                    root.surfaceBg = colors[2];
                    root.surfaceRaised = colors[2];
                }
            }
            if (obj.palette && typeof obj.palette.islandRadius === "number") {
                root.islandRadius = obj.palette.islandRadius;
            }
            return true;
        } catch (e) {
            console.warn("Theme.loadBundle failed:", e);
            return false;
        }
    }

    function buildPaishState(stateObj, compositor, profileName, cursorSvc, lockSvc) {
        const effectiveName = (profileName !== undefined && profileName !== null)
            ? String(profileName)
            : (stateObj && stateObj.activeProfile ? String(stateObj.activeProfile) : "");
        return {
            // 1. Theme & Accent
            presetName: root.activePreset,
            globalSurfaceTheme: stateObj ? stateObj.globalSurfaceTheme : "OLED Pure",
            customAccentActive: Boolean(root.customAccentActive),
            accentMode: root.accentMode,
            hueVal: root.hueVal,
            satVal: root.satVal,
            valVal: root.valVal,
            gradientAngle: Math.round(root.gradientAngle),
            gooeyEnabled: Boolean(root.gooeyEnabled),
            speedMultiplier: root.speedMultiplier,
            // 2. Decoration, Motion & Blur
            cornerRounding: compositor ? Math.round(compositor.cornerRounding) : 18,
            shadowEnabled: compositor ? Boolean(compositor.shadowEnabled) : true,
            shadowRange: Math.round(root.shadowRange),
            inactiveOpacity: compositor ? compositor.inactiveOpacity : 0.96,
            animationsEnabled: compositor ? Boolean(compositor.animationsEnabled) : true,
            springStiffness: compositor ? Math.round(compositor.springStiffness) : 260,
            springDamping: compositor ? Math.round(compositor.springDamping) : 23,
            blurEnabled: compositor ? Boolean(compositor.blurEnabled) : true,
            blurSize: compositor ? Math.round(compositor.blurSize) : 6,
            blurPasses: compositor ? Math.round(compositor.blurPasses) : 2,
            blurVibrancy: compositor ? compositor.blurVibrancy : 0.12,
            // 3. Layout & Dynamic Island
            layoutName: compositor ? compositor.layoutName : "dwindle",
            masterRatio: Math.round(root.masterRatio),
            preserveSplit: Boolean(root.preserveSplit),
            gapsIn: compositor ? Math.round(compositor.gapsIn) : 6,
            gapsOut: compositor ? Math.round(compositor.gapsOut) : 12,
            borderSize: compositor ? Math.round(compositor.borderSize) : 1,
            activeBorderHighlight: stateObj ? Boolean(stateObj.activeBorderHighlight) : true,
            barPosition: stateObj ? stateObj.barPosition : "top",
            islandCornerRadius: stateObj ? stateObj.islandCornerRadius : "26px (Default)",
            topEdgeOffset: stateObj ? Boolean(stateObj.topEdgeOffset) : true,
            hideBarFullscreen: stateObj ? Boolean(stateObj.hideBarFullscreen) : true,
            autoHideOnOverlap: stateObj ? Boolean(stateObj.autoHideOnOverlap) : false,
            // 4. Cursor
            cursorStyle: cursorSvc ? cursorSvc.style : "sharp",
            cursorSize: cursorSvc ? Math.round(cursorSvc.size) : 24,
            cursorColorMode: cursorSvc ? cursorSvc.colorMode : "auto",
            cursorFixedColor: cursorSvc ? String(cursorSvc.fixedColor || "#ffffff") : "#ffffff",
            cursorMotionBlur: cursorSvc ? Boolean(cursorSvc.motionBlur) : false,
            // 5. Lock Screen
            lockEffectPreset: lockSvc ? lockSvc.effectPreset : "none",
            lockAmbientSound: lockSvc ? lockSvc.ambientSound : "wind",
            lockSilentMode: lockSvc ? Boolean(lockSvc.silentMode) : false,
            lockSfxEnabled: lockSvc ? Boolean(lockSvc.sfxEnabled) : true,
            lockShowNotifications: lockSvc ? Boolean(lockSvc.showNotifications) : true,
            lockHideNotifContent: lockSvc ? Boolean(lockSvc.hideNotifContent) : false,
            lockShowMedia: lockSvc ? Boolean(lockSvc.showMedia) : true,
            lockShowSystemAlerts: lockSvc ? Boolean(lockSvc.showSystemAlerts) : true,
            lockEffectIntensity: lockSvc ? Math.round(lockSvc.effectIntensity) : 100,
            lockAmbientVolume: lockSvc ? Math.round(lockSvc.ambientVolume) : 35,
            lockDimOpacity: lockSvc ? Math.round(lockSvc.dimOpacity) : 36,
            // 6. Embedded Profile / Preset Name
            profileName: effectiveName
        };
    }

    function exportBundle() {
        return JSON.stringify({
            name: "Paithosh Custom",
            version: "1.2",
            palette: {
                colors: [String(root.pillBg), String(root.text), String(root.surfaceBg)],
                islandRadius: root.islandRadius
            }
        });
    }
}
