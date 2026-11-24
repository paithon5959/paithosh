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

        readonly property real localX: CursorService.cursorX - monX
        readonly property real localY: CursorService.cursorY - monY
        readonly property bool onThisScreen: localX >= -64 && localX <= monW + 64 && localY >= -64 && localY <= monH + 64

        readonly property real clampedVx: Math.max(-72, Math.min(72, CursorService.cursorVx))
        readonly property real clampedVy: Math.max(-72, Math.min(72, CursorService.cursorVy))
        readonly property real speedFactor: Math.min(1.0, Math.max(0.0, (CursorService.cursorSpeed - 3.0) / 28.0))
        readonly property bool activeTrail: CursorService.motionBlur && CursorService.cursorMoving && onThisScreen && speedFactor > 0.02

        Repeater {
            model: 5
            delegate: Image {
                required property int index
                readonly property int step: index + 1
                readonly property real falloff: Math.pow(1.0 - step / 6.0, 1.6)
                readonly property real stride: step * 0.42 * CursorService.motionBlurStrength
                readonly property real sz: CursorService.size

                x: overlayWin.localX - (CursorService.hotspotX * sz) - (overlayWin.clampedVx * stride)
                y: overlayWin.localY - (CursorService.hotspotY * sz) - (overlayWin.clampedVy * stride)
                width: sz
                height: sz
                sourceSize: Qt.size(Math.max(16, sz * 2), Math.max(16, sz * 2))
                source: CursorService.previewTag !== "" ? ("file://" + CursorService.previewDir + "/active-" + CursorService.previewTag + ".svg") : ""
                smooth: true
                asynchronous: false
                cache: false

                opacity: overlayWin.activeTrail
                    ? (overlayWin.speedFactor * falloff * 0.56 * CursorService.motionBlurStrength)
                    : 0.0
                visible: opacity > 0.01

                Behavior on opacity {
                    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                }
            }
        }
    }
}
