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
    property string surfaceTheme: "OLED Pure"
    property string accentMode: "Solid"
    readonly property bool accentGradientEnabled: accentMode === "Gradient"
    property real hueVal: 0.0
    property real satVal: 0.0
    property real valVal: 0.92
    property int gradientAngle: 135
    property int masterRatio: 55
    property bool preserveSplit: true
    property int shadowRange: 24
    property bool customAccentActive: false

    // Custom Palette & Gradient State
    property bool customPaletteActive: false
    property bool hasCustomPillBg: false
    property string customPillBg: ""
    property bool hasCustomSurfaceBg: false
    property string customSurfaceBg: ""
    property bool hasCustomSurfaceRaised: false
    property string customSurfaceRaised: ""
    property bool hasCustomText: false
    property string customText: ""
    property bool hasCustomBorderColor: false
    property string customBorderColor: ""

    property bool shellGradientEnabled: false
    property color pillBg2: "#0e0e0e"
    property bool surfaceGradientEnabled: false
    property color surfaceBg2: "#18181a"
    property bool customAccent2Active: false
    property color accent2: "#cccccc"
    property bool _suppressColorSignal: false

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
            borderAlpha: 0.14,
            shellGradient: false,
            surfaceGradient: false,
            accentGradient: false
        },
        {
            name: "Nord Frost",
            subtitle: "Frost gradient • 16px • Blur 9px",
            shortDesc: "Cool Slate • Frost Gradient",
            surfaceTheme: "Adaptive",
            compositorKey: "ocean",
            previewBg: "#1a1f29",
            previewAccent: "#88c0d0",
            pillBg: "#1a1f29",
            pillBg2: "#222b3b",
            surfaceBg: "#212734",
            surfaceBg2: "#273142",
            surfaceRaised: "#293040",
            text: "#eceff4",
            accent: "#88c0d0",
            accent2: "#81a1c1",
            accentFg: "#141a24",
            cardAlpha: 0.09,
            hoverAlpha: 0.15,
            borderAlpha: 0.18,
            shellGradient: true,
            surfaceGradient: true,
            accentGradient: true,
            gradientAngle: 135
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
            borderAlpha: 0.16,
            shellGradient: false,
            surfaceGradient: false,
            accentGradient: false
        },
        {
            name: "Catppuccin Mocha",
            subtitle: "Mauve gradient • 16px • Blur 10px",
            shortDesc: "Pastel Mauve • Dusk Gradient",
            surfaceTheme: "Adaptive",
            compositorKey: "ocean",
            previewBg: "#1e1e2e",
            previewAccent: "#cba6f7",
            pillBg: "#1e1e2e",
            pillBg2: "#28263d",
            surfaceBg: "#181825",
            surfaceBg2: "#232136",
            surfaceRaised: "#313244",
            text: "#cdd6f4",
            accent: "#cba6f7",
            accent2: "#89b4fa",
            accentFg: "#11111b",
            cardAlpha: 0.09,
            hoverAlpha: 0.15,
            borderAlpha: 0.18,
            shellGradient: true,
            surfaceGradient: true,
            accentGradient: true,
            gradientAngle: 135
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
            borderAlpha: 0.16,
            shellGradient: false,
            surfaceGradient: false,
            accentGradient: false
        },
        {
            name: "Adaptive",
            subtitle: "Teal gradient • 16px • Blur 8px",
            shortDesc: "Deep Teal • Ocean Gradient",
            surfaceTheme: "Adaptive",
            compositorKey: "adaptive",
            previewBg: "#0d1216",
            previewAccent: "#80cbc4",
            pillBg: "#0d1216",
            pillBg2: "#131e24",
            surfaceBg: "#10161c",
            surfaceBg2: "#162229",
            surfaceRaised: "#161e26",
            text: "#edf6f5",
            accent: "#80cbc4",
            accent2: "#4db6ac",
            accentFg: "#071a18",
            cardAlpha: 0.09,
            hoverAlpha: 0.15,
            borderAlpha: 0.16,
            shellGradient: true,
            surfaceGradient: true,
            accentGradient: true,
            gradientAngle: 125
        }
    ]

    signal presetApplied(string name)
    signal themeColorsChanged()

    Component.onCompleted: rebuildPalette(false)

    function presetMeta(name) {
        for (let i = 0; i < presetCatalog.length; ++i) {
            if (presetCatalog[i].name === name) return presetCatalog[i];
        }
        return null;
    }

    function _byteHex(n) {
        const clamped = Math.max(0, Math.min(255, Math.round(n)));
        const s = clamped.toString(16);
        return s.length < 2 ? "0" + s : s;
    }

    function colorToHex(c) {
        const col = Qt.color(c);
        return "#" + _byteHex(col.r * 255) + _byteHex(col.g * 255) + _byteHex(col.b * 255);
    }

    function normalizeHex(str, fallback) {
        const fb = (fallback !== undefined) ? String(fallback) : "";
        const raw = String(str || "").trim();
        const m = raw.match(/^#?([0-9a-fA-F]{6})$/);
        if (!m) return fb;
        return "#" + m[1].toLowerCase();
    }

    function hexToColor(hex) {
        const norm = normalizeHex(hex, "#000000");
        const r = parseInt(norm.slice(1, 3), 16) / 255.0;
        const g = parseInt(norm.slice(3, 5), 16) / 255.0;
        const b = parseInt(norm.slice(5, 7), 16) / 255.0;
        return Qt.rgba(r, g, b, 1.0);
    }

    function computeLuminance(c) {
        const col = Qt.color(c);
        return 0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b;
    }

    function contrastFg(c) {
        return computeLuminance(c) > 0.52 ? "#000000" : "#ffffff";
    }

    function deriveRaised(bgColor) {
        const c = Qt.color(bgColor);
        if (computeLuminance(c) < 0.5) {
            return Qt.rgba(Math.min(1, c.r + 0.045), Math.min(1, c.g + 0.045), Math.min(1, c.b + 0.052), 1.0);
        }
        return Qt.darker(c, 1.07);
    }

    function deriveHarmonyStop(baseColor, hueShiftDeg, valDelta) {
        const c = Qt.color(baseColor);
        const s = Math.max(0, c.hslSaturation);
        let l = Math.max(0, Math.min(1, c.hslLightness));
        if (s < 0.05) {
            const delta = Math.abs(valDelta) > 0.001 ? valDelta : (l > 0.6 ? -0.20 : 0.16);
            l = Math.max(0.04, Math.min(0.92, l + delta));
            return Qt.hsla(0.0, 0.0, l, 1.0);
        }
        const h = ((c.hslHue >= 0 ? c.hslHue : 0) + hueShiftDeg / 360.0 + 1.0) % 1.0;
        l = Math.max(0.04, Math.min(0.92, l + valDelta));
        return Qt.hsla(h, s, l, 1.0);
    }

    function surfaceAlphas(mode, presetObj) {
        if (presetObj && mode === presetObj.surfaceTheme) {
            return { card: presetObj.cardAlpha, hover: presetObj.hoverAlpha, border: presetObj.borderAlpha };
        }
        if (mode === "Mica Dark") return { card: 0.10, hover: 0.17, border: 0.18 };
        if (mode === "Adaptive") return { card: 0.09, hover: 0.15, border: 0.17 };
        return { card: 0.08, hover: 0.14, border: 0.14 };
    }

    function rebuildPalette(emitSignal) {
        const p = presetMeta(root.activePreset) || root.presetCatalog[0];
        const normPill = root.hasCustomPillBg ? normalizeHex(root.customPillBg, "") : "";
        const normSurf = root.hasCustomSurfaceBg ? normalizeHex(root.customSurfaceBg, "") : "";
        const normRaised = root.hasCustomSurfaceRaised ? normalizeHex(root.customSurfaceRaised, "") : "";
        const normText = root.hasCustomText ? normalizeHex(root.customText, "") : "";
        const normBorder = root.hasCustomBorderColor ? normalizeHex(root.customBorderColor, "") : "";

        root.pillBg = normPill !== "" ? hexToColor(normPill) : hexToColor(p.pillBg);
        root.surfaceBg = normSurf !== "" ? hexToColor(normSurf) : hexToColor(p.surfaceBg);
        root.surfaceRaised = normRaised !== ""
            ? hexToColor(normRaised)
            : (normSurf !== "" ? deriveRaised(root.surfaceBg) : hexToColor(p.surfaceRaised));
        root.text = normText !== "" ? hexToColor(normText) : hexToColor(p.text);

        if (root.customAccentActive) {
            root.accent = Qt.hsva(root.hueVal, root.satVal, root.valVal, 1.0);
        } else {
            root.accent = hexToColor(p.accent);
        }

        if (!root.customAccent2Active) {
            root.accent2 = (!root.customAccentActive && p.accent2)
                ? hexToColor(p.accent2)
                : deriveHarmonyStop(root.accent, 32, 0.0);
        }

        if (root.accentGradientEnabled) {
            const a1 = Qt.color(root.accent);
            const a2 = Qt.color(root.accent2);
            const mid = Qt.rgba((a1.r + a2.r) * 0.5, (a1.g + a2.g) * 0.5, (a1.b + a2.b) * 0.5, 1.0);
            root.accentFg = contrastFg(mid);
        } else if (root.customAccentActive) {
            root.accentFg = contrastFg(root.accent);
        } else {
            root.accentFg = hexToColor(p.accentFg);
        }

        const al = surfaceAlphas(root.surfaceTheme, p);
        root.textSub = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.62);
        root.textMuted = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.45);
        root.cardBg = Qt.rgba(root.text.r, root.text.g, root.text.b, al.card);
        root.cardHover = Qt.rgba(root.text.r, root.text.g, root.text.b, al.hover);
        const borderBase = normBorder !== "" ? hexToColor(normBorder) : root.text;
        root.borderSubtle = Qt.rgba(borderBase.r, borderBase.g, borderBase.b, al.border);
        root.customPaletteActive = (normPill !== "" || normSurf !== "" || normRaised !== "" || normText !== "" || normBorder !== "");

        if (emitSignal !== false && !root._suppressColorSignal) {
            root.themeColorsChanged();
        }
    }

    function applySurfaceTheme(name) {
        const valid = (name === "OLED Pure" || name === "Mica Dark" || name === "Adaptive") ? name : "OLED Pure";
        root.surfaceTheme = valid;
        rebuildPalette(true);
    }

    function applyAccentHsv(h, s, v) {
        root.hueVal = Math.max(0, Math.min(1, Number(h) || 0));
        root.satVal = Math.max(0, Math.min(1, Number(s) || 0));
        root.valVal = Math.max(0, Math.min(1, Number(v) || 0));
        root.customAccentActive = true;
        rebuildPalette(true);
    }

    function setPaletteColor(slot, hexOrColor) {
        const hex = (typeof hexOrColor === "string")
            ? normalizeHex(hexOrColor, "")
            : ((hexOrColor && hexOrColor.r !== undefined) ? colorToHex(hexOrColor) : "");
        if (hex === "") return false;
        const c = hexToColor(hex);
        if (slot === "pillBg") {
            root.hasCustomPillBg = true;
            root.customPillBg = hex;
            if (!root.shellGradientEnabled) root.pillBg2 = deriveHarmonyStop(c, 16, 0.055);
        } else if (slot === "pillBg2") {
            root.pillBg2 = c;
            root.shellGradientEnabled = true;
        } else if (slot === "surfaceBg") {
            root.hasCustomSurfaceBg = true;
            root.customSurfaceBg = hex;
            if (!root.surfaceGradientEnabled) root.surfaceBg2 = deriveHarmonyStop(c, 14, 0.05);
        } else if (slot === "surfaceBg2") {
            root.surfaceBg2 = c;
            root.surfaceGradientEnabled = true;
        } else if (slot === "accent") {
            root.hueVal = c.hsvHue >= 0 ? c.hsvHue : 0;
            root.satVal = c.hsvSaturation;
            root.valVal = c.hsvValue;
            root.customAccentActive = true;
        } else if (slot === "accent2") {
            root.accent2 = c;
            root.customAccent2Active = true;
            root.accentMode = "Gradient";
        } else if (slot === "surfaceRaised") {
            root.hasCustomSurfaceRaised = true;
            root.customSurfaceRaised = hex;
        } else if (slot === "text") {
            root.hasCustomText = true;
            root.customText = hex;
        } else if (slot === "borderColor") {
            root.hasCustomBorderColor = true;
            root.customBorderColor = hex;
        } else {
            return false;
        }
        rebuildPalette(true);
        return true;
    }

    function clearPaletteOverride(slot) {
        if (slot === "pillBg") {
            root.hasCustomPillBg = false;
            root.customPillBg = "";
        } else if (slot === "surfaceBg") {
            root.hasCustomSurfaceBg = false;
            root.customSurfaceBg = "";
        } else if (slot === "surfaceRaised") {
            root.hasCustomSurfaceRaised = false;
            root.customSurfaceRaised = "";
        } else if (slot === "text") {
            root.hasCustomText = false;
            root.customText = "";
        } else if (slot === "borderColor") {
            root.hasCustomBorderColor = false;
            root.customBorderColor = "";
        } else if (slot === "accent") {
            root.customAccentActive = false;
            root.hueVal = 0.0;
            root.satVal = 0.0;
            root.valVal = 0.92;
        } else if (slot === "accent2") {
            root.customAccent2Active = false;
        } else if (slot === "pillBg2") {
            root.pillBg2 = deriveHarmonyStop(root.pillBg, 16, 0.055);
        } else if (slot === "surfaceBg2") {
            root.surfaceBg2 = deriveHarmonyStop(root.surfaceBg, 14, 0.05);
        } else {
            return false;
        }
        rebuildPalette(true);
        return true;
    }

    function setGradientFlags(shellOn, surfaceOn, accentOn) {
        const sOn = Boolean(shellOn);
        const fOn = Boolean(surfaceOn);
        const aOn = Boolean(accentOn);
        if (sOn && !root.shellGradientEnabled && colorToHex(root.pillBg2) === colorToHex(root.pillBg)) {
            root.pillBg2 = deriveHarmonyStop(root.pillBg, 16, 0.055);
        }
        if (fOn && !root.surfaceGradientEnabled && colorToHex(root.surfaceBg2) === colorToHex(root.surfaceBg)) {
            root.surfaceBg2 = deriveHarmonyStop(root.surfaceBg, 14, 0.05);
        }
        root.shellGradientEnabled = sOn;
        root.surfaceGradientEnabled = fOn;
        root.accentMode = aOn ? "Gradient" : "Solid";
        rebuildPalette(true);
    }

    function setGradientAngle(deg) {
        const next = Math.max(0, Math.min(360, Math.round(Number(deg) || 0)));
        if (root.gradientAngle === next) return;
        root.gradientAngle = next;
        rebuildPalette(true);
    }

    function getSlotHex(slot) {
        if (slot === "pillBg") return colorToHex(root.pillBg);
        if (slot === "pillBg2") return colorToHex(root.pillBg2);
        if (slot === "surfaceBg") return colorToHex(root.surfaceBg);
        if (slot === "surfaceBg2") return colorToHex(root.surfaceBg2);
        if (slot === "accent") return colorToHex(root.accent);
        if (slot === "accent2") return colorToHex(root.accent2);
        if (slot === "surfaceRaised") return colorToHex(root.surfaceRaised);
        if (slot === "text") return colorToHex(root.text);
        if (slot === "borderColor") {
            const norm = root.hasCustomBorderColor ? normalizeHex(root.customBorderColor, "") : "";
            return norm !== "" ? norm : colorToHex(root.text);
        }
        return "#ffffff";
    }

    function applyPreset(name) {
        const p = presetMeta(name);
        if (!p) return false;
        root.activePreset = name;
        root.surfaceTheme = p.surfaceTheme;
        root.customAccentActive = false;
        root.customAccent2Active = false;
        root.accentMode = p.accentGradient ? "Gradient" : "Solid";
        root.hueVal = 0;
        root.satVal = 0;
        root.valVal = 0.92;
        root.hasCustomPillBg = false;
        root.customPillBg = "";
        root.hasCustomSurfaceBg = false;
        root.customSurfaceBg = "";
        root.hasCustomSurfaceRaised = false;
        root.customSurfaceRaised = "";
        root.hasCustomText = false;
        root.customText = "";
        root.hasCustomBorderColor = false;
        root.customBorderColor = "";
        root.customPaletteActive = false;
        root.shellGradientEnabled = Boolean(p.shellGradient);
        root.surfaceGradientEnabled = Boolean(p.surfaceGradient);
        root.gradientAngle = (p.gradientAngle !== undefined) ? p.gradientAngle : 135;
        root.pillBg2 = p.pillBg2 ? hexToColor(p.pillBg2) : deriveHarmonyStop(p.pillBg, 16, 0.055);
        root.surfaceBg2 = p.surfaceBg2 ? hexToColor(p.surfaceBg2) : deriveHarmonyStop(p.surfaceBg, 14, 0.05);
        root.accent2 = p.accent2 ? hexToColor(p.accent2) : deriveHarmonyStop(p.accent, 32, 0.0);
        rebuildPalette(false);
        root.presetApplied(name);
        if (!root._suppressColorSignal) root.themeColorsChanged();
        return true;
    }

    function exportPaletteState() {
        return {
            surfaceTheme: root.surfaceTheme,
            customAccentActive: Boolean(root.customAccentActive),
            accentMode: root.accentMode,
            hueVal: root.hueVal,
            satVal: root.satVal,
            valVal: root.valVal,
            gradientAngle: Math.round(root.gradientAngle),
            shellGradientEnabled: Boolean(root.shellGradientEnabled),
            pillBg2: colorToHex(root.pillBg2),
            surfaceGradientEnabled: Boolean(root.surfaceGradientEnabled),
            surfaceBg2: colorToHex(root.surfaceBg2),
            customAccent2Active: Boolean(root.customAccent2Active),
            accent2: colorToHex(root.accent2),
            customPaletteActive: Boolean(root.customPaletteActive),
            hasCustomPillBg: Boolean(root.hasCustomPillBg),
            customPillBg: root.hasCustomPillBg ? normalizeHex(root.customPillBg, "") : "",
            hasCustomSurfaceBg: Boolean(root.hasCustomSurfaceBg),
            customSurfaceBg: root.hasCustomSurfaceBg ? normalizeHex(root.customSurfaceBg, "") : "",
            hasCustomSurfaceRaised: Boolean(root.hasCustomSurfaceRaised),
            customSurfaceRaised: root.hasCustomSurfaceRaised ? normalizeHex(root.customSurfaceRaised, "") : "",
            hasCustomText: Boolean(root.hasCustomText),
            customText: root.hasCustomText ? normalizeHex(root.customText, "") : "",
            hasCustomBorderColor: Boolean(root.hasCustomBorderColor),
            customBorderColor: root.hasCustomBorderColor ? normalizeHex(root.customBorderColor, "") : ""
        };
    }

    function applyPaletteState(obj) {
        if (!obj || typeof obj !== "object") return false;
        const prevSuppress = root._suppressColorSignal;
        root._suppressColorSignal = true;

        const surfTheme = obj.surfaceTheme || obj.globalSurfaceTheme;
        if (typeof surfTheme === "string" && (surfTheme === "OLED Pure" || surfTheme === "Mica Dark" || surfTheme === "Adaptive")) {
            root.surfaceTheme = surfTheme;
        }
        if (typeof obj.accentMode === "string") root.accentMode = obj.accentMode === "Gradient" ? "Gradient" : "Solid";
        if (typeof obj.gradientAngle === "number") root.gradientAngle = Math.max(0, Math.min(360, Math.round(obj.gradientAngle)));

        if (obj.customAccentActive === true) {
            root.hueVal = Math.max(0, Math.min(1, Number(obj.hueVal) || 0));
            root.satVal = Math.max(0, Math.min(1, Number(obj.satVal) || 0));
            root.valVal = Math.max(0, Math.min(1, Number(obj.valVal) || 0));
            root.customAccentActive = true;
        } else {
            root.customAccentActive = false;
            if (typeof obj.hueVal === "number") root.hueVal = obj.hueVal;
            if (typeof obj.satVal === "number") root.satVal = obj.satVal;
            if (typeof obj.valVal === "number") root.valVal = obj.valVal;
        }

        const cPill = normalizeHex(obj.customPillBg, "");
        root.hasCustomPillBg = (obj.hasCustomPillBg !== undefined ? Boolean(obj.hasCustomPillBg) : cPill !== "") && cPill !== "";
        root.customPillBg = root.hasCustomPillBg ? cPill : "";

        const cSurf = normalizeHex(obj.customSurfaceBg, "");
        root.hasCustomSurfaceBg = (obj.hasCustomSurfaceBg !== undefined ? Boolean(obj.hasCustomSurfaceBg) : cSurf !== "") && cSurf !== "";
        root.customSurfaceBg = root.hasCustomSurfaceBg ? cSurf : "";

        const cRaised = normalizeHex(obj.customSurfaceRaised, "");
        root.hasCustomSurfaceRaised = (obj.hasCustomSurfaceRaised !== undefined ? Boolean(obj.hasCustomSurfaceRaised) : cRaised !== "") && cRaised !== "";
        root.customSurfaceRaised = root.hasCustomSurfaceRaised ? cRaised : "";

        const cText = normalizeHex(obj.customText, "");
        root.hasCustomText = (obj.hasCustomText !== undefined ? Boolean(obj.hasCustomText) : cText !== "") && cText !== "";
        root.customText = root.hasCustomText ? cText : "";

        const cBorder = normalizeHex(obj.customBorderColor, "");
        root.hasCustomBorderColor = (obj.hasCustomBorderColor !== undefined ? Boolean(obj.hasCustomBorderColor) : cBorder !== "") && cBorder !== "";
        root.customBorderColor = root.hasCustomBorderColor ? cBorder : "";

        root.shellGradientEnabled = Boolean(obj.shellGradientEnabled);
        const p2 = normalizeHex(obj.pillBg2, "");
        if (p2 !== "") root.pillBg2 = hexToColor(p2);

        root.surfaceGradientEnabled = Boolean(obj.surfaceGradientEnabled);
        const s2 = normalizeHex(obj.surfaceBg2, "");
        if (s2 !== "") root.surfaceBg2 = hexToColor(s2);

        const a2 = normalizeHex(obj.accent2, "");
        root.customAccent2Active = Boolean(obj.customAccent2Active) && a2 !== "";
        if (root.customAccent2Active) root.accent2 = hexToColor(a2);

        rebuildPalette(false);

        if (p2 === "" || (!root.shellGradientEnabled && obj.pillBg2 === undefined)) {
            root.pillBg2 = deriveHarmonyStop(root.pillBg, 16, 0.055);
        }
        if (s2 === "" || (!root.surfaceGradientEnabled && obj.surfaceBg2 === undefined)) {
            root.surfaceBg2 = deriveHarmonyStop(root.surfaceBg, 14, 0.05);
        }

        root._suppressColorSignal = prevSuppress;
        if (!root._suppressColorSignal) root.themeColorsChanged();
        return true;
    }

    function loadBundle(jsonStr) {
        try {
            const obj = JSON.parse(jsonStr);
            if (!obj || typeof obj !== "object") return false;
            const colors = obj.palette && obj.palette.colors ? obj.palette.colors : obj.colors;
            if (Array.isArray(colors) && colors.length >= 2) {
                setPaletteColor("pillBg", colors[0]);
                setPaletteColor("text", colors[1]);
                setPaletteColor("accent", colors[1]);
                if (colors.length >= 3) {
                    setPaletteColor("surfaceBg", colors[2]);
                    setPaletteColor("surfaceRaised", colors[2]);
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
            globalSurfaceTheme: stateObj ? stateObj.globalSurfaceTheme : root.surfaceTheme,
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
            profileName: effectiveName,
            // 7. v3 Extended Colors & Gradients
            shellGradientEnabled: Boolean(root.shellGradientEnabled),
            pillBg2: colorToHex(root.pillBg2),
            surfaceGradientEnabled: Boolean(root.surfaceGradientEnabled),
            surfaceBg2: colorToHex(root.surfaceBg2),
            customAccent2Active: Boolean(root.customAccent2Active),
            accent2: colorToHex(root.accent2),
            customPaletteActive: Boolean(root.customPaletteActive),
            customPillBg: root.hasCustomPillBg ? normalizeHex(root.customPillBg, "") : "",
            customSurfaceBg: root.hasCustomSurfaceBg ? normalizeHex(root.customSurfaceBg, "") : "",
            customSurfaceRaised: root.hasCustomSurfaceRaised ? normalizeHex(root.customSurfaceRaised, "") : "",
            customText: root.hasCustomText ? normalizeHex(root.customText, "") : "",
            customBorderColor: root.hasCustomBorderColor ? normalizeHex(root.customBorderColor, "") : ""
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
