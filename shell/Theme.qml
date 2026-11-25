pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    // Core Monochrome OLED Palette (live rendered tokens — smoothly blended in OKLab)
    property color pillBg: "#000000"
    property color pillBgMid: "#000000"
    property color surfaceBg: "#0b0b0c"
    property color surfaceBgMid: "#0b0b0c"
    property color surfaceRaised: "#101012"
    property color cardBg: Qt.rgba(1, 1, 1, 0.08)
    property color cardHover: Qt.rgba(1, 1, 1, 0.14)
    property color borderSubtle: Qt.rgba(1, 1, 1, 0.14)
    property color text: "#ffffff"
    property color textSub: Qt.rgba(1, 1, 1, 0.60)
    property color textMuted: Qt.rgba(1, 1, 1, 0.45)
    property color accent: "#ffffff"
    property color accentMid: "#ffffff"
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

    // Extended Personalization State (manual backing state — preserved across wallpaper mode & .paish)
    property string surfaceTheme: "OLED Pure"
    property string accentMode: "Solid"
    property bool accentGradientEnabled: false
    property real hueVal: 0.0
    property real satVal: 0.0
    property real valVal: 0.92
    property int gradientAngle: 135
    property int masterRatio: 55
    property bool preserveSplit: true
    property int shadowRange: 24
    property bool customAccentActive: false

    // Custom Palette & Gradient State (manual backing state)
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

    // Preserved Manual Backing Fields (never overwritten by wallpaper color extraction)
    property bool manualShellGradientEnabled: false
    property bool manualSurfaceGradientEnabled: false
    property string manualAccentMode: "Solid"
    property color manualPillBg2: "#0e0e0e"
    property color manualSurfaceBg2: "#18181a"
    property color manualAccent2: "#cccccc"
    property int manualGradientAngle: 135

    // "Adjust colors based on what you see" (Wallpaper-Adaptive Theme)
    property bool wallpaperColorEnabled: false
    property string wallpaperColorMode: "Solid" // "Solid" | "Gradient"
    property string wallpaperColorSourcePath: ""
    property var wallpaperExtractedColors: []
    property var wallpaperRefinedPalette: []
    property bool wallpaperColorBusy: false
    property var _wallpaperPaletteObj: null

    // Internal OKLab Blender State
    property bool _suppressColorSignal: false
    property int targetGradientAngle: 135
    property real blendProgress: 1.0
    property var _fromLab: null
    property var _toLab: null
    property var _blendDirty: null
    property double _lastBlendTickMs: 0
    property var _targetPalette: null
    property color _liveBorderBase: "#ffffff"
    property real _liveCardAlpha: 0.08
    property real _liveHoverAlpha: 0.14
    property real _liveBorderAlpha: 0.14

    property NumberAnimation _blendAnim: NumberAnimation {
        target: root
        property: "blendProgress"
        from: 0.0
        to: 1.0
        duration: Math.max(180, Math.round(280 / Math.max(0.5, root.speedMultiplier)))
        easing.type: Easing.OutCubic
        onFinished: root._finishBlend()
    }

    function _labDiffers(a, b) {
        return Math.abs(a[0] - b[0]) > 0.002 || Math.abs(a[1] - b[1]) > 0.002 || Math.abs(a[2] - b[2]) > 0.002;
    }

    function _arraysEqual(a, b) {
        if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
        for (let i = 0; i < a.length; ++i) {
            if (a[i] !== b[i]) return false;
        }
        return true;
    }

    onBlendProgressChanged: {
        if (!_fromLab || !_toLab || !_blendDirty) return;
        const t = blendProgress;
        if (t < 0.999) {
            const now = Date.now();
            if (now - _lastBlendTickMs < 32) return;
            _lastBlendTickMs = now;
        }
        const f = _fromLab;
        const g = _toLab;
        const d = _blendDirty;

        if (d.pillBg) root.pillBg = _lerpLabColor(f.pillBg, g.pillBg, t);
        if (d.pillBgMid) root.pillBgMid = _lerpLabColor(f.pillBgMid, g.pillBgMid, t);
        if (d.pillBg2) root.pillBg2 = _lerpLabColor(f.pillBg2, g.pillBg2, t);
        if (d.surfaceBg) root.surfaceBg = _lerpLabColor(f.surfaceBg, g.surfaceBg, t);
        if (d.surfaceBgMid) root.surfaceBgMid = _lerpLabColor(f.surfaceBgMid, g.surfaceBgMid, t);
        if (d.surfaceBg2) root.surfaceBg2 = _lerpLabColor(f.surfaceBg2, g.surfaceBg2, t);
        if (d.surfaceRaised) root.surfaceRaised = _lerpLabColor(f.surfaceRaised, g.surfaceRaised, t);
        if (d.text) root.text = _lerpLabColor(f.text, g.text, t);
        if (d.accent) root.accent = _lerpLabColor(f.accent, g.accent, t);
        if (d.accentMid) root.accentMid = _lerpLabColor(f.accentMid, g.accentMid, t);
        if (d.accent2) root.accent2 = _lerpLabColor(f.accent2, g.accent2, t);
        if (d.accentFg) root.accentFg = _lerpLabColor(f.accentFg, g.accentFg, t);
        if (d.borderBase) root._liveBorderBase = _lerpLabColor(f.borderBase, g.borderBase, t);

        if (d.cardAlpha) root._liveCardAlpha = f.cardAlpha + (g.cardAlpha - f.cardAlpha) * t;
        if (d.hoverAlpha) root._liveHoverAlpha = f.hoverAlpha + (g.hoverAlpha - f.hoverAlpha) * t;
        if (d.borderAlpha) root._liveBorderAlpha = f.borderAlpha + (g.borderAlpha - f.borderAlpha) * t;
        if (d.gradientAngle) root.gradientAngle = _lerpAngle(f.gradientAngle, g.gradientAngle, t);

        if (d.text) {
            root.textSub = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.62);
            root.textMuted = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.45);
        }
        if (d.text || d.cardAlpha) {
            root.cardBg = Qt.rgba(root.text.r, root.text.g, root.text.b, root._liveCardAlpha);
        }
        if (d.text || d.hoverAlpha) {
            root.cardHover = Qt.rgba(root.text.r, root.text.g, root.text.b, root._liveHoverAlpha);
        }
        if (d.borderBase || d.borderAlpha) {
            root.borderSubtle = Qt.rgba(root._liveBorderBase.r, root._liveBorderBase.g, root._liveBorderBase.b, root._liveBorderAlpha);
        }
    }

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

    Component.onCompleted: rebuildPalette(false, false)

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

    function _midColor(c1, c2) {
        const a = Qt.color(c1);
        const b = Qt.color(c2);
        return Qt.rgba((a.r + b.r) * 0.5, (a.g + b.g) * 0.5, (a.b + b.b) * 0.5, 1.0);
    }

    function _srgbToLin(u) {
        const c = Math.max(0, Math.min(1, u));
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }

    function _linToSrgb(u) {
        const c = Math.max(0, Math.min(1, u));
        return c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1.0 / 2.4) - 0.055;
    }

    function _cbrt(x) {
        return x < 0 ? -Math.pow(-x, 1.0 / 3.0) : Math.pow(x, 1.0 / 3.0);
    }

    function _colorToOklab(c) {
        const col = Qt.color(c);
        const lr = _srgbToLin(col.r);
        const lg = _srgbToLin(col.g);
        const lb = _srgbToLin(col.b);
        const l = _cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
        const m = _cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
        const s = _cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
        return [
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        ];
    }

    function _oklabToColor(L, a, b) {
        const l_ = L + 0.3963377774 * a + 0.2158037573 * b;
        const m_ = L - 0.1055613458 * a - 0.0638541728 * b;
        const s_ = L - 0.0894841775 * a - 1.2914855480 * b;
        const l = l_ * l_ * l_;
        const m = m_ * m_ * m_;
        const s = s_ * s_ * s_;
        const lr = +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
        const lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
        const lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
        return Qt.rgba(_linToSrgb(lr), _linToSrgb(lg), _linToSrgb(lb), 1.0);
    }

    function _lerpLabColor(lab0, lab1, t) {
        return _oklabToColor(
            lab0[0] + (lab1[0] - lab0[0]) * t,
            lab0[1] + (lab1[1] - lab0[1]) * t,
            lab0[2] + (lab1[2] - lab0[2]) * t
        );
    }

    function _lerpAngle(a0, a1, t) {
        const delta = ((a1 - a0 + 540) % 360) - 180;
        return Math.round((a0 + delta * t + 360) % 360);
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

    function _refreshDerivedTokens() {
        root.textSub = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.62);
        root.textMuted = Qt.rgba(root.text.r, root.text.g, root.text.b, 0.45);
        root.cardBg = Qt.rgba(root.text.r, root.text.g, root.text.b, root._liveCardAlpha);
        root.cardHover = Qt.rgba(root.text.r, root.text.g, root.text.b, root._liveHoverAlpha);
        root.borderSubtle = Qt.rgba(root._liveBorderBase.r, root._liveBorderBase.g, root._liveBorderBase.b, root._liveBorderAlpha);
    }

    function _computeManualTargetPalette() {
        const p = presetMeta(root.activePreset) || root.presetCatalog[0];
        const normPill = root.hasCustomPillBg ? normalizeHex(root.customPillBg, "") : "";
        const normSurf = root.hasCustomSurfaceBg ? normalizeHex(root.customSurfaceBg, "") : "";
        const normRaised = root.hasCustomSurfaceRaised ? normalizeHex(root.customSurfaceRaised, "") : "";
        const normText = root.hasCustomText ? normalizeHex(root.customText, "") : "";
        const normBorder = root.hasCustomBorderColor ? normalizeHex(root.customBorderColor, "") : "";

        const tPill = normPill !== "" ? hexToColor(normPill) : hexToColor(p.pillBg);
        const tSurf = normSurf !== "" ? hexToColor(normSurf) : hexToColor(p.surfaceBg);
        const tRaised = normRaised !== ""
            ? hexToColor(normRaised)
            : (normSurf !== "" ? deriveRaised(tSurf) : hexToColor(p.surfaceRaised));
        const tText = normText !== "" ? hexToColor(normText) : hexToColor(p.text);

        const tAcc = root.customAccentActive
            ? Qt.hsva(root.hueVal, root.satVal, root.valVal, 1.0)
            : hexToColor(p.accent);
        const tAcc2 = root.customAccent2Active
            ? root.manualAccent2
            : ((!root.customAccentActive && p.accent2) ? hexToColor(p.accent2) : deriveHarmonyStop(tAcc, 32, 0.0));

        const accGradOn = root.manualAccentMode === "Gradient";
        let tAccFg;
        if (accGradOn) {
            const mid = _midColor(tAcc, tAcc2);
            tAccFg = hexToColor(contrastFg(mid));
        } else if (root.customAccentActive) {
            tAccFg = hexToColor(contrastFg(tAcc));
        } else {
            tAccFg = hexToColor(p.accentFg);
        }

        const tPill2 = root.manualPillBg2;
        const tSurf2 = root.manualSurfaceBg2;
        const al = surfaceAlphas(root.surfaceTheme, p);
        const tBorderBase = normBorder !== "" ? hexToColor(normBorder) : tText;

        root.customPaletteActive = (normPill !== "" || normSurf !== "" || normRaised !== "" || normText !== "" || normBorder !== "");

        return {
            pillBg: tPill,
            pillBgMid: _midColor(tPill, tPill2),
            pillBg2: tPill2,
            surfaceBg: tSurf,
            surfaceBgMid: _midColor(tSurf, tSurf2),
            surfaceBg2: tSurf2,
            surfaceRaised: tRaised,
            text: tText,
            accent: tAcc,
            accentMid: _midColor(tAcc, tAcc2),
            accent2: tAcc2,
            accentFg: tAccFg,
            borderBase: tBorderBase,
            cardAlpha: al.card,
            hoverAlpha: al.hover,
            borderAlpha: al.border,
            shellGradientEnabled: Boolean(root.manualShellGradientEnabled),
            surfaceGradientEnabled: Boolean(root.manualSurfaceGradientEnabled),
            accentGradientEnabled: Boolean(accGradOn),
            gradientAngle: Math.max(0, Math.min(360, Math.round(root.manualGradientAngle)))
        };
    }

    function _computeWallpaperTargetPalette() {
        const pal = root._wallpaperPaletteObj;
        const tPill = hexToColor(pal.pillBg);
        const tPillMid = hexToColor(pal.pillBgMid || pal.pillBg);
        const tPill2 = hexToColor(pal.pillBg2 || pal.pillBg);
        const tSurf = hexToColor(pal.surfaceBg);
        const tSurfMid = hexToColor(pal.surfaceBgMid || pal.surfaceBg);
        const tSurf2 = hexToColor(pal.surfaceBg2 || pal.surfaceBg);
        const tRaised = hexToColor(pal.surfaceRaised);
        const tText = hexToColor(pal.text);
        const tAcc = hexToColor(pal.accent);
        const tAccMid = hexToColor(pal.accentMid || pal.accent);
        const tAcc2 = hexToColor(pal.accent2 || pal.accent);
        const tAccFg = hexToColor(pal.accentFg || contrastFg(tAcc));
        const tBorder = hexToColor(pal.borderColor || pal.text);

        return {
            pillBg: tPill,
            pillBgMid: tPillMid,
            pillBg2: tPill2,
            surfaceBg: tSurf,
            surfaceBgMid: tSurfMid,
            surfaceBg2: tSurf2,
            surfaceRaised: tRaised,
            text: tText,
            accent: tAcc,
            accentMid: tAccMid,
            accent2: tAcc2,
            accentFg: tAccFg,
            borderBase: tBorder,
            cardAlpha: typeof pal.cardAlpha === "number" ? pal.cardAlpha : 0.09,
            hoverAlpha: typeof pal.hoverAlpha === "number" ? pal.hoverAlpha : 0.15,
            borderAlpha: typeof pal.borderAlpha === "number" ? pal.borderAlpha : 0.17,
            shellGradientEnabled: Boolean(pal.shellGradientEnabled),
            surfaceGradientEnabled: Boolean(pal.surfaceGradientEnabled),
            accentGradientEnabled: Boolean(pal.accentGradientEnabled),
            gradientAngle: typeof pal.gradientAngle === "number" ? Math.max(0, Math.min(360, Math.round(pal.gradientAngle))) : 135
        };
    }

    function _applyPaletteImmediate(target) {
        root.pillBg = target.pillBg;
        root.pillBgMid = target.pillBgMid;
        root.pillBg2 = target.pillBg2;
        root.surfaceBg = target.surfaceBg;
        root.surfaceBgMid = target.surfaceBgMid;
        root.surfaceBg2 = target.surfaceBg2;
        root.surfaceRaised = target.surfaceRaised;
        root.text = target.text;
        root.accent = target.accent;
        root.accentMid = target.accentMid;
        root.accent2 = target.accent2;
        root.accentFg = target.accentFg;
        root._liveBorderBase = target.borderBase;
        root._liveCardAlpha = target.cardAlpha;
        root._liveHoverAlpha = target.hoverAlpha;
        root._liveBorderAlpha = target.borderAlpha;
        root.shellGradientEnabled = target.shellGradientEnabled;
        root.surfaceGradientEnabled = target.surfaceGradientEnabled;
        root.accentGradientEnabled = target.accentGradientEnabled;
        root.gradientAngle = target.gradientAngle;
        root.targetGradientAngle = target.gradientAngle;
        _refreshDerivedTokens();
    }

    function _finishBlend() {
        root._fromLab = null;
        root._toLab = null;
        root._blendDirty = null;
        if (root._targetPalette) {
            _applyPaletteImmediate(root._targetPalette);
        }
    }

    function _commitPalette(target, animate) {
        root._targetPalette = target;
        root.targetGradientAngle = target.gradientAngle;
        if (!animate) {
            _blendAnim.stop();
            root._fromLab = null;
            root._toLab = null;
            root._blendDirty = null;
            _applyPaletteImmediate(target);
            root.blendProgress = 1.0;
            return;
        }

        const wasShellGrad = root.shellGradientEnabled;
        const wasSurfGrad = root.surfaceGradientEnabled;
        const wasAccGrad = root.accentGradientEnabled;

        // Snapshot current mid-blend colors cleanly for retargeting
        const curPill = root.pillBg;
        const curPillMid = wasShellGrad ? root.pillBgMid : curPill;
        const curPill2 = wasShellGrad ? root.pillBg2 : curPill;

        const curSurf = root.surfaceBg;
        const curSurfMid = wasSurfGrad ? root.surfaceBgMid : curSurf;
        const curSurf2 = wasSurfGrad ? root.surfaceBg2 : curSurf;

        const curAcc = root.accent;
        const curAccMid = wasAccGrad ? root.accentMid : curAcc;
        const curAcc2 = wasAccGrad ? root.accent2 : curAcc;

        const toPillMid = target.shellGradientEnabled ? target.pillBgMid : target.pillBg;
        const toPill2 = target.shellGradientEnabled ? target.pillBg2 : target.pillBg;

        const toSurfMid = target.surfaceGradientEnabled ? target.surfaceBgMid : target.surfaceBg;
        const toSurf2 = target.surfaceGradientEnabled ? target.surfaceBg2 : target.surfaceBg;

        const toAccMid = target.accentGradientEnabled ? target.accentMid : target.accent;
        const toAcc2 = target.accentGradientEnabled ? target.accent2 : target.accent;

        // Keep shader active across any Solid <-> Gradient transition; _finishBlend disables it when converging to Solid
        if (target.shellGradientEnabled || wasShellGrad) root.shellGradientEnabled = true;
        if (target.surfaceGradientEnabled || wasSurfGrad) root.surfaceGradientEnabled = true;
        if (target.accentGradientEnabled || wasAccGrad) root.accentGradientEnabled = true;

        _blendAnim.stop();
        const fromLab = {
            pillBg: _colorToOklab(curPill),
            pillBgMid: _colorToOklab(curPillMid),
            pillBg2: _colorToOklab(curPill2),
            surfaceBg: _colorToOklab(curSurf),
            surfaceBgMid: _colorToOklab(curSurfMid),
            surfaceBg2: _colorToOklab(curSurf2),
            surfaceRaised: _colorToOklab(root.surfaceRaised),
            text: _colorToOklab(root.text),
            accent: _colorToOklab(curAcc),
            accentMid: _colorToOklab(curAccMid),
            accent2: _colorToOklab(curAcc2),
            accentFg: _colorToOklab(root.accentFg),
            borderBase: _colorToOklab(root._liveBorderBase),
            cardAlpha: root._liveCardAlpha,
            hoverAlpha: root._liveHoverAlpha,
            borderAlpha: root._liveBorderAlpha,
            gradientAngle: root.gradientAngle
        };
        const toLab = {
            pillBg: _colorToOklab(target.pillBg),
            pillBgMid: _colorToOklab(toPillMid),
            pillBg2: _colorToOklab(toPill2),
            surfaceBg: _colorToOklab(target.surfaceBg),
            surfaceBgMid: _colorToOklab(toSurfMid),
            surfaceBg2: _colorToOklab(toSurf2),
            surfaceRaised: _colorToOklab(target.surfaceRaised),
            text: _colorToOklab(target.text),
            accent: _colorToOklab(target.accent),
            accentMid: _colorToOklab(toAccMid),
            accent2: _colorToOklab(toAcc2),
            accentFg: _colorToOklab(target.accentFg),
            borderBase: _colorToOklab(target.borderBase),
            cardAlpha: target.cardAlpha,
            hoverAlpha: target.hoverAlpha,
            borderAlpha: target.borderAlpha,
            gradientAngle: target.gradientAngle
        };
        const dirty = {
            pillBg: _labDiffers(fromLab.pillBg, toLab.pillBg),
            pillBgMid: _labDiffers(fromLab.pillBgMid, toLab.pillBgMid),
            pillBg2: _labDiffers(fromLab.pillBg2, toLab.pillBg2),
            surfaceBg: _labDiffers(fromLab.surfaceBg, toLab.surfaceBg),
            surfaceBgMid: _labDiffers(fromLab.surfaceBgMid, toLab.surfaceBgMid),
            surfaceBg2: _labDiffers(fromLab.surfaceBg2, toLab.surfaceBg2),
            surfaceRaised: _labDiffers(fromLab.surfaceRaised, toLab.surfaceRaised),
            text: _labDiffers(fromLab.text, toLab.text),
            accent: _labDiffers(fromLab.accent, toLab.accent),
            accentMid: _labDiffers(fromLab.accentMid, toLab.accentMid),
            accent2: _labDiffers(fromLab.accent2, toLab.accent2),
            accentFg: _labDiffers(fromLab.accentFg, toLab.accentFg),
            borderBase: _labDiffers(fromLab.borderBase, toLab.borderBase),
            cardAlpha: Math.abs(fromLab.cardAlpha - toLab.cardAlpha) > 0.002,
            hoverAlpha: Math.abs(fromLab.hoverAlpha - toLab.hoverAlpha) > 0.002,
            borderAlpha: Math.abs(fromLab.borderAlpha - toLab.borderAlpha) > 0.002,
            gradientAngle: Math.abs(fromLab.gradientAngle - toLab.gradientAngle) >= 1
        };
        let anyDirty = false;
        for (let k in dirty) {
            if (dirty[k]) { anyDirty = true; break; }
        }
        if (!anyDirty) {
            root._fromLab = null;
            root._toLab = null;
            root._blendDirty = null;
            _applyPaletteImmediate(target);
            root.blendProgress = 1.0;
            return;
        }
        root._fromLab = fromLab;
        root._toLab = toLab;
        root._blendDirty = dirty;
        root._lastBlendTickMs = 0;
        root.blendProgress = 0.0;
        _blendAnim.start();
    }

    function rebuildPalette(emitSignal, animate) {
        const manualTarget = _computeManualTargetPalette();
        const target = (root.wallpaperColorEnabled && root._wallpaperPaletteObj)
            ? _computeWallpaperTargetPalette()
            : manualTarget;
        _commitPalette(target, Boolean(animate));

        if (emitSignal !== false && !root._suppressColorSignal) {
            root.themeColorsChanged();
        }
    }

    function exportTargetRenderColors() {
        const t = root._targetPalette;
        if (!t) {
            return {
                pillBg: colorToHex(root.pillBg),
                pillBgMid: colorToHex(root.pillBgMid),
                pillBg2: colorToHex(root.pillBg2),
                surfaceBg: colorToHex(root.surfaceBg),
                surfaceBgMid: colorToHex(root.surfaceBgMid),
                surfaceBg2: colorToHex(root.surfaceBg2),
                surfaceRaised: colorToHex(root.surfaceRaised),
                text: colorToHex(root.text),
                borderColor: getSlotHex("borderColor"),
                accent: colorToHex(root.accent),
                accentMid: colorToHex(root.accentMid),
                accent2: colorToHex(root.accent2),
                accentFg: colorToHex(root.accentFg),
                shellGradientEnabled: Boolean(root.shellGradientEnabled),
                surfaceGradientEnabled: Boolean(root.surfaceGradientEnabled),
                accentGradientEnabled: Boolean(root.accentGradientEnabled),
                gradientAngle: Math.round(root.gradientAngle),
                borderAlpha: root._liveBorderAlpha
            };
        }
        return {
            pillBg: colorToHex(t.pillBg),
            pillBgMid: colorToHex(t.pillBgMid),
            pillBg2: colorToHex(t.pillBg2),
            surfaceBg: colorToHex(t.surfaceBg),
            surfaceBgMid: colorToHex(t.surfaceBgMid),
            surfaceBg2: colorToHex(t.surfaceBg2),
            surfaceRaised: colorToHex(t.surfaceRaised),
            text: colorToHex(t.text),
            borderColor: colorToHex(t.borderBase),
            accent: colorToHex(t.accent),
            accentMid: colorToHex(t.accentMid),
            accent2: colorToHex(t.accent2),
            accentFg: colorToHex(t.accentFg),
            shellGradientEnabled: Boolean(t.shellGradientEnabled),
            surfaceGradientEnabled: Boolean(t.surfaceGradientEnabled),
            accentGradientEnabled: Boolean(t.accentGradientEnabled),
            gradientAngle: Math.round(t.gradientAngle),
            borderAlpha: t.borderAlpha
        };
    }

    function setWallpaperColorEnabled(enabled, deferApply) {
        const next = Boolean(enabled);
        if (root.wallpaperColorEnabled === next) return;
        root.wallpaperColorEnabled = next;
        if (!next) {
            root.wallpaperColorBusy = false;
            rebuildPalette(true, true);
        } else if (!deferApply && root._wallpaperPaletteObj && root._wallpaperPaletteObj.mode === root.wallpaperColorMode) {
            rebuildPalette(true, true);
        } else if (!deferApply && !root._suppressColorSignal) {
            root.themeColorsChanged();
        }
    }

    function setWallpaperColorMode(mode) {
        const next = (String(mode || "").trim().toLowerCase() === "gradient") ? "Gradient" : "Solid";
        if (root.wallpaperColorMode === next) return;
        root.wallpaperColorMode = next;
    }

    function applyWallpaperPalette(resultObj, sourcePath, animate) {
        root.wallpaperColorBusy = false;
        if (!resultObj || !resultObj.ok || !resultObj.palette) return false;
        const ext = Array.isArray(resultObj.extractedColors) ? resultObj.extractedColors : [];
        const ref = Array.isArray(resultObj.refinedPalette) ? resultObj.refinedPalette : [];
        if (!_arraysEqual(root.wallpaperExtractedColors, ext)) root.wallpaperExtractedColors = ext;
        if (!_arraysEqual(root.wallpaperRefinedPalette, ref)) root.wallpaperRefinedPalette = ref;
        root.wallpaperColorSourcePath = String(sourcePath || "");
        const copyPal = Object.assign({}, resultObj.palette, { mode: resultObj.mode || root.wallpaperColorMode });
        root._wallpaperPaletteObj = copyPal;
        if (root.wallpaperColorEnabled) {
            rebuildPalette(true, animate !== false);
        }
        return true;
    }

    function applySurfaceTheme(name) {
        const valid = (name === "OLED Pure" || name === "Mica Dark" || name === "Adaptive") ? name : "OLED Pure";
        root.surfaceTheme = valid;
        rebuildPalette(true, false);
    }

    function applyAccentHsv(h, s, v) {
        root.hueVal = Math.max(0, Math.min(1, Number(h) || 0));
        root.satVal = Math.max(0, Math.min(1, Number(s) || 0));
        root.valVal = Math.max(0, Math.min(1, Number(v) || 0));
        root.customAccentActive = true;
        rebuildPalette(true, false);
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
            if (!root.manualShellGradientEnabled) root.manualPillBg2 = deriveHarmonyStop(c, 16, 0.055);
        } else if (slot === "pillBg2") {
            root.manualPillBg2 = c;
            root.manualShellGradientEnabled = true;
        } else if (slot === "surfaceBg") {
            root.hasCustomSurfaceBg = true;
            root.customSurfaceBg = hex;
            if (!root.manualSurfaceGradientEnabled) root.manualSurfaceBg2 = deriveHarmonyStop(c, 14, 0.05);
        } else if (slot === "surfaceBg2") {
            root.manualSurfaceBg2 = c;
            root.manualSurfaceGradientEnabled = true;
        } else if (slot === "accent") {
            root.hueVal = c.hsvHue >= 0 ? c.hsvHue : 0;
            root.satVal = c.hsvSaturation;
            root.valVal = c.hsvValue;
            root.customAccentActive = true;
        } else if (slot === "accent2") {
            root.manualAccent2 = c;
            root.customAccent2Active = true;
            root.manualAccentMode = "Gradient";
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
        rebuildPalette(true, false);
        return true;
    }

    function clearPaletteOverride(slot) {
        const p = presetMeta(root.activePreset) || root.presetCatalog[0];
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
            const baseP = root.hasCustomPillBg ? hexToColor(root.customPillBg) : hexToColor(p.pillBg);
            root.manualPillBg2 = deriveHarmonyStop(baseP, 16, 0.055);
        } else if (slot === "surfaceBg2") {
            const baseS = root.hasCustomSurfaceBg ? hexToColor(root.customSurfaceBg) : hexToColor(p.surfaceBg);
            root.manualSurfaceBg2 = deriveHarmonyStop(baseS, 14, 0.05);
        } else {
            return false;
        }
        rebuildPalette(true, false);
        return true;
    }

    function setGradientFlags(shellOn, surfaceOn, accentOn) {
        const sOn = Boolean(shellOn);
        const fOn = Boolean(surfaceOn);
        const aOn = Boolean(accentOn);
        const p = presetMeta(root.activePreset) || root.presetCatalog[0];
        const baseP = root.hasCustomPillBg ? hexToColor(root.customPillBg) : hexToColor(p.pillBg);
        const baseS = root.hasCustomSurfaceBg ? hexToColor(root.customSurfaceBg) : hexToColor(p.surfaceBg);
        if (sOn && !root.manualShellGradientEnabled && colorToHex(root.manualPillBg2) === colorToHex(baseP)) {
            root.manualPillBg2 = deriveHarmonyStop(baseP, 16, 0.055);
        }
        if (fOn && !root.manualSurfaceGradientEnabled && colorToHex(root.manualSurfaceBg2) === colorToHex(baseS)) {
            root.manualSurfaceBg2 = deriveHarmonyStop(baseS, 14, 0.05);
        }
        root.manualShellGradientEnabled = sOn;
        root.manualSurfaceGradientEnabled = fOn;
        root.manualAccentMode = aOn ? "Gradient" : "Solid";
        root.accentMode = root.manualAccentMode;
        rebuildPalette(true, false);
    }

    function setGradientAngle(deg) {
        const next = Math.max(0, Math.min(360, Math.round(Number(deg) || 0)));
        if (root.manualGradientAngle === next) return;
        root.manualGradientAngle = next;
        rebuildPalette(true, false);
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
            if (!root.wallpaperColorEnabled) {
                const norm = root.hasCustomBorderColor ? normalizeHex(root.customBorderColor, "") : "";
                return norm !== "" ? norm : colorToHex(root.text);
            }
            return colorToHex(root._liveBorderBase);
        }
        return "#ffffff";
    }

    function applyPreset(name, skipLiveCommit) {
        const p = presetMeta(name);
        if (!p) return false;
        root.activePreset = name;
        root.surfaceTheme = p.surfaceTheme;
        root.customAccentActive = false;
        root.customAccent2Active = false;
        root.manualAccentMode = p.accentGradient ? "Gradient" : "Solid";
        root.accentMode = root.manualAccentMode;
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
        root.manualShellGradientEnabled = Boolean(p.shellGradient);
        root.manualSurfaceGradientEnabled = Boolean(p.surfaceGradient);
        root.manualGradientAngle = (p.gradientAngle !== undefined) ? p.gradientAngle : 135;
        root.manualPillBg2 = p.pillBg2 ? hexToColor(p.pillBg2) : deriveHarmonyStop(p.pillBg, 16, 0.055);
        root.manualSurfaceBg2 = p.surfaceBg2 ? hexToColor(p.surfaceBg2) : deriveHarmonyStop(p.surfaceBg, 14, 0.05);
        root.manualAccent2 = p.accent2 ? hexToColor(p.accent2) : deriveHarmonyStop(p.accent, 32, 0.0);
        if (!skipLiveCommit) {
            rebuildPalette(false, false);
        }
        root.presetApplied(name);
        if (!skipLiveCommit && !root._suppressColorSignal) root.themeColorsChanged();
        return true;
    }

    function exportPaletteState() {
        return {
            surfaceTheme: root.surfaceTheme,
            customAccentActive: Boolean(root.customAccentActive),
            accentMode: root.manualAccentMode,
            hueVal: root.hueVal,
            satVal: root.satVal,
            valVal: root.valVal,
            gradientAngle: Math.round(root.manualGradientAngle),
            shellGradientEnabled: Boolean(root.manualShellGradientEnabled),
            pillBg2: colorToHex(root.manualPillBg2),
            surfaceGradientEnabled: Boolean(root.manualSurfaceGradientEnabled),
            surfaceBg2: colorToHex(root.manualSurfaceBg2),
            customAccent2Active: Boolean(root.customAccent2Active),
            accent2: colorToHex(root.manualAccent2),
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
            customBorderColor: root.hasCustomBorderColor ? normalizeHex(root.customBorderColor, "") : "",
            wallpaperColorEnabled: Boolean(root.wallpaperColorEnabled),
            wallpaperColorMode: root.wallpaperColorMode === "Gradient" ? "Gradient" : "Solid"
        };
    }

    function applyPaletteState(obj, deferLiveIfWallpaper) {
        if (!obj || typeof obj !== "object") return false;
        const prevSuppress = root._suppressColorSignal;
        root._suppressColorSignal = true;

        const surfTheme = obj.surfaceTheme || obj.globalSurfaceTheme;
        if (typeof surfTheme === "string" && (surfTheme === "OLED Pure" || surfTheme === "Mica Dark" || surfTheme === "Adaptive")) {
            root.surfaceTheme = surfTheme;
        }
        if (typeof obj.accentMode === "string") {
            root.manualAccentMode = obj.accentMode === "Gradient" ? "Gradient" : "Solid";
            root.accentMode = root.manualAccentMode;
        }
        if (typeof obj.gradientAngle === "number") {
            root.manualGradientAngle = Math.max(0, Math.min(360, Math.round(obj.gradientAngle)));
        }

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

        root.manualShellGradientEnabled = Boolean(obj.shellGradientEnabled);
        const p2 = normalizeHex(obj.pillBg2, "");
        if (p2 !== "") root.manualPillBg2 = hexToColor(p2);

        root.manualSurfaceGradientEnabled = Boolean(obj.surfaceGradientEnabled);
        const s2 = normalizeHex(obj.surfaceBg2, "");
        if (s2 !== "") root.manualSurfaceBg2 = hexToColor(s2);

        const a2 = normalizeHex(obj.accent2, "");
        root.customAccent2Active = Boolean(obj.customAccent2Active) && a2 !== "";
        if (root.customAccent2Active) root.manualAccent2 = hexToColor(a2);

        root.wallpaperColorEnabled = Boolean(obj.wallpaperColorEnabled);
        root.wallpaperColorMode = (typeof obj.wallpaperColorMode === "string" && obj.wallpaperColorMode.toLowerCase() === "gradient")
            ? "Gradient"
            : "Solid";

        if (p2 === "" || (!root.manualShellGradientEnabled && obj.pillBg2 === undefined)) {
            const p = presetMeta(root.activePreset) || root.presetCatalog[0];
            const baseP = root.hasCustomPillBg ? hexToColor(root.customPillBg) : hexToColor(p.pillBg);
            root.manualPillBg2 = deriveHarmonyStop(baseP, 16, 0.055);
        }
        if (s2 === "" || (!root.manualSurfaceGradientEnabled && obj.surfaceBg2 === undefined)) {
            const p = presetMeta(root.activePreset) || root.presetCatalog[0];
            const baseS = root.hasCustomSurfaceBg ? hexToColor(root.customSurfaceBg) : hexToColor(p.surfaceBg);
            root.manualSurfaceBg2 = deriveHarmonyStop(baseS, 14, 0.05);
        }

        if (!(deferLiveIfWallpaper && root.wallpaperColorEnabled)) {
            rebuildPalette(false, false);
        } else {
            _computeManualTargetPalette();
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
            // 1. Theme & Accent (always exports User A's preserved manual color settings)
            presetName: root.activePreset,
            globalSurfaceTheme: stateObj ? stateObj.globalSurfaceTheme : root.surfaceTheme,
            customAccentActive: Boolean(root.customAccentActive),
            accentMode: root.manualAccentMode,
            hueVal: root.hueVal,
            satVal: root.satVal,
            valVal: root.valVal,
            gradientAngle: Math.round(root.manualGradientAngle),
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
            // 7. v3 Extended Colors & Gradients (manual backing state)
            shellGradientEnabled: Boolean(root.manualShellGradientEnabled),
            pillBg2: colorToHex(root.manualPillBg2),
            surfaceGradientEnabled: Boolean(root.manualSurfaceGradientEnabled),
            surfaceBg2: colorToHex(root.manualSurfaceBg2),
            customAccent2Active: Boolean(root.customAccent2Active),
            accent2: colorToHex(root.manualAccent2),
            customPaletteActive: Boolean(root.customPaletteActive),
            customPillBg: root.hasCustomPillBg ? normalizeHex(root.customPillBg, "") : "",
            customSurfaceBg: root.hasCustomSurfaceBg ? normalizeHex(root.customSurfaceBg, "") : "",
            customSurfaceRaised: root.hasCustomSurfaceRaised ? normalizeHex(root.customSurfaceRaised, "") : "",
            customText: root.hasCustomText ? normalizeHex(root.customText, "") : "",
            customBorderColor: root.hasCustomBorderColor ? normalizeHex(root.customBorderColor, "") : "",
            // 8. v4 Adaptive Wallpaper Color Mode ("Adjust colors based on what you see")
            wallpaperColorEnabled: Boolean(root.wallpaperColorEnabled),
            wallpaperColorMode: root.wallpaperColorMode === "Gradient" ? "Gradient" : "Solid"
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
