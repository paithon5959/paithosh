import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../services"

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: overlayWin
        property var modelData
        screen: modelData

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "paithosh-cursor-motion"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Item {
            id: emptyMask
            width: 0
            height: 0
        }

        mask: Region {
            item: emptyMask
        }

        readonly property var hyprMon: CompositorService.isHyprland && modelData ? Hyprland.monitorFor(modelData) : null
        readonly property real monX: hyprMon ? (hyprMon.x || 0) : 0
        readonly property real monY: hyprMon ? (hyprMon.y || 0) : 0
        readonly property real monW: modelData ? (modelData.width || 1920) : 1920
        readonly property real monH: modelData ? (modelData.height || 1080) : 1080

        readonly property real sz: CursorService.size
        readonly property real quadSize: Math.max(200, Math.ceil(sz * 4.5 + 148))
        readonly property real maxStreakPx: Math.min(quadSize * 0.34, Math.max(72, sz * 2.8))

        // Vsync-smoothed render state (only active while moving or collapsing)
        property real targetX: CursorService.cursorX - monX
        property real targetY: CursorService.cursorY - monY
        property real renderX: targetX
        property real renderY: targetY
        property real renderVx: 0
        property real renderVy: 0
        property real renderPrevVx: 0
        property real renderPrevVy: 0
        property real renderBlurOpacity: 0
        property bool activeOnScreen: false

        function _clampVec(vx, vy, maxLen) {
            const len = Math.hypot(vx, vy);
            if (len <= maxLen || len < 0.0001) return [vx, vy];
            const k = maxLen / len;
            return [vx * k, vy * k];
        }

        Connections {
            target: CursorService
            function onCursorSampleSeqChanged() {
                const lx = CursorService.cursorX - overlayWin.monX;
                const ly = CursorService.cursorY - overlayWin.monY;
                const onScr = lx >= -overlayWin.quadSize && lx <= overlayWin.monW + overlayWin.quadSize
                    && ly >= -overlayWin.quadSize && ly <= overlayWin.monH + overlayWin.quadSize;
                overlayWin.activeOnScreen = onScr;
                if (!onScr) return;

                // Snap directly to latest pointer position (zero exponential position lag)
                overlayWin.targetX = lx;
                overlayWin.targetY = ly;
                overlayWin.renderX = lx;
                overlayWin.renderY = ly;
                overlayWin.renderVx = CursorService.cursorVx;
                overlayWin.renderVy = CursorService.cursorVy;
                overlayWin.renderPrevVx = CursorService.cursorPrevVx;
                overlayWin.renderPrevVy = CursorService.cursorPrevVy;
                if (!frameAnim.running) frameAnim.running = true;
            }
            function onCursorMovingChanged() {
                if (CursorService.cursorMoving && overlayWin.activeOnScreen && !frameAnim.running) {
                    frameAnim.running = true;
                }
            }
        }

        // Vsync-locked per-frame integration & clean collapse on stop (0% CPU/GPU when idle)
        FrameAnimation {
            id: frameAnim
            running: false
            onTriggered: {
                const dt = Math.max(0.002, Math.min(0.05, frameTime));
                const hz = Math.max(30.0, Math.min(360.0, CursorService.cursorRefreshHz || 60.0));

                // Exponentially collapse velocity into cursor as soon as pointer stops (~2 frames)
                if (!CursorService.cursorMoving) {
                    const decay = Math.exp(-dt * hz * 1.45);
                    overlayWin.renderVx *= decay;
                    overlayWin.renderVy *= decay;
                    overlayWin.renderPrevVx *= decay;
                    overlayWin.renderPrevVy *= decay;
                }

                const speed = Math.hypot(overlayWin.renderVx, overlayWin.renderVy);
                const speedPxPerSec = speed * hz;
                const threshold = Math.max(0, CursorService.motionBlurThreshold);
                const strength = CursorService.motionBlurStrength;
                // Strictly 0 below activation threshold; smoothstep ramp above it (refresh-rate independent)
                const rampSpan = Math.max(450.0, 900.0 * (1.0 - 0.25 * strength));
                const rawAct = Math.min(1.0, Math.max(0.0, (speedPxPerSec - threshold) / rampSpan));
                const smoothAct = rawAct * rawAct * (3.0 - 2.0 * rawAct);
                const targetOp = (CursorService.motionBlur && overlayWin.activeOnScreen)
                    ? smoothAct * (0.40 + 0.55 * strength)
                    : 0.0;

                const opAlpha = 1.0 - Math.exp(-dt * hz * (targetOp > overlayWin.renderBlurOpacity ? 2.2 : 1.55));
                overlayWin.renderBlurOpacity += (targetOp - overlayWin.renderBlurOpacity) * opAlpha;

                if (!CursorService.cursorMoving && speed < 0.75 && overlayWin.renderBlurOpacity < 0.008) {
                    overlayWin.renderVx = 0;
                    overlayWin.renderVy = 0;
                    overlayWin.renderPrevVx = 0;
                    overlayWin.renderPrevVy = 0;
                    overlayWin.renderBlurOpacity = 0;
                    frameAnim.running = false;
                }
            }
        }

        // Offscreen cursor sprite (rasterized once per style/color/size change, zero per-frame SVG cost)
        Image {
            id: spriteImg
            visible: true
            width: overlayWin.sz
            height: overlayWin.sz
            sourceSize: Qt.size(Math.max(32, Math.round(overlayWin.sz * 2)), Math.max(32, Math.round(overlayWin.sz * 2)))
            source: CursorService.previewTag !== ""
                ? ("file://" + CursorService.previewDir + "/active-" + CursorService.previewTag + ".svg")
                : ""
            smooth: true
            asynchronous: false
            cache: false
            function _refreshTexture() {
                if (status === Image.Ready) Qt.callLater(() => spriteSource.scheduleUpdate());
            }
            Component.onCompleted: _refreshTexture()
            onStatusChanged: _refreshTexture()
            onSourceChanged: _refreshTexture()
            onWidthChanged: _refreshTexture()
        }

        ShaderEffectSource {
            id: spriteSource
            visible: false
            sourceItem: spriteImg
            width: overlayWin.sz
            height: overlayWin.sz
            textureSize: Qt.size(Math.max(32, Math.round(overlayWin.sz * 2)), Math.max(32, Math.round(overlayWin.sz * 2)))
            live: false
            hideSource: true
            smooth: true
            mipmap: false
        }

        // Local 32-tap GPU directional shutter-blur quad (only visible & rendered while moving)
        ShaderEffect {
            id: blurQuad
            readonly property real shutterScale: 0.55 + 0.85 * CursorService.motionBlurStrength
            readonly property var clampedV: overlayWin._clampVec(
                overlayWin.renderVx * shutterScale,
                overlayWin.renderVy * shutterScale,
                overlayWin.maxStreakPx
            )
            readonly property var clampedPrevV: overlayWin._clampVec(
                overlayWin.renderPrevVx * shutterScale,
                overlayWin.renderPrevVy * shutterScale,
                overlayWin.maxStreakPx
            )

            // Center quad on the cursor's visual center (compensating hotspot offset)
            x: overlayWin.renderX - (CursorService.hotspotX * overlayWin.sz) + (overlayWin.sz * 0.5) - (overlayWin.quadSize * 0.5)
            y: overlayWin.renderY - (CursorService.hotspotY * overlayWin.sz) + (overlayWin.sz * 0.5) - (overlayWin.quadSize * 0.5)
            width: overlayWin.quadSize
            height: overlayWin.quadSize

            visible: overlayWin.activeOnScreen && overlayWin.renderBlurOpacity > 0.008 && spriteImg.status === Image.Ready
            opacity: 1.0

            property variant source: spriteSource
            property real blurOpacity: overlayWin.renderBlurOpacity
            property vector2d cursorUvSize: Qt.vector2d(
                overlayWin.sz / overlayWin.quadSize,
                overlayWin.sz / overlayWin.quadSize
            )
            property vector2d velUv: Qt.vector2d(
                clampedV[0] / overlayWin.quadSize,
                clampedV[1] / overlayWin.quadSize
            )
            property vector2d prevVelUv: Qt.vector2d(
                clampedPrevV[0] / overlayWin.quadSize,
                clampedPrevV[1] / overlayWin.quadSize
            )
            // Predictive lead compensates ~0.65 frame of IPC + Wayland overlay latency so smear stays glued to real cursor
            property real leadFactor: 0.65

            fragmentShader: "../assets/shaders/cursor_blur.frag.qsb"
        }
    }
}
