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

    function _fmtNum(n) {
        return Number(n).toFixed(3).replace(/\.?0+$/, "") || "0";
    }

    readonly property string _b64UrlChars: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

    function _b64UrlEncode(str) {
        let out = "";
        for (let i = 0; i < str.length; i += 3) {
            const a = str.charCodeAt(i);
            const b = i + 1 < str.length ? str.charCodeAt(i + 1) : 0;
            const c = i + 2 < str.length ? str.charCodeAt(i + 2) : 0;
            const n = (a << 16) | (b << 8) | c;
            out += _b64UrlChars.charAt((n >> 18) & 63) + _b64UrlChars.charAt((n >> 12) & 63);
            if (i + 1 < str.length) out += _b64UrlChars.charAt((n >> 6) & 63);
            if (i + 2 < str.length) out += _b64UrlChars.charAt(n & 63);
        }
        return out;
    }

    function _b64UrlDecode(str) {
        let out = "";
        for (let i = 0; i < str.length; i += 4) {
            const c0 = _b64UrlChars.indexOf(str.charAt(i));
            const c1 = _b64UrlChars.indexOf(str.charAt(i + 1));
            const c2 = i + 2 < str.length ? _b64UrlChars.indexOf(str.charAt(i + 2)) : -1;
            const c3 = i + 3 < str.length ? _b64UrlChars.indexOf(str.charAt(i + 3)) : -1;
            if (c0 < 0 || c1 < 0) return null;
            const n = (c0 << 18) | (c1 << 12) | ((c2 >= 0 ? c2 : 0) << 6) | (c3 >= 0 ? c3 : 0);
            out += String.fromCharCode((n >> 16) & 255);
            if (c2 >= 0) out += String.fromCharCode((n >> 8) & 255);
            if (c3 >= 0) out += String.fromCharCode(n & 255);
        }
        return out;
    }

    function encodeState(stateObj, compositor, bgLayer, profileName) {
        const presetIdx = Math.max(0, presetNames.indexOf(root.activePreset));
        const surfaceIdx = Math.max(0, surfaceThemeNames.indexOf(stateObj ? stateObj.globalSurfaceTheme : "OLED Pure"));
        const islandRadStr = stateObj ? stateObj.islandCornerRadius : "26px (Default)";
        const islandRad = islandRadStr.indexOf("12") !== -1 ? 12 : (islandRadStr.indexOf("18") !== -1 ? 18 : 26);
        const transIdx = Math.max(0, transitionModes.indexOf(bgLayer ? bgLayer.transitionMode : "crossfade-scale"));
        const rawName = String(profileName || (stateObj && stateObj.activeProfile) || root.activePreset || "custom").trim();
        const cleanName = rawName.replace(/[^a-zA-Z0-9._-]/g, "_") || "custom";

        const vals = [
            1, // 0: schema version
            presetIdx, // 1: activePreset
            surfaceIdx, // 2: globalSurfaceTheme
            islandRad, // 3: islandCornerRadius (12 | 18 | 26)
            (stateObj && stateObj.topEdgeOffset) ? 1 : 0, // 4
            (stateObj && stateObj.hideBarFullscreen) ? 1 : 0, // 5
            (stateObj && stateObj.autoHideOnOverlap) ? 1 : 0, // 6
            (stateObj && stateObj.activeBorderHighlight) ? 1 : 0, // 7
            root.accentMode === "Gradient" ? 1 : 0, // 8
            _fmtNum(root.hueVal), // 9
            _fmtNum(root.satVal), // 10
            _fmtNum(root.valVal), // 11
            Math.round(root.gradientAngle), // 12
            compositor ? Math.round(compositor.gapsIn) : 6, // 13
            compositor ? Math.round(compositor.gapsOut) : 12, // 14
            compositor ? Math.round(compositor.borderSize) : 1, // 15
            (compositor && compositor.layoutName === "master") ? 1 : 0, // 16
            Math.round(root.masterRatio), // 17
            root.preserveSplit ? 1 : 0, // 18
            compositor ? Math.round(compositor.cornerRounding) : 18, // 19
            (compositor && compositor.shadowEnabled) ? 1 : 0, // 20
            _fmtNum(compositor ? compositor.inactiveOpacity : 0.96), // 21
            Math.round(root.shadowRange), // 22
            (compositor && compositor.animationsEnabled) ? 1 : 0, // 23
            compositor ? Math.round(compositor.springStiffness) : 260, // 24
            compositor ? Math.round(compositor.springDamping) : 23, // 25
            (compositor && compositor.blurEnabled) ? 1 : 0, // 26
            compositor ? Math.round(compositor.blurSize) : 6, // 27
            compositor ? Math.round(compositor.blurPasses) : 2, // 28
            _fmtNum(compositor ? compositor.blurVibrancy : 0.12), // 29
            transIdx, // 30: bgLayer.transitionMode
            bgLayer ? Math.max(0, Math.round(bgLayer.currentIndex)) : 0, // 31: wallpaper index
            root.customAccentActive ? 1 : 0, // 32: customAccentActive
            root.gooeyEnabled ? 1 : 0, // 33: gooeyEnabled
            _fmtNum(root.speedMultiplier), // 34: speedMultiplier
            cleanName // 35: embedded profile name
        ];

        const raw = vals.join(";");
        return { raw: raw, code: "PAISH1:" + _b64UrlEncode(raw) };
    }

    function decodeState(input) {
        if (!input || typeof input !== "string") return null;
        let raw = input.trim();
        if (raw.indexOf("PAISH1:") === 0) {
            raw = _b64UrlDecode(raw.slice(7).replace(/=+$/, ""));
            if (!raw) return null;
        }
        const parts = raw.split(";");
        if (parts.length < 32) return null;
        const n = [];
        const lim = Math.min(parts.length, 35);
        for (let i = 0; i < lim; ++i) {
            const v = Number(parts[i]);
            if (isNaN(v) || !isFinite(v)) return null;
            n.push(v);
        }
        if (Math.round(n[0]) !== 1) return null;

        const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
        const radVal = Math.round(n[3]);
        const islandRadStr = radVal <= 12 ? "12px" : (radVal <= 18 ? "18px" : "26px (Default)");
        const hue = clamp(n[9], 0, 1);
        const sat = clamp(n[10], 0, 1);
        const val = clamp(n[11], 0, 1);
        const hasExplicitCustom = n.length >= 33;

        return {
            presetName: presetNames[clamp(Math.round(n[1]), 0, presetNames.length - 1)],
            globalSurfaceTheme: surfaceThemeNames[clamp(Math.round(n[2]), 0, surfaceThemeNames.length - 1)],
            islandCornerRadius: islandRadStr,
            topEdgeOffset: n[4] >= 0.5,
            hideBarFullscreen: n[5] >= 0.5,
            autoHideOnOverlap: n[6] >= 0.5,
            activeBorderHighlight: n[7] >= 0.5,
            accentMode: n[8] >= 0.5 ? "Gradient" : "Solid",
            hueVal: hue,
            satVal: sat,
            valVal: val,
            gradientAngle: clamp(Math.round(n[12]), 0, 360),
            gapsIn: clamp(Math.round(n[13]), 0, 32),
            gapsOut: clamp(Math.round(n[14]), 0, 48),
            borderSize: clamp(Math.round(n[15]), 0, 6),
            layoutName: n[16] >= 0.5 ? "master" : "dwindle",
            masterRatio: clamp(Math.round(n[17]), 30, 80),
            preserveSplit: n[18] >= 0.5,
            cornerRounding: clamp(Math.round(n[19]), 0, 28),
            shadowEnabled: n[20] >= 0.5,
            inactiveOpacity: clamp(n[21], 0.6, 1.0),
            shadowRange: clamp(Math.round(n[22]), 0, 48),
            animationsEnabled: n[23] >= 0.5,
            springStiffness: clamp(Math.round(n[24]), 80, 600),
            springDamping: clamp(Math.round(n[25]), 5, 60),
            blurEnabled: n[26] >= 0.5,
            blurSize: clamp(Math.round(n[27]), 1, 24),
            blurPasses: clamp(Math.round(n[28]), 1, 6),
            blurVibrancy: clamp(n[29], 0, 1),
            transitionMode: transitionModes[clamp(Math.round(n[30]), 0, transitionModes.length - 1)],
            wallpaperIndex: Math.max(0, Math.round(n[31])),
            customAccentActive: hasExplicitCustom ? (n[32] >= 0.5) : (sat > 0.001 || Math.abs(val - 0.92) > 0.01),
            gooeyEnabled: n.length >= 34 ? (n[33] >= 0.5) : null,
            speedMultiplier: n.length >= 35 ? clamp(n[34], 0.5, 2.5) : null,
            profileName: (parts.length >= 36 && parts[35].trim() !== "") ? parts[35].trim().replace(/[^a-zA-Z0-9._-]/g, "_") : ""
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
