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

            // Theme-colored backdrop (always matches desktop when wallpapers are disabled)
            Rectangle {
                anchors.fill: parent
                color: Theme.surfaceBg
                opacity: transWin.animProgress

                ThemeGradientFill {
                    anchors.fill: parent
                    enabled: Theme.surfaceGradientEnabled
                    color1: Theme.surfaceBg
                    colorMid: Theme.surfaceBgMid
                    color2: Theme.surfaceBg2
                    angle: Theme.gradientAngle
                }
            }

            // Wallpaper fading over active windows
            Image {
                anchors.fill: parent
                source: (LockService.transitionVisible && !Theme.wallpapersDisabled) ? lockRoot.resolvedWallpaperUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                cache: true
                smooth: true
                visible: !Theme.wallpapersDisabled
                opacity: transWin.animProgress
            }

            // Dim scrim matching LockScreen idle state
            Rectangle {
                anchors.fill: parent
                color: Theme.pillBg
                opacity: transWin.animProgress * (LockService.dimOpacity / 100.0)
            }

            // Matching statusbar pill so transition between DynamicIsland <-> LockScreen is pixel-seamless
            ClippingRectangle {
                id: transPill
                readonly property real edgeOffset: Theme.topOffsetRest

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
            property bool notifTrayOpen: false
            property bool pillHovered: false
            property real shakeX: 0
            property real shownOsdVal: lockRoot.shellState ? lockRoot.shellState.osdValue : 0

            Behavior on shownOsdVal {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            readonly property bool hasLockOsd: lockRoot.shellState && lockRoot.shellState.osdOpen && !LockService.exiting && !(surface.isActiveScreen && surface.inputOpen)
            readonly property bool hasLockNotifBadge: LockService.showNotifications && NotificationService.hasUnreadBadge && !surface.inputOpen && !LockService.exiting
            readonly property bool hasLockMedia: LockService.showMedia && MediaService.active && !LockService.exiting
            readonly property string lockAlertKind: {
                if (!LockService.showSystemAlerts || LockService.exiting) return "";
                if (TelemetryService.overheatAlert || (lockRoot.shellState && lockRoot.shellState.previewAlertMode === 1)) return "overheat";
                if (PowerService.lowBatteryAlert || (lockRoot.shellState && lockRoot.shellState.previewAlertMode === 2)) return "lowbat";
                if (lockRoot.shellState && lockRoot.shellState.chargeSlotOpen) return "charger";
                return "";
            }
            readonly property bool hasLockAlert: lockAlertKind !== ""

            onInputOpenChanged: {
                if (inputOpen) {
                    notifTrayOpen = false;
                } else {
                    passwordInput.focus = false;
                    keyCatcher.forceActiveFocus();
                }
            }

            Connections {
                target: LockService
                function onExitingChanged() {
                    if (LockService.exiting) surface.notifTrayOpen = false;
                }
            }

            Connections {
                target: NotificationService
                function onHistoryListChanged() {
                    if (NotificationService.historyList.length === 0) surface.notifTrayOpen = false;
                }
            }

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
                        if (event.key === Qt.Key_Escape) {
                            if (surface.notifTrayOpen) {
                                surface.notifTrayOpen = false;
                                event.accepted = true;
                                return;
                            }
                            if (NotificationService.activeToast) {
                                NotificationService.dismissToast();
                                event.accepted = true;
                                return;
                            }
                        }
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
                            if (!LockService.silentMode && LockService.sfxEnabled) {
                                SoundService.playKey();
                            }
                            idleCollapseTimer.stop();
                            event.accepted = true;
                        }
                    }
                }

                // Theme-colored backdrop (live surface color + gradient when wallpapers are disabled)
                Rectangle {
                    anchors.fill: parent
                    color: Theme.surfaceBg

                    ThemeGradientFill {
                        anchors.fill: parent
                        enabled: Theme.surfaceGradientEnabled
                        color1: Theme.surfaceBg
                        colorMid: Theme.surfaceBgMid
                        color2: Theme.surfaceBg2
                        angle: Theme.gradientAngle
                    }
                }

                // Current desktop wallpaper (already faded in by transitionOverlay)
                Image {
                    anchors.fill: parent
                    source: !Theme.wallpapersDisabled ? lockRoot.resolvedWallpaperUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: false
                    cache: true
                    smooth: true
                    opacity: Theme.wallpapersDisabled ? 0.0 : 1.0
                    visible: opacity > 0.002

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                    }
                }

                // Subtle dim scrim (custom base dim, +0.12 while typing)
                Rectangle {
                    anchors.fill: parent
                    color: Theme.pillBg
                    readonly property real baseDim: LockService.dimOpacity / 100.0
                    opacity: (surface.isActiveScreen && surface.inputOpen && !LockService.exiting) ? Math.min(0.82, baseDim + 0.12) : baseDim

                    Behavior on opacity {
                        NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                    }
                }

                // Ambient Visual Effect (Snowfall / Rain / Wind Breeze)
                LockAmbientEffect {
                    anchors.fill: parent
                    effect: LockService.effectPreset
                    intensity: LockService.effectIntensity
                    active: LockService.sessionLocked && !LockService.exiting
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
                        if (surface.notifTrayOpen) {
                            surface.notifTrayOpen = false;
                            if (!surface.inputOpen) keyCatcher.forceActiveFocus();
                            return;
                        }
                        if (surface.inputOpen && passwordInput.text.length === 0 && !LockService.authenticating) {
                            surface.inputOpen = false;
                            idleCollapseTimer.stop();
                            keyCatcher.forceActiveFocus();
                        } else if (surface.inputOpen) {
                            passwordInput.forceActiveFocus();
                        }
                    }
                }

                // Statusbar Lock Stage (1:1 geometry, hover offset & gooey.frag parity with DynamicIsland.qml)
                Item {
                    id: lockStageContainer
                    anchors.horizontalCenter: parent.horizontalCenter
                    property real animatedEdgeOffset: (surface.pillHovered || surface.inputOpen || surface.notifTrayOpen) ? Theme.topOffsetHover : Theme.topOffsetRest
                    Behavior on animatedEdgeOffset {
                        NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                    }
                    width: lockPillRow.width + Theme.shaderPad * 2
                    height: mainPill.height + Theme.shaderPad * 2
                    y: surface.isBottom
                        ? Math.round(surface.height - height + Theme.shaderPad - animatedEdgeOffset)
                        : Math.round(animatedEdgeOffset - Theme.shaderPad)
                    transform: Translate { x: surface.shakeX }

                    // Liquid Gooey Background Layer (1:1 geometry sync with foreground pills)
                    Item {
                        id: gooSource
                        anchors.fill: parent
                        layer.enabled: Theme.gooeyEnabled
                        layer.effect: ShaderEffect {
                            fragmentShader: Qt.resolvedUrl("../assets/shaders/gooey.frag.qsb")
                            property size texelSize: Qt.size(1.0 / Math.max(1, gooSource.width), 1.0 / Math.max(1, gooSource.height))
                            property real threshold: 0.46
                            property real softness: 0.06
                            property color pillColor: Theme.pillBg
                        }

                        Rectangle {
                            id: mainBg
                            x: Theme.shaderPad + mainPill.x
                            y: Theme.shaderPad
                            width: mainPill.width
                            height: mainPill.height
                            radius: mainPill.radius
                            color: Theme.pillBg
                        }

                        Rectangle {
                            id: mediaBg
                            x: Theme.shaderPad + mediaSlotWrap.x + mediaPill.x
                            y: Theme.shaderPad + (Theme.islandHeight - height) / 2
                            width: Math.max(0, Math.min(mediaPill.width, mediaSlotWrap.width - mediaPill.x))
                            height: mediaPill.height
                            radius: Theme.islandRadius
                            color: Theme.pillBg
                            scale: mediaPill.scale
                            opacity: mediaSlotWrap.opacity
                            visible: width > 1 && opacity > 0.01
                        }

                        Rectangle {
                            id: alertBg
                            x: Theme.shaderPad + alertSlotWrap.x + alertPill.x
                            y: Theme.shaderPad + (Theme.islandHeight - height) / 2
                            width: Math.max(0, Math.min(alertPill.width, alertSlotWrap.width - alertPill.x))
                            height: alertPill.height
                            radius: Theme.islandRadius
                            color: Theme.pillBg
                            scale: alertPill.scale
                            opacity: alertSlotWrap.opacity
                            visible: width > 1 && opacity > 0.01
                        }
                    }

                // Foreground Pill Row
                Row {
                    id: lockPillRow
                    x: Theme.shaderPad
                    y: Theme.shaderPad
                    spacing: 0
                    height: Theme.islandHeight

                ClippingRectangle {
                    id: mainPill

                    readonly property real slotsTargetWidth: slotLockedIcon.targetWidth + slotPassword.targetWidth + slotOsd.targetWidth + slotNotif.targetWidth

                    height: Theme.islandHeight
                    width: Math.max(260, Math.min(surface.width - 48, Math.ceil(weatherLabel.implicitWidth + slotsTargetWidth + clockLabel.implicitWidth + 84)))
                    radius: Theme.islandRadius
                    color: Theme.gooeyEnabled ? "transparent" : Theme.pillBg
                    border.width: 1
                    border.color: {
                        if (LockService.unlockSuccess) return Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.55);
                        if (surface.isActiveScreen && LockService.isError) return Qt.rgba(Theme.danger.r, Theme.danger.g, Theme.danger.b, 0.55);
                        if (surface.isActiveScreen && surface.inputOpen) return Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45);
                        return Theme.borderSubtle;
                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: Math.round(Theme.springMs * 0.65)
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.25
                        }
                    }

                    Behavior on border.color {
                        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        propagateComposedEvents: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: surface.pillHovered = true
                        onExited: surface.pillHovered = false
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
                                open: (!(surface.isActiveScreen && (surface.inputOpen || LockService.unlockSuccess)) && !surface.hasLockOsd) || LockService.exiting
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
                                            enabled: surface.inputOpen && !LockService.exiting
                                            textColor: Theme.text
                                            soundEnabled: !LockService.silentMode && LockService.sfxEnabled
                                            font.family: Theme.fontMono
                                            font.pixelSize: 15
                                            readOnly: LockService.authenticating || LockService.unlockSuccess || LockService.exiting
                                            clip: true

                                            onTextChanged: {
                                                if (text.length > 0) {
                                                    if (!surface.inputOpen && !LockService.exiting) {
                                                        surface.inputOpen = true;
                                                    }
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

                            // 3. Inline Volume / Brightness OSD Slot
                            IslandSlot {
                                id: slotOsd
                                open: surface.hasLockOsd
                                maxSlotWidth: 280

                                Item { width: 14; height: 1 }

                                SvgIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    sourceName: {
                                        const kind = lockRoot.shellState ? lockRoot.shellState.osdKind : "vol";
                                        if (kind === "bri") return "sun";
                                        if (kind === "mute") return "volume-x";
                                        return "volume";
                                    }
                                    iconSize: 18
                                    color: (lockRoot.shellState && lockRoot.shellState.osdKind === "mute") ? Theme.dangerText : Theme.text
                                }

                                Item { width: 10; height: 1 }

                                Rectangle {
                                    visible: !lockRoot.shellState || lockRoot.shellState.osdKind !== "mute"
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 156
                                    height: 6
                                    radius: 3
                                    clip: true
                                    color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.16)

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        radius: 3
                                        color: Theme.text
                                        width: Math.max(0, Math.min(parent.width, parent.width * ((lockRoot.shellState ? lockRoot.shellState.osdValue : 0) / 100.0)))

                                        Behavior on width {
                                            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                        }
                                    }
                                }

                                Text {
                                    visible: lockRoot.shellState && lockRoot.shellState.osdKind === "mute"
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Audio Muted"
                                    color: Theme.dangerText
                                    font.family: Theme.fontSans
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }

                                Item { visible: !lockRoot.shellState || lockRoot.shellState.osdKind !== "mute"; width: 10; height: 1 }

                                Text {
                                    visible: !lockRoot.shellState || lockRoot.shellState.osdKind !== "mute"
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 42
                                    horizontalAlignment: Text.AlignRight
                                    text: Math.round(surface.shownOsdVal) + "%"
                                    color: Theme.text
                                    font.family: Theme.fontMono
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }

                                Item { width: 14; height: 1 }
                            }

                            // 4. Inline Notification Bell Slot
                            IslandSlot {
                                id: slotNotif
                                open: surface.hasLockNotifBadge
                                maxSlotWidth: 72

                                Item {
                                    id: notifSlotBox
                                    width: NotificationService.unreadCount > 1 ? 54 : 38
                                    height: Theme.islandHeight
                                    scale: notifSlotMouse.pressed ? 0.92 : 1.0

                                    Behavior on width {
                                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on scale {
                                        NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot }
                                    }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 5

                                        Item {
                                            width: 22
                                            height: 22
                                            anchors.verticalCenter: parent.verticalCenter

                                            SvgIcon {
                                                anchors.centerIn: parent
                                                sourceName: "bell"
                                                iconSize: 17
                                                color: surface.notifTrayOpen ? Theme.accent : Theme.text
                                            }

                                            Rectangle {
                                                width: 8
                                                height: 8
                                                radius: 4
                                                color: Theme.danger
                                                border.width: 2
                                                border.color: Theme.pillBg
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.rightMargin: 1
                                                anchors.topMargin: 1
                                            }
                                        }

                                        Text {
                                            visible: NotificationService.unreadCount > 1
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: String(Math.min(99, NotificationService.unreadCount))
                                            color: Theme.textSub
                                            font.family: Theme.fontMono
                                            font.pixelSize: 12
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    MouseArea {
                                        id: notifSlotMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function(mouse) {
                                            LockService.activeScreenName = surface.screenName;
                                            if (NotificationService.historyList.length > 0) {
                                                surface.notifTrayOpen = !surface.notifTrayOpen;
                                            } else if (NotificationService.activeToast) {
                                                NotificationService.dismissToast();
                                            }
                                            if (!surface.inputOpen) keyCatcher.forceActiveFocus();
                                            mouse.accepted = true;
                                        }
                                    }
                                }
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

                // Liquid Split Pill 1: Media Player + Controls
                Item {
                    id: mediaSlotWrap
                    height: Theme.islandHeight
                    clip: true
                    width: surface.hasLockMedia ? (Theme.splitGap + mediaPill.width) : 0
                    opacity: surface.hasLockMedia ? 1.0 : 0.0
                    visible: width > 0.5 || opacity > 0.01

                    Behavior on width {
                        NumberAnimation {
                            duration: surface.hasLockMedia ? Theme.springMs : Theme.smoothMs
                            easing.type: surface.hasLockMedia ? Easing.OutBack : Easing.OutCubic
                            easing.overshoot: 0.75
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: surface.hasLockMedia ? 220 : 160; easing.type: Easing.OutCubic }
                    }

                    ClippingRectangle {
                        id: mediaPill
                        x: surface.hasLockMedia ? Theme.splitGap : 0
                        height: Theme.islandHeight
                        width: Math.min(280, Math.max(168, Math.ceil(mediaRow.implicitWidth) + 28))
                        radius: Theme.islandRadius
                        color: Theme.gooeyEnabled ? "transparent" : Theme.pillBg
                        border.width: Theme.gooeyEnabled ? 0 : 1
                        border.color: Theme.borderSubtle
                        scale: surface.hasLockMedia ? 1.0 : 0.86

                        HoverHandler {
                            onHoveredChanged: surface.pillHovered = hovered
                        }

                        Behavior on x {
                            NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                        }

                        Row {
                            id: mediaRow
                            anchors.centerIn: parent
                            spacing: 8

                            Row {
                                id: eq
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2.5
                                height: 15
                                readonly property var maxH: [9, 15, 11, 14]
                                readonly property var durs: [420, 340, 480, 380]
                                Repeater {
                                    model: 4
                                    delegate: Rectangle {
                                        required property int index
                                        id: eqBar
                                        width: 2.5
                                        radius: 1.25
                                        height: eq.maxH[index]
                                        y: Math.round((eq.height - height) / 2)
                                        color: MediaService.isPlaying ? Theme.accent : Theme.textMuted
                                        Behavior on color { ColorAnimation { duration: 200 } }
                                        transform: Scale { id: eqScale; origin.y: eqBar.height / 2; yScale: 0.3 }

                                        SequentialAnimation {
                                            running: MediaService.isPlaying && surface.hasLockMedia
                                            loops: Animation.Infinite
                                            onStopped: eqScale.yScale = 0.3
                                            NumberAnimation { target: eqScale; property: "yScale"; to: 1.0; duration: eq.durs[index]; easing.type: Easing.InOutSine }
                                            NumberAnimation { target: eqScale; property: "yScale"; to: 0.3; duration: eq.durs[index]; easing.type: Easing.InOutSine }
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: MediaService.trackTitle
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, 108)
                            }

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Repeater {
                                    model: [
                                        { key: "prev", icon: "prev" },
                                        { key: "play", icon: MediaService.isPlaying ? "pause" : "play" },
                                        { key: "next", icon: "next" }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 24
                                        height: 24
                                        radius: 12
                                        color: ctrlMouse.containsMouse ? Theme.cardHover : "transparent"
                                        scale: ctrlMouse.pressed ? 0.90 : 1.0
                                        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                        SvgIcon {
                                            anchors.centerIn: parent
                                            sourceName: modelData.icon
                                            iconSize: 12
                                            color: modelData.key === "play" ? Theme.text : Theme.textSub
                                        }

                                        MouseArea {
                                            id: ctrlMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                LockService.activeScreenName = surface.screenName;
                                                if (modelData.key === "prev") MediaService.previous();
                                                else if (modelData.key === "play") {
                                                    if (MediaService.isPlaying) {
                                                        SoundService.fadeOutMediaAndRun(550, function() {
                                                            if (MediaService.isPlaying) MediaService.togglePlay();
                                                        });
                                                    } else {
                                                        MediaService.togglePlay();
                                                    }
                                                }
                                                else MediaService.next();
                                                if (!surface.inputOpen) keyCatcher.forceActiveFocus();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Liquid Split Pill 2: System Alerts (Overheat / Low Battery / Charger)
                Item {
                    id: alertSlotWrap
                    height: Theme.islandHeight
                    clip: true
                    width: surface.hasLockAlert ? (Theme.splitGap + alertPill.width) : 0
                    opacity: surface.hasLockAlert ? 1.0 : 0.0
                    visible: width > 0.5 || opacity > 0.01

                    Behavior on width {
                        NumberAnimation {
                            duration: surface.hasLockAlert ? Theme.springMs : Theme.smoothMs
                            easing.type: surface.hasLockAlert ? Easing.OutBack : Easing.OutCubic
                            easing.overshoot: 0.75
                        }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: surface.hasLockAlert ? 220 : 160; easing.type: Easing.OutCubic }
                    }

                    ClippingRectangle {
                        id: alertPill
                        x: surface.hasLockAlert ? Theme.splitGap : 0
                        height: Theme.islandHeight
                        width: Math.min(248, Math.max(138, Math.ceil(alertRow.implicitWidth) + 34))
                        radius: Theme.islandRadius
                        color: Theme.gooeyEnabled ? "transparent" : Theme.pillBg
                        border.width: Theme.gooeyEnabled ? 0 : 1
                        border.color: Qt.rgba(alertTint.r, alertTint.g, alertTint.b, 0.45)
                        scale: surface.hasLockAlert ? 1.0 : 0.86

                        HoverHandler {
                            onHoveredChanged: surface.pillHovered = hovered
                        }

                        readonly property color alertTint: {
                            if (surface.lockAlertKind === "overheat") return Theme.dangerText;
                            if (surface.lockAlertKind === "charger") return (lockRoot.shellState && lockRoot.shellState.chargeIsCharging) ? Theme.ok : Theme.warn;
                            return Theme.warn;
                        }
                        readonly property string alertIcon: {
                            if (surface.lockAlertKind === "overheat") return "thermometer";
                            if (surface.lockAlertKind === "charger") return "bolt";
                            return "battery-low";
                        }
                        readonly property string alertMsg: {
                            if (surface.lockAlertKind === "overheat") {
                                return (TelemetryService.overheatAlert ? TelemetryService.cpuTempC : 92) + "℃ Overheat";
                            }
                            if (surface.lockAlertKind === "charger") {
                                return lockRoot.shellState ? lockRoot.shellState.chargeText : "Charging";
                            }
                            return (PowerService.lowBatteryAlert ? PowerService.batteryPct : 7) + "% Low Battery";
                        }

                        Behavior on x {
                            NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Qt.rgba(alertPill.alertTint.r, alertPill.alertTint.g, alertPill.alertTint.b, 0.10)
                        }

                        Row {
                            id: alertRow
                            anchors.centerIn: parent
                            spacing: 8

                            SvgIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                sourceName: alertPill.alertIcon
                                iconSize: 16
                                color: alertPill.alertTint
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: alertPill.alertMsg
                                color: alertPill.alertTint
                                font.family: Theme.fontMono
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, 178)
                            }
                        }
                    }
                }
                }
                }

                // Concentric Lock Notification Toast / Tray Card (anchored 10px from lockStageContainer pill)
                Rectangle {
                    id: lockNotifCard

                    readonly property bool isListMode: surface.notifTrayOpen && NotificationService.historyList.length > 0
                    readonly property bool isToastMode: !isListMode && NotificationService.activeToast !== null
                    readonly property bool showNotifCard: LockService.showNotifications
                        && !LockService.exiting
                        && !surface.inputOpen
                        && (isListMode || isToastMode)

                    width: Math.min(400, surface.width - 48)
                    height: notifCardCol.implicitHeight + 28
                    radius: 22
                    color: Theme.pillBg
                    border.width: 1
                    border.color: Theme.borderSubtle
                    clip: true

                    x: Math.round((surface.width - width) / 2)
                    readonly property real pillTopY: lockStageContainer.y + Theme.shaderPad
                    readonly property real openY: surface.isBottom
                        ? Math.round(pillTopY - height - 10)
                        : Math.round(pillTopY + Theme.islandHeight + 10)
                    y: openY + (showNotifCard ? 0 : (surface.isBottom ? 10 : -10))
                    opacity: showNotifCard ? 1.0 : 0.0
                    scale: showNotifCard ? 1.0 : 0.94
                    transformOrigin: surface.isBottom ? Item.Bottom : Item.Top
                    visible: opacity > 0.01

                    Behavior on height {
                        NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                    }
                    Behavior on y {
                        NumberAnimation { duration: showNotifCard ? Theme.springMs : Theme.smoothMs; easing.type: showNotifCard ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 0.75 }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: showNotifCard ? Theme.springMs : Theme.smoothMs; easing.type: showNotifCard ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 0.85 }
                    }

                    HoverHandler {
                        onHoveredChanged: {
                            if (lockNotifCard.isToastMode) {
                                if (hovered) NotificationService.pauseToastTimer();
                                else NotificationService.resumeToastTimer();
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: function(mouse) { mouse.accepted = true; }
                    }

                    ColumnLayout {
                        id: notifCardCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 14
                        spacing: 10

                        // ── MODE A: NOTIFICATION LIST HEADER ──
                        RowLayout {
                            visible: lockNotifCard.isListMode
                            Layout.fillWidth: true
                            spacing: 8

                            SvgIcon {
                                sourceName: "bell"
                                iconSize: 15
                                color: Theme.accent
                            }

                            Text {
                                text: "Notifications"
                                color: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }

                            Rectangle {
                                implicitWidth: countBadgeText.implicitWidth + 12
                                height: 20
                                radius: 10
                                color: Theme.surfaceRaised
                                border.width: 1
                                border.color: Theme.borderSubtle

                                Text {
                                    id: countBadgeText
                                    anchors.centerIn: parent
                                    text: String(NotificationService.historyList.length)
                                    color: Theme.textSub
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                }
                            }

                            Rectangle {
                                visible: LockService.hideNotifContent
                                width: 22
                                height: 20
                                radius: 7
                                color: Theme.surfaceRaised
                                border.width: 1
                                border.color: Theme.borderSubtle

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: "eye-off"
                                    iconSize: 11
                                    color: Theme.textMuted
                                }
                            }

                            Item { Layout.fillWidth: true }

                            PillButton {
                                visible: NotificationService.historyList.length > 0
                                text: "Clear All"
                                iconName: "trash"
                                iconSize: 12
                                fixedHeight: 28
                                radius: 9
                                danger: true
                                onClicked: {
                                    NotificationService.clearAll();
                                    surface.notifTrayOpen = false;
                                    if (!surface.inputOpen) keyCatcher.forceActiveFocus();
                                }
                            }

                            Rectangle {
                                width: 28
                                height: 28
                                radius: 9
                                color: closeTrayMouse.containsMouse ? Theme.cardHover : Theme.surfaceRaised
                                border.width: 1
                                border.color: closeTrayMouse.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.22) : Theme.borderSubtle
                                scale: closeTrayMouse.pressed ? 0.92 : 1.0

                                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                SvgIcon {
                                    anchors.centerIn: parent
                                    sourceName: "close"
                                    iconSize: 13
                                    color: closeTrayMouse.containsMouse ? Theme.text : Theme.textSub
                                }

                                MouseArea {
                                    id: closeTrayMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        surface.notifTrayOpen = false;
                                        if (!surface.inputOpen) keyCatcher.forceActiveFocus();
                                    }
                                }
                            }
                        }

                        // ── MODE A: SCROLLABLE NOTIFICATION LIST ──
                        Flickable {
                            id: notifListFlick
                            visible: lockNotifCard.isListMode
                            Layout.fillWidth: true
                            Layout.preferredHeight: Math.min(notifListCol.implicitHeight, 340)
                            contentWidth: width
                            contentHeight: notifListCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            interactive: contentHeight > height

                            ColumnLayout {
                                id: notifListCol
                                width: notifListFlick.width
                                spacing: 6

                                Repeater {
                                    model: lockNotifCard.isListMode ? NotificationService.historyList : []
                                    delegate: Rectangle {
                                        id: notifItemCard
                                        required property var modelData
                                        required property int index

                                        Layout.fillWidth: true
                                        implicitHeight: itemRow.implicitHeight + 18
                                        radius: 14
                                        clip: true
                                        color: itemHover.hovered ? Theme.cardHover : Theme.cardBg
                                        border.width: 1
                                        border.color: itemHover.hovered
                                            ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.22)
                                            : Theme.borderSubtle

                                        Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

                                        HoverHandler { id: itemHover }

                                        RowLayout {
                                            id: itemRow
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 10

                                            // Concentric 34x34 icon well
                                            Rectangle {
                                                Layout.preferredWidth: 34
                                                Layout.preferredHeight: 34
                                                Layout.alignment: Qt.AlignTop
                                                radius: 10
                                                clip: true
                                                color: Theme.surfaceRaised
                                                border.width: 1
                                                border.color: Theme.borderSubtle

                                                SvgIcon {
                                                    anchors.centerIn: parent
                                                    sourceName: LockService.hideNotifContent ? "lock" : "bell"
                                                    iconSize: 15
                                                    color: notifItemCard.index === 0 ? Theme.accent : Theme.textSub
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 2

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    spacing: 6

                                                    Text {
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 0
                                                        text: notifItemCard.modelData ? (notifItemCard.modelData.appName || "System") : ""
                                                        color: Theme.textSub
                                                        font.family: Theme.fontSans
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: notifItemCard.modelData ? (notifItemCard.modelData.timeText || "now") : "now"
                                                        color: Theme.textMuted
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: 10
                                                    }
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    text: LockService.hideNotifContent
                                                        ? "New notification"
                                                        : (notifItemCard.modelData ? (notifItemCard.modelData.summary || "Notification") : "")
                                                    color: Theme.text
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 0
                                                    visible: LockService.hideNotifContent || (notifItemCard.modelData && notifItemCard.modelData.body !== "")
                                                    text: LockService.hideNotifContent
                                                        ? "Content hidden on lock screen"
                                                        : (notifItemCard.modelData ? notifItemCard.modelData.body : "")
                                                    color: LockService.hideNotifContent ? Theme.textMuted : Theme.textSub
                                                    font.family: Theme.fontSans
                                                    font.pixelSize: LockService.hideNotifContent ? 11 : 12
                                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                                    maximumLineCount: 2
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            // Per-item dismiss button
                                            Rectangle {
                                                Layout.preferredWidth: 26
                                                Layout.preferredHeight: 26
                                                Layout.alignment: Qt.AlignTop
                                                radius: 8
                                                color: dismissItemMouse.containsMouse ? Theme.surfaceRaised : "transparent"
                                                scale: dismissItemMouse.pressed ? 0.90 : 1.0

                                                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                                                SvgIcon {
                                                    anchors.centerIn: parent
                                                    sourceName: "close"
                                                    iconSize: 12
                                                    color: dismissItemMouse.containsMouse ? Theme.text : Theme.textMuted
                                                }

                                                MouseArea {
                                                    id: dismissItemMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (notifItemCard.modelData) {
                                                            NotificationService.dismissById(notifItemCard.modelData.id);
                                                        }
                                                        if (!surface.inputOpen) keyCatcher.forceActiveFocus();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── MODE B: ACTIVE TOAST CARD ──
                        Rectangle {
                            visible: lockNotifCard.isToastMode
                            Layout.fillWidth: true
                            implicitHeight: toastContentCol.implicitHeight + 20
                            radius: 14
                            clip: true
                            color: Theme.cardBg
                            border.width: 1
                            border.color: Theme.borderSubtle

                            ColumnLayout {
                                id: toastContentCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Rectangle {
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 36
                                        Layout.alignment: Qt.AlignTop
                                        radius: 10
                                        clip: true
                                        color: Theme.surfaceRaised
                                        border.width: 1
                                        border.color: Theme.borderSubtle

                                        SvgIcon {
                                            anchors.centerIn: parent
                                            sourceName: LockService.hideNotifContent ? "lock" : "bell"
                                            iconSize: 16
                                            color: Theme.accent
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 2

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 6

                                            Text {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                text: NotificationService.activeToast ? (NotificationService.activeToast.appName || "System") : ""
                                                color: Theme.textSub
                                                font.family: Theme.fontSans
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                text: NotificationService.activeToast ? (NotificationService.activeToast.timeText || "now") : "now"
                                                color: Theme.textMuted
                                                font.family: Theme.fontMono
                                                font.pixelSize: 11
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: LockService.hideNotifContent
                                                ? "New notification"
                                                : (NotificationService.activeToast ? (NotificationService.activeToast.summary || "Notification") : "")
                                            color: Theme.text
                                            font.family: Theme.fontSans
                                            font.pixelSize: 14
                                            font.weight: Font.Bold
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                Text {
                                    visible: LockService.hideNotifContent || (NotificationService.activeToast && NotificationService.activeToast.body !== "")
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.leftMargin: 46
                                    text: LockService.hideNotifContent
                                        ? "Content hidden on lock screen"
                                        : (NotificationService.activeToast ? NotificationService.activeToast.body : "")
                                    color: LockService.hideNotifContent ? Theme.textMuted : Theme.textSub
                                    font.family: Theme.fontSans
                                    font.pixelSize: LockService.hideNotifContent ? 11 : 12
                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // ── MODE B: TOAST ACTION BAR ──
                        RowLayout {
                            visible: lockNotifCard.isToastMode
                            Layout.fillWidth: true
                            spacing: 8

                            PillButton {
                                visible: NotificationService.historyList.length > 1
                                fillWidth: true
                                fixedHeight: 32
                                radius: 10
                                subtle: true
                                iconName: "bell"
                                iconSize: 13
                                text: "View All (" + NotificationService.historyList.length + ")"
                                onClicked: {
                                    NotificationService.dismissToast();
                                    surface.notifTrayOpen = true;
                                    if (!surface.inputOpen) keyCatcher.forceActiveFocus();
                                }
                            }

                            PillButton {
                                fillWidth: true
                                fixedHeight: 32
                                radius: 10
                                iconName: "close"
                                iconSize: 13
                                text: "Dismiss"
                                onClicked: {
                                    NotificationService.dismissToast();
                                    if (!surface.inputOpen) keyCatcher.forceActiveFocus();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
