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

            // Dim scrim matching LockScreen idle state
            Rectangle {
                anchors.fill: parent
                color: Theme.pillBg
                opacity: transWin.animProgress * (LockService.dimOpacity / 100.0)
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
            property bool notifTrayOpen: false
            property real shakeX: 0

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

                // Current desktop wallpaper (already faded in by transitionOverlay)
                Image {
                    anchors.fill: parent
                    source: lockRoot.resolvedWallpaperUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: false
                    cache: true
                    smooth: true
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
                        if (surface.inputOpen && passwordInput.text.length === 0 && !LockService.authenticating) {
                            surface.inputOpen = false;
                            idleCollapseTimer.stop();
                            keyCatcher.forceActiveFocus();
                        } else if (surface.inputOpen) {
                            passwordInput.forceActiveFocus();
                        }
                    }
                }

                // Statusbar Lock Pill Row (main lock pill + orbiting media & system alert split pills)
                Row {
                    id: lockPillRow
                    spacing: 0
                    height: Theme.islandHeight
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: surface.isBottom
                        ? Math.round(surface.height - height - Theme.topOffsetHover)
                        : Math.round(Theme.topOffsetHover)
                    transform: Translate { x: surface.shakeX }

                ClippingRectangle {
                    id: mainPill

                    readonly property real slotsTargetWidth: slotLockedIcon.targetWidth + slotPassword.targetWidth + slotNotif.targetWidth
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

                            // 3. Inline Notification Bell Slot
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
                        color: Theme.pillBg
                        border.width: 1
                        border.color: Theme.borderSubtle
                        scale: surface.hasLockMedia ? 1.0 : 0.86

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
                                                else if (modelData.key === "play") MediaService.togglePlay();
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
                        color: Theme.pillBg
                        border.width: 1
                        border.color: Qt.rgba(alertTint.r, alertTint.g, alertTint.b, 0.45)
                        scale: surface.hasLockAlert ? 1.0 : 0.86

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

                // Concentric Lock Notification Toast / Tray Card (anchored 10px from lockPillRow)
                Rectangle {
                    id: lockNotifCard

                    readonly property bool showNotifCard: LockService.showNotifications
                        && !LockService.exiting
                        && !surface.inputOpen
                        && (NotificationService.activeToast !== null || (surface.notifTrayOpen && NotificationService.historyList.length > 0))
                    readonly property var cardItems: surface.notifTrayOpen
                        ? NotificationService.historyList.slice(0, 3)
                        : (NotificationService.activeToast ? [NotificationService.activeToast] : [])

                    width: Math.min(380, surface.width - 48)
                    height: notifCardCol.implicitHeight + 28
                    radius: 22
                    color: Theme.pillBg
                    border.width: 1
                    border.color: Theme.borderSubtle
                    clip: true

                    x: Math.round((surface.width - width) / 2)
                    readonly property real openY: surface.isBottom
                        ? Math.round(lockPillRow.y - height - 10)
                        : Math.round(lockPillRow.y + lockPillRow.height + 10)
                    y: openY + (showNotifCard ? 0 : (surface.isBottom ? 10 : -10))
                    opacity: showNotifCard ? 1.0 : 0.0
                    scale: showNotifCard ? 1.0 : 0.94
                    transformOrigin: surface.isBottom ? Item.Bottom : Item.Top
                    visible: opacity > 0.01

                    Behavior on y {
                        NumberAnimation { duration: showNotifCard ? Theme.springMs : Theme.smoothMs; easing.type: showNotifCard ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 0.75 }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: showNotifCard ? Theme.springMs : Theme.smoothMs; easing.type: showNotifCard ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 0.85 }
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

                        Repeater {
                            model: lockNotifCard.cardItems
                            delegate: ColumnLayout {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: 4

                                Rectangle {
                                    visible: index > 0
                                    Layout.fillWidth: true
                                    Layout.bottomMargin: 4
                                    height: 1
                                    color: Theme.borderSubtle
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 7

                                    Rectangle {
                                        width: 7
                                        height: 7
                                        radius: 3.5
                                        color: Theme.danger
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: modelData ? (modelData.appName || "System") : ""
                                        color: Theme.textSub
                                        font.family: Theme.fontSans
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: modelData ? (modelData.timeText || "now") : "now"
                                        color: Theme.textMuted
                                        font.family: Theme.fontMono
                                        font.pixelSize: 11
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: LockService.hideNotifContent ? "New notification" : (modelData ? (modelData.summary || "Notification") : "")
                                    color: Theme.text
                                    font.family: Theme.fontSans
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    visible: LockService.hideNotifContent || (modelData && modelData.body !== "")
                                    text: LockService.hideNotifContent ? "Content hidden on lock screen" : (modelData ? modelData.body : "")
                                    color: LockService.hideNotifContent ? Theme.textMuted : Theme.textSub
                                    font.family: Theme.fontSans
                                    font.pixelSize: LockService.hideNotifContent ? 11 : 12
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 2
                            spacing: 8

                            PillButton {
                                text: "Dismiss"
                                subtle: true
                                onClicked: {
                                    NotificationService.dismissToast();
                                    surface.notifTrayOpen = false;
                                    if (!surface.inputOpen) keyCatcher.forceActiveFocus();
                                }
                            }

                            PillButton {
                                visible: surface.notifTrayOpen && NotificationService.historyList.length > 1
                                text: "Clear All"
                                danger: true
                                onClicked: {
                                    NotificationService.clearAll();
                                    surface.notifTrayOpen = false;
                                    if (!surface.inputOpen) keyCatcher.forceActiveFocus();
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
    }
}
