import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."
import "common"

PanelWindow {
    id: root

    required property var shellState
    property var modelData

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"

    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "paithosh-session-transition"
    WlrLayershell.keyboardFocus: isActiveScreen && !isReloadMode && shellState.sessionPhase === "fading"
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None

    readonly property bool isActiveScreen: !shellState.activeScreen || shellState.activeScreen === modelData
    readonly property bool isReloadMode: shellState.sessionPhase === "idle" && shellState.reloadOverlayActive
    readonly property string action: isReloadMode ? "reload" : shellState.sessionAction
    readonly property string phase: isReloadMode ? shellState.reloadPhase : shellState.sessionPhase

    readonly property bool curtainVisible: isReloadMode
        ? (phase === "exiting" || phase === "revealing")
        : (phase === "fading" || phase === "executing")
    readonly property bool capsuleVisible: isReloadMode
        ? (phase === "exiting" || phase === "revealing")
        : (phase === "fading")

    readonly property bool isShutdown: action === "shutdown"
    readonly property bool isReboot: action === "reboot"
    readonly property bool isReloadDone: isReloadMode && phase === "revealing"
    readonly property color accentTint: isShutdown
        ? Theme.dangerText
        : (isReloadDone ? Theme.ok : Theme.accent)
    readonly property string iconName: {
        if (isShutdown) return "power";
        if (isReloadDone) return "check";
        if (isReboot || isReloadMode) return "refresh";
        return "log-out";
    }
    readonly property string titleText: {
        if (isReloadMode) return isReloadDone ? "Shell Reloaded" : "Reloading Shell…";
        if (isShutdown) return "Shutting down…";
        if (isReboot) return "Restarting…";
        if (action === "logout") return "Logging out…";
        return "";
    }
    readonly property string subtitleText: {
        if (isReloadMode) {
            return isReloadDone
                ? "Configuration applied"
                : (shellState._pendingReloadHyprland ? "Reloading Quickshell & Hyprland" : "Reloading Quickshell config");
        }
        return shellState.sessionDryRun ? "Preview • Press Esc to cancel" : "Press Esc to cancel";
    }

    // Start opaque without fade-in flash when seamlessly taking over right after Quickshell.reload()
    property bool _entered: shellState.reloadPhase === "revealing"

    Component.onCompleted: {
        if (!_entered) {
            Qt.callLater(() => { root._entered = true; });
        }
    }

    Item {
        id: keyTrap
        anchors.fill: parent
        focus: root.isActiveScreen && !root.isReloadMode
        Keys.onEscapePressed: (event) => {
            if (!root.isReloadMode && root.phase === "fading") {
                root.shellState.cancelSessionAction();
                event.accepted = true;
            }
        }
    }

    // Fullscreen OLED dark veil over all windows & monitors
    Rectangle {
        id: curtain
        anchors.fill: parent
        color: Theme.pillBg
        opacity: (root._entered && root.curtainVisible) ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: root.curtainVisible
                    ? Math.max(150, Math.round((root.isReloadMode ? 280 : (root.isShutdown ? 460 : 400)) / Math.max(0.5, Theme.speedMultiplier)))
                    : Math.max(140, Math.round((root.isReloadMode ? 360 : 280) / Math.max(0.5, Theme.speedMultiplier)))
                easing.type: root.curtainVisible ? Easing.InOutCubic : Easing.OutCubic
            }
        }
    }

    // Minimal monochrome center capsule (primary/active screen only)
    Rectangle {
        id: statusCard
        visible: root.isActiveScreen
        anchors.centerIn: parent
        width: Math.min(324, Math.max(256, cardContent.implicitWidth + 40))
        height: cardContent.implicitHeight + 32
        radius: 20
        color: Theme.surfaceBg
        border.width: 1
        border.color: root.isShutdown
            ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.40)
            : (root.isReloadDone
                ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.42)
                : Theme.borderSubtle)
        clip: true

        Behavior on border.color {
            ColorAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        opacity: (root._entered && root.capsuleVisible) ? 1.0 : 0.0
        scale: (root._entered && root.capsuleVisible)
            ? 1.0
            : ((root.phase === "executing" || root.phase === "clearing") ? 0.94 : 0.90)

        Behavior on opacity {
            NumberAnimation {
                duration: root.capsuleVisible
                    ? Math.max(140, Math.round(260 / Math.max(0.5, Theme.speedMultiplier)))
                    : Math.max(110, Math.round(200 / Math.max(0.5, Theme.speedMultiplier)))
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.capsuleVisible
                    ? Math.max(180, Math.round(Theme.springMs * 0.9))
                    : Math.max(110, Math.round(200 / Math.max(0.5, Theme.speedMultiplier)))
                easing.type: root.capsuleVisible ? Easing.OutBack : Easing.OutCubic
                easing.overshoot: 1.05
            }
        }

        ColumnLayout {
            id: cardContent
            anchors.centerIn: parent
            width: parent.width - 40
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    width: 38
                    height: 38
                    radius: 12
                    color: root.isShutdown
                        ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.14)
                        : (root.isReloadDone
                            ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.14)
                            : Theme.surfaceRaised)
                    border.width: 1
                    border.color: root.isShutdown
                        ? Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.35)
                        : (root.isReloadDone
                            ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.35)
                            : Theme.borderSubtle)

                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    SvgIcon {
                        id: actionIcon
                        anchors.centerIn: parent
                        sourceName: root.iconName
                        iconSize: 18
                        color: root.accentTint

                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 860
                            loops: Animation.Infinite
                            running: (root.isReboot || (root.isReloadMode && !root.isReloadDone)) && root.capsuleVisible
                            onRunningChanged: if (!running) actionIcon.rotation = 0
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: root.titleText
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.subtitleText
                        color: Theme.textMuted
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }

            // Sleek right-to-left sweeping monochrome progress bar
            Rectangle {
                id: progressTrack
                Layout.fillWidth: true
                height: 3
                radius: 2
                color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12)
                clip: true

                Rectangle {
                    id: sweepBeam
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.max(48, Math.round(progressTrack.width * 0.42))
                    radius: 2
                    color: root.accentTint
                    x: progressTrack.width

                    SequentialAnimation on x {
                        running: root._entered && root.capsuleVisible && !root.isReloadDone
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: progressTrack.width
                            to: -sweepBeam.width
                            duration: Math.max(460, Math.round(880 / Math.max(0.5, Theme.speedMultiplier)))
                            easing.type: Easing.InOutCubic
                        }
                    }
                }

                // Smooth solid confirmation sweep when reload completes
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    radius: 2
                    color: Theme.ok
                    width: root.isReloadDone ? parent.width : 0

                    Behavior on width {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }
}
