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
                if (colors.length >= 3) root.surfaceBg = colors[2];
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
}
