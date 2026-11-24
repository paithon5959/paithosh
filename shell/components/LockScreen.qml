import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import ".."
import "../services"
import "common"

Scope {
    id: lockRoot

    required property var shellState
    property string wallpaperPath: ""

    readonly property string resolvedWallpaperUrl: lockRoot.wallpaperPath !== ""
        ? (lockRoot.wallpaperPath.startsWith("file://") ? lockRoot.wallpaperPath : ("file://" + lockRoot.wallpaperPath))
        : ""
    property string sharedClockText: Qt.formatTime(new Date(), "hh:mm")

    Timer {
        interval: 5000
        running: LockService.locked || LockService.transitionVisible
        repeat: true
        triggeredOnStart: true
        onTriggered: lockRoot.sharedClockText = Qt.formatTime(new Date(), "hh:mm")
    }

    // Smooth pre-lock / post-unlock transition overlay (eliminates 0ms snap when apps are open)
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: transWin
            property var modelData
            screen: modelData

            visible: LockService.transitionVisible
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "paithosh-lock-transition"
            WlrLayershell.keyboardFocus: (LockService.transitionVisible && !LockService.sessionLocked) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            readonly property bool isBottom: lockRoot.shellState.barPosition === "bottom"
            property real animProgress: LockService.transitionProgress
            Behavior on animProgress {
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

            // Wallpaper fading over active windows
            Image {
                anchors.fill: parent
                source: lockRoot.resolvedWallpaperUrl
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: true
                smooth: true
                opacity: transWin.animProgress
            }

            // Dim scrim matching LockScreen idle state (0.36)
            Rectangle {
                anchors.fill: parent
                color: Theme.pillBg
                opacity: transWin.animProgress * 0.36
            }

            // Matching statusbar pill so transition between DynamicIsland <-> LockScreen is pixel-seamless
            ClippingRectangle {
                id: transPill
                readonly property real edgeOffset: Theme.topOffsetRest + (Theme.topOffsetHover - Theme.topOffsetRest) * transWin.animProgress

                height: Theme.islandHeight
                width: Math.max(260, Math.ceil(transWeather.implicitWidth + 36 + transClock.implicitWidth + 84))
                radius: Theme.islandRadius
                color: Theme.pillBg
                border.width: 1
                border.color: LockService.unlockSuccess
                    ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.55)
                    : Theme.borderSubtle
                opacity: transWin.animProgress

                x: Math.round((transWin.width - width) / 2)
                y: transWin.isBottom
                    ? Math.round(transWin.height - height - edgeOffset)
                    : Math.round(edgeOffset)

                Text {
                    id: transWeather
                    anchors.left: parent.left
                    anchors.leftMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: WeatherService.tempText
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 22
                    font.weight: Font.Bold
                }

                SvgIcon {
                    anchors.centerIn: parent
                    sourceName: LockService.unlockSuccess ? "unlock" : "lock"
                    iconSize: 16
                    color: LockService.unlockSuccess ? Theme.ok : Theme.textSub
                }

                Text {
                    id: transClock
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.verticalCenter: parent.verticalCenter
                    text: lockRoot.sharedClockText
                    color: Theme.text
                    font.family: Theme.fontSans
                    font.pixelSize: 22
                    font.weight: Font.Bold
                }
            }
        }
    }

    // Secure Wayland Session Lock (ext_session_lock_v1)
    WlSessionLock {
        id: sessionLock
        locked: LockService.sessionLocked

        WlSessionLockSurface {
            id: surface
            color: Theme.pillBg

            readonly property bool isBottom: lockRoot.shellState.barPosition === "bottom"
            readonly property string screenName: surface.screen ? surface.screen.name : ""
            readonly property bool isActiveScreen: LockService.activeScreenName === "" || LockService.activeScreenName === screenName

            property bool inputOpen: false
            property real shakeX: 0

            Component.onCompleted: {
                Qt.callLater(function() {
                    keyCatcher.forceActiveFocus();
                });
            }

            Timer {
                id: idleCollapseTimer
                interval: 6000
                repeat: false
                onTriggered: {
                    if (surface.inputOpen && passwordInput.text.length === 0 && !LockService.authenticating && !LockService.isError && !LockService.unlockSuccess) {
                        surface.inputOpen = false;
                        keyCatcher.forceActiveFocus();
                    }
                }
            }

            Connections {
                target: LockService
                function onAuthFailed() {
                    if (!surface.isActiveScreen) return;
                    passwordInput.text = "";
                    surface.inputOpen = true;
                    shakeAnim.restart();
                    Qt.callLater(function() {
                        passwordInput.forceActiveFocus();
                    });
                }
                function onUnlockSuccessChanged() {
                    if (LockService.unlockSuccess) {
                        passwordInput.text = "";
                    }
                }
            }

            SequentialAnimation {
                id: shakeAnim
                NumberAnimation { target: surface; property: "shakeX"; to: -10; duration: 45; easing.type: Easing.OutCubic }
                NumberAnimation { target: surface; property: "shakeX"; to: 10; duration: 55; easing.type: Easing.OutCubic }
                NumberAnimation { target: surface; property: "shakeX"; to: -7; duration: 50; easing.type: Easing.OutCubic }
                NumberAnimation { target: surface; property: "shakeX"; to: 7; duration: 50; easing.type: Easing.OutCubic }
                NumberAnimation { target: surface; property: "shakeX"; to: -3; duration: 45; easing.type: Easing.OutCubic }
                NumberAnimation { target: surface; property: "shakeX"; to: 0; duration: 55; easing.type: Easing.OutCubic }
            }

            FocusScope {
                id: keyCatcher
                anchors.fill: parent
                focus: true

                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Shift || event.key === Qt.Key_Control ||
                        event.key === Qt.Key_Alt || event.key === Qt.Key_Meta ||
                        event.key === Qt.Key_CapsLock || event.key === Qt.Key_Super_L ||
                        event.key === Qt.Key_Super_R) {
                        return;
                    }
                    if (LockService.unlockSuccess || LockService.exiting) {
                        event.accepted = true;
                        return;
                    }

                    LockService.activeScreenName = surface.screenName;

                    if (!surface.inputOpen) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                            surface.inputOpen = true;
                            idleCollapseTimer.restart();
                            Qt.callLater(function() {
                                passwordInput.forceActiveFocus();
                            });
                            event.accepted = true;
                            return;
                        }
                        if (event.text.length > 0 &&
                            !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) &&
                            event.key !== Qt.Key_Escape &&
                            event.key !== Qt.Key_Backspace &&
                            event.key !== Qt.Key_Tab) {
                            LockService.clearError();
                            surface.inputOpen = true;
                            passwordInput.forceActiveFocus();
                            passwordInput.text = event.text;
                            passwordInput.cursorPosition = passwordInput.text.length;
                            SoundService.playKey();
                            idleCollapseTimer.stop();
                            event.accepted = true;
                        }
                    }
                }

                // Current desktop wallpaper (already faded in by transitionOverlay)
                Image {
                    anchors.fill: parent
                    source: lockRoot.resolvedWallpaperUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: false
                    cache: true
                    smooth: true
                }

                // Subtle dim scrim (0.36 at rest, 0.48 while typing)
                Rectangle {
                    anchors.fill: parent
                    color: Theme.pillBg
                    opacity: (surface.isActiveScreen && surface.inputOpen && !LockService.exiting) ? 0.48 : 0.36

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                    }
                }

                // Multi-monitor pointer tracking & empty-input collapse
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: {
                        if (!LockService.authenticating && !LockService.unlockSuccess && passwordInput.text.length === 0) {
                            LockService.activeScreenName = surface.screenName;
                        }
                    }
                    onClicked: {
                        LockService.activeScreenName = surface.screenName;
                        if (surface.inputOpen && passwordInput.text.length === 0 && !LockService.authenticating) {
                            surface.inputOpen = false;
                            idleCollapseTimer.stop();
                            keyCatcher.forceActiveFocus();
                        } else if (surface.inputOpen) {
                            passwordInput.forceActiveFocus();
                        }
                    }
                }

                // Statusbar Lock Pill (all interaction revolves around the statusbar)
                ClippingRectangle {
                    id: mainPill

                    readonly property real slotsTargetWidth: slotLockedIcon.targetWidth + slotPassword.targetWidth
                    readonly property real edgeOffset: Theme.topOffsetHover

                    height: Theme.islandHeight
                    width: Math.max(260, Math.min(surface.width - 48, Math.ceil(weatherLabel.implicitWidth + slotsTargetWidth + clockLabel.implicitWidth + 84)))
                    radius: Theme.islandRadius
                    color: Theme.pillBg
                    border.width: 1
                    border.color: {
                        if (LockService.unlockSuccess) return Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.55);
                        if (surface.isActiveScreen && LockService.isError) return Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.55);
                        if (surface.isActiveScreen && surface.inputOpen) return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45);
                        return Theme.borderSubtle;
                    }

                    x: Math.round((surface.width - width) / 2 + surface.shakeX)
                    y: surface.isBottom
                        ? Math.round(surface.height - height - edgeOffset)
                        : Math.round(edgeOffset)

                    Behavior on width {
                        NumberAnimation {
                            duration: Math.round(Theme.springMs * 0.75)
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.1
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }

                    MouseArea {
                        anchors.fill: parent
                        propagateComposedEvents: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            LockService.activeScreenName = surface.screenName;
                            if (!surface.inputOpen && !LockService.unlockSuccess && !LockService.exiting) {
                                surface.inputOpen = true;
                                idleCollapseTimer.restart();
                                Qt.callLater(function() {
                                    passwordInput.forceActiveFocus();
                                });
                                mouse.accepted = true;
                            } else {
                                passwordInput.forceActiveFocus();
                                mouse.accepted = false;
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent

                        // Left Edge: Outdoor Temperature
                        Text {
                            id: weatherLabel
                            anchors.left: parent.left
                            anchors.leftMargin: 24
                            anchors.verticalCenter: parent.verticalCenter
                            text: WeatherService.tempText
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 22
                            font.weight: Font.Bold
                        }

                        // Center Expanding Slots
                        Row {
                            id: centerSlotsRow
                            x: Math.round(weatherLabel.x + weatherLabel.implicitWidth + Math.max(12, (clockLabel.x - (weatherLabel.x + weatherLabel.implicitWidth) - width) / 2))
                            y: Math.round((parent.height - height) / 2)
                            width: Math.min(implicitWidth, Math.max(0, clockLabel.x - (weatherLabel.x + weatherLabel.implicitWidth) - 24))
                            height: Theme.islandHeight
                            spacing: 0
                            clip: true

                            // 1. Locked Idle Indicator Slot
                            IslandSlot {
                                id: slotLockedIcon
                                open: !(surface.isActiveScreen && (surface.inputOpen || LockService.unlockSuccess)) || LockService.exiting
                                maxSlotWidth: 52

                                Item {
                                    width: 36
                                    height: Theme.islandHeight
                                    SvgIcon {
                                        anchors.centerIn: parent
                                        sourceName: LockService.unlockSuccess ? "unlock" : "lock"
                                        iconSize: 16
                                        color: LockService.unlockSuccess ? Theme.ok : Theme.textSub
                                    }
                                }
                            }

                            // 2. Inline Password Input Slot
                            IslandSlot {
                                id: slotPassword
                                open: surface.isActiveScreen && surface.inputOpen && !LockService.exiting
                                maxSlotWidth: 330

                                Item { width: 10; height: 1 }

                                SvgIcon {
                                    id: lockStateIcon
                                    anchors.verticalCenter: parent.verticalCenter
                                    sourceName: LockService.unlockSuccess ? "unlock" : "lock"
                                    iconSize: 15
                                    color: LockService.unlockSuccess
                                        ? Theme.ok
                                        : (LockService.isError ? Theme.dangerText : Theme.text)

                                    Behavior on color {
                                        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                                    }

                                    SequentialAnimation on opacity {
                                        running: LockService.authenticating
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.35; duration: 550; easing.type: Easing.InOutSine }
                                        NumberAnimation { to: 1.0; duration: 550; easing.type: Easing.InOutSine }
                                    }
                                }

                                Item { width: 8; height: 1 }

                                // Concentric Password Well (pill r=26, padY=10 -> well H=34, r=17)
                                Rectangle {
                                    id: passwordWell
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 34
                                    width: Math.min(248, Math.max(188, 188 + passwordInput.text.length * 4))
                                    radius: 17
                                    clip: true
                                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, passwordInput.activeFocus ? 0.11 : 0.07)
                                    border.width: 1
                                    border.color: {
                                        if (LockService.unlockSuccess) return Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.55);
                                        if (LockService.isError) return Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.55);
                                        if (passwordInput.activeFocus) return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40);
                                        return Theme.borderSubtle;
                                    }

                                    Behavior on width {
                                        NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on border.color {
                                        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 5
                                        spacing: 6

                                        AnimatedTextInput {
                                            id: passwordInput
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            Layout.fillHeight: true
                                            verticalAlignment: TextInput.AlignVCenter
                                            echoMode: TextInput.Password
                                            textColor: Theme.text
                                            font.family: Theme.fontMono
                                            font.pixelSize: 15
                                            readOnly: LockService.authenticating || LockService.unlockSuccess || LockService.exiting
                                            clip: true

                                            onTextChanged: {
                                                if (text.length > 0) {
                                                    LockService.clearError();
                                                    idleCollapseTimer.stop();
                                                } else if (surface.inputOpen && !LockService.authenticating && !LockService.isError && !LockService.unlockSuccess) {
                                                    idleCollapseTimer.restart();
                                                }
                                            }

                                            onAccepted: {
                                                if (text.length > 0) {
                                                    LockService.submitPassword(text);
                                                }
                                            }

                                            Keys.onEscapePressed: {
                                                if (!LockService.authenticating && !LockService.unlockSuccess) {
                                                    text = "";
                                                    LockService.clearError();
                                                    surface.inputOpen = false;
                                                    idleCollapseTimer.stop();
                                                    keyCatcher.forceActiveFocus();
                                                }
                                            }

                                            Text {
                                                anchors.fill: parent
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                                visible: passwordInput.text.length === 0
                                                text: {
                                                    if (LockService.unlockSuccess) return "Unlocked";
                                                    if (LockService.authenticating) return "Checking...";
                                                    if (LockService.isError) return "Wrong password";
                                                    return "Password";
                                                }
                                                color: {
                                                    if (LockService.unlockSuccess) return Theme.ok;
                                                    if (LockService.isError) return Theme.dangerText;
                                                    if (LockService.authenticating) return Theme.textSub;
                                                    return Theme.textMuted;
                                                }
                                                font.family: Theme.fontSans
                                                font.pixelSize: 13
                                                font.weight: (LockService.unlockSuccess || LockService.isError) ? Font.DemiBold : Font.Normal

                                                Behavior on color {
                                                    ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                                                }
                                            }
                                        }

                                        // Concentric Submit Button (well r=17, pad=5 -> button 24x24, r=12)
                                        Rectangle {
                                            readonly property bool canSubmit: passwordInput.text.length > 0 && !LockService.authenticating && !LockService.unlockSuccess && !LockService.exiting
                                            Layout.preferredWidth: canSubmit ? 24 : 0
                                            Layout.preferredHeight: 24
                                            radius: 12
                                            clip: true
                                            opacity: canSubmit ? 1.0 : 0.0
                                            scale: submitMouse.pressed ? 0.90 : (canSubmit ? 1.0 : 0.75)
                                            color: submitMouse.containsMouse
                                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.86)
                                                : Theme.accent

                                            Behavior on Layout.preferredWidth {
                                                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                            }
                                            Behavior on opacity {
                                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                                            }
                                            Behavior on scale {
                                                NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot }
                                            }
                                            Behavior on color {
                                                ColorAnimation { duration: 140; easing.type: Easing.OutCubic }
                                            }

                                            SvgIcon {
                                                anchors.centerIn: parent
                                                sourceName: "arrow-right"
                                                iconSize: 12
                                                color: Theme.accentFg
                                            }

                                            MouseArea {
                                                id: submitMouse
                                                anchors.fill: parent
                                                enabled: parent.canSubmit
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: LockService.submitPassword(passwordInput.text)
                                            }
                                        }
                                    }
                                }

                                Item { width: 10; height: 1 }
                            }
                        }

                        // Right Edge: Clock
                        Text {
                            id: clockLabel
                            anchors.right: parent.right
                            anchors.rightMargin: 24
                            anchors.verticalCenter: parent.verticalCenter
                            text: lockRoot.sharedClockText
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 22
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }
    }
}
