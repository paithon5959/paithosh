import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import ".."
import "../services"
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
    WlrLayershell.layer: (!shellState.hideBarFullscreen && CompositorService.isFullscreenFor(modelData)) ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.namespace: "paithosh-island"
    WlrLayershell.keyboardFocus: isSearchOnThisScreen ? WlrKeyboardFocus.Exclusive : (isAppExpandedOnScreen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)

    readonly property bool isBottom: shellState.barPosition === "bottom"
    readonly property bool isActiveScreen: shellState.activeScreen === modelData
    readonly property bool isPopoverTargetScreen: isActiveScreen || (!shellState.activeScreen && Quickshell.screens.length > 0 && modelData === Quickshell.screens[0])
    readonly property bool isPopoverOpenOnThisScreen: isActiveScreen && shellState.openPopover !== ""
    readonly property bool isSearchOnThisScreen: isActiveScreen && shellState.openPopover === "search"
    readonly property bool isAppExpandedOnScreen: isActiveScreen && shellState.islandApp !== ""
    readonly property bool hasActivity: anyTransientSlot || isPopoverOpenOnThisScreen || isAppExpandedOnScreen || hasAlert || ScreenRecordService.recording
    property bool isDodged: false
    property bool dodgeUnlocked: false
    readonly property bool dodgeEligible: shellState.dodgeCursor && !isPopoverOpenOnThisScreen && !isAppExpandedOnScreen && !shellState.superHeld && !dodgeUnlocked
    readonly property bool pointerOverIsland: topEdgeHover.hovered
    readonly property bool suppressSuperDrag: !root.isHidden && root.pointerOverIsland && root.shellState.superHeld
    readonly property bool isHidden: root.isDodged || ((shellState.manualHideBar || (shellState.hideBarFullscreen && CompositorService.isFullscreenFor(modelData)) || (shellState.autoHideOnOverlap && CompositorService.isOverlappedFor(modelData, shellState.barPosition))) && !root.hovered && !topEdgeHover.hovered && !hasActivity && !(shellState.superPeekBar && isActiveScreen))

    function syncIslandLayoutToState() {
        if (!isPopoverTargetScreen) return;
        shellState.activeIslandHidden = root.isHidden;
        shellState.activeIslandEdgeOffset = stageContainer.animatedEdgeOffset;
    }

    onIsPopoverTargetScreenChanged: syncIslandLayoutToState()
    onIsHiddenChanged: syncIslandLayoutToState()
    Component.onCompleted: syncIslandLayoutToState()

    onSuppressSuperDragChanged: {
        if (suppressSuperDrag) {
            dodgeUnlocked = true;
            shellState.superUsedWithIsland = true;
        }
        CompositorService.setIslandDragSuppressedFor(modelData ? modelData.name : "default", suppressSuperDrag);
    }

    Component.onDestruction: {
        CompositorService.setIslandDragSuppressedFor(modelData ? modelData.name : "default", false);
    }

    onPointerOverIslandChanged: {
        if (pointerOverIsland) {
            if (dodgeEligible) {
                isDodged = true;
            } else if (shellState.superHeld) {
                dodgeUnlocked = true;
                shellState.superUsedWithIsland = true;
            }
        } else {
            dodgeUnlocked = false;
            root.hovered = false;
        }
    }

    onDodgeEligibleChanged: {
        if (!dodgeEligible) {
            isDodged = false;
        } else if (pointerOverIsland) {
            isDodged = true;
        }
    }

    readonly property string attachedTitle: {
        if (shellState.islandApp === "settings") return "Settings (Island)";
        if (shellState.islandApp === "files") return "Files (Island)";
        if (shellState.islandApp === "music") return "Music (Island)";
        if (shellState.islandApp === "picker") {
            if (shellState.pickerDirectory) return "Select Folder (Island)";
            return shellState.pickerMode === "download" ? "Save Location (Island)" : "Upload Location (Island)";
        }
        if (shellState.islandApp === "portal") return "Screen Share (Island)";
        if (shellState.islandApp === "weather") return "Weather Forecast";
        return "";
    }
    readonly property string activeTitle: isAppExpandedOnScreen ? attachedTitle : CompositorService.activeTitleFor(modelData)
    readonly property bool hasFocus: activeTitle !== ""
    readonly property bool hasNotifBadge: NotificationService.hasUnreadBadge
    readonly property bool hasMedia: MediaService.active && !isAppExpandedOnScreen
    readonly property int currentWs: CompositorService.workspaceIdFor(modelData)

    readonly property int alertMode: {
        if (shellState.previewAlertMode > 0) return shellState.previewAlertMode;
        if (TelemetryService.overheatAlert) return 1;
        if (PowerService.lowBatteryAlert) return 2;
        return 0;
    }
    readonly property bool hasAlert: alertMode > 0 && !isAppExpandedOnScreen

    readonly property bool anyTransientSlot: isSearchOnThisScreen || shellState.osdOpen || shellState.inputSlotOpen || shellState.wsSlotOpen || shellState.kdeSlotOpen || shellState.chargeSlotOpen || shellState.reloadSlotOpen || PackageService.statusEventOpen || PackageService.activeOpText !== "" || BackupService.busy

    property bool bootEntered: false
    readonly property bool isReloadExiting: shellState.reloadPhase === "exiting" || shellState.reloadPhase === "committing" || shellState.reloadPhase === "revealing"
    readonly property bool isSessionExiting: shellState.sessionPhase === "fading" || shellState.sessionPhase === "executing"
    readonly property bool isLifecycleExiting: isReloadExiting || isSessionExiting
    readonly property bool isTucked: !bootEntered || isLifecycleExiting
    property bool hovered: false
    property bool dropHovered: false
    property string clockText: Qt.formatTime(new Date(), "hh:mm")
    property real shownOsdVal: shellState.osdValue

    Behavior on shownOsdVal {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    onIsSearchOnThisScreenChanged: {
        if (isSearchOnThisScreen) {
            searchInput.text = shellState.searchQuery;
            searchFocusTimer.restart();
        } else {
            searchInput.focus = false;
        }
    }

    Timer {
        id: bootEntranceTimer
        interval: 35
        running: true
        repeat: false
        onTriggered: root.bootEntered = true
    }

    Timer {
        id: searchFocusTimer
        interval: 60
        repeat: false
        onTriggered: searchInput.forceActiveFocus()
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: root.clockText = Qt.formatTime(new Date(), "hh:mm")
    }

    property bool _cachedSettings: false
    property bool _cachedFiles: false
    property bool _cachedMusic: false
    property bool _cachedPicker: false
    property bool _cachedWeather: false

    function _markAppCached(appName) {
        if (!Theme.reduceMotion) return;
        if (appName === "settings") _cachedSettings = true;
        else if (appName === "files") _cachedFiles = true;
        else if (appName === "music") _cachedMusic = true;
        else if (appName === "picker") _cachedPicker = true;
        else if (appName === "weather") _cachedWeather = true;
    }

    Connections {
        target: Theme
        function onReduceMotionChanged() {
            if (!Theme.reduceMotion) {
                root._cachedSettings = false;
                root._cachedFiles = false;
                root._cachedMusic = false;
                root._cachedPicker = false;
                root._cachedWeather = false;
            } else if (root.isAppExpandedOnScreen) {
                root._markAppCached(root.shellState.islandApp);
            }
        }
    }

    onIsAppExpandedOnScreenChanged: {
        if (isAppExpandedOnScreen) {
            _markAppCached(shellState.islandApp);
            if (shellState.islandApp === "settings" && settingsLoader.item) {
                settingsLoader.item.openPage(shellState.settingsPage || "home");
                expandedFocusItem.forceActiveFocus();
            } else if (shellState.islandApp === "picker" && pickerLoader.item) {
                pickerLoader.item.initFromState();
                Qt.callLater(() => { if (pickerLoader.item) pickerLoader.item.forceActiveFocus(); });
            } else if (shellState.islandApp === "files" && filesLoader.item) {
                Qt.callLater(() => { if (filesLoader.item) filesLoader.item.forceActiveFocus(); });
            } else if (shellState.islandApp === "music" && musicLoader.item) {
                Qt.callLater(() => { if (musicLoader.item) musicLoader.item.forceActiveFocus(); });
            } else {
                expandedFocusItem.forceActiveFocus();
            }
        }
    }

    Connections {
        target: root.shellState
        function onIslandAppChanged() {
            if (root.isAppExpandedOnScreen) {
                root._markAppCached(root.shellState.islandApp);
                if (root.shellState.islandApp === "settings" && settingsLoader.item) {
                    settingsLoader.item.openPage(root.shellState.settingsPage || "home");
                    expandedFocusItem.forceActiveFocus();
                } else if (root.shellState.islandApp === "picker" && pickerLoader.item) {
                    pickerLoader.item.initFromState();
                    Qt.callLater(() => { if (pickerLoader.item) pickerLoader.item.forceActiveFocus(); });
                } else if (root.shellState.islandApp === "files" && filesLoader.item) {
                    Qt.callLater(() => { if (filesLoader.item) filesLoader.item.forceActiveFocus(); });
                } else if (root.shellState.islandApp === "music" && musicLoader.item) {
                    Qt.callLater(() => { if (musicLoader.item) musicLoader.item.forceActiveFocus(); });
                }
            }
        }
    }

    // Transient VPN status slot (shown briefly on connect/disconnect or while busy)
    property bool vpnTransientOpen: false
    property bool _vpnInitialized: false

    function formatVpnLabel(tunnelName) {
        if (!tunnelName) return "VPN Off";
        const parts = tunnelName.split(/[-_]/).filter(p => p.length > 0);
        const prefixes = ["wg", "vpn", "ovpn", "proton"];
        let loc = parts[0] || tunnelName;
        if (parts.length > 1 && prefixes.indexOf(parts[0].toLowerCase()) !== -1) {
            loc = parts[1];
        }
        if (/^[a-zA-Z]{2}$/.test(loc)) {
            loc = loc.toUpperCase();
        }
        return "VPN (" + loc + ")";
    }

    Timer {
        id: vpnStartupGraceTimer
        interval: 1500
        running: true
        repeat: false
        onTriggered: root._vpnInitialized = true
    }

    Timer {
        id: vpnTransientTimer
        interval: 3000
        repeat: false
        onTriggered: root.vpnTransientOpen = false
    }

    Connections {
        target: VpnProxyService
        function onActiveTunnelChanged() {
            if (!root._vpnInitialized) return;
            root.vpnTransientOpen = true;
            vpnTransientTimer.restart();
        }
        function onImportCompleted() {
            if (root.shellState) {
                root.shellState.settingsPage = "vpn";
                root.shellState.islandApp = "settings";
                root.shellState.islandExpanded = true;
            }
            if (settingsLoader.item) {
                settingsLoader.item.openPage("vpn");
            }
            expandedFocusItem.forceActiveFocus();
        }
    }

    Item {
        id: hoverTrigger
        z: 50
        y: root.isBottom ? (parent.height - height) : 0
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(contentRow.width + 16, 260)
        height: Math.max(Theme.topOffsetHover, Theme.topOffsetRest) + Theme.islandHeight + 10

        HoverHandler {
            id: topEdgeHover
        }
    }

    Item {
        id: fullScreenMask
        anchors.fill: parent
    }

    Item {
        id: filesCardMask
        x: Math.round((parent.width - 960) / 2)
        y: 0
        width: 960
        height: 710
    }

    Item {
        id: emptyMask
        width: 0
        height: 0
    }

    Timer {
        id: dodgeCursorPollTimer
        interval: 100
        repeat: true
        running: root.isDodged && CompositorService.isHyprland
        onTriggered: {
            if (!dodgeCursorProc.running) dodgeCursorProc.running = true;
        }
    }

    Process {
        id: dodgeCursorProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.isDodged) return;
                const raw = (text || "").trim();
                const parts = raw.split(",");
                if (parts.length < 2) return;
                const cx = parseFloat(parts[0].trim());
                const cy = parseFloat(parts[1].trim());
                if (isNaN(cx) || isNaN(cy)) return;
                const mon = CompositorService.monitorBoundsFor(root.modelData);
                const x0 = mon.x + hoverTrigger.x;
                const x1 = x0 + hoverTrigger.width;
                const y0 = root.isBottom ? (mon.y + mon.height - hoverTrigger.height) : mon.y;
                const y1 = y0 + hoverTrigger.height;
                if (cx < x0 || cx > x1 || cy < y0 || cy > y1) {
                    root.isDodged = false;
                }
            }
        }
    }

    mask: Region {
        item: root.isDodged ? emptyMask : (root.isHidden ? hoverTrigger : (root.isAppExpandedOnScreen ? (root.shellState.islandApp === "files" ? filesCardMask : fullScreenMask) : hitbox))
    }

    Item {
        id: expandedFocusItem
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            if (root.isAppExpandedOnScreen) root.shellState.collapseIslandApp();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: (root.isAppExpandedOnScreen && root.shellState.islandApp === "portal")
            ? Qt.rgba(0, 0, 0, 0.72)
            : "transparent"

        Behavior on color {
            ColorAnimation { duration: 200; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.isAppExpandedOnScreen
            onClicked: root.shellState.collapseIslandApp()
        }
    }

    Item {
        id: hitbox
        x: stageContainer.x + Theme.shaderPad - 8
        y: root.isBottom ? Math.min(parent.height - 6, stageContainer.y + Theme.shaderPad - 10) : 0
        width: contentRow.width + 16
        height: root.isBottom
            ? Math.max(6, parent.height - y)
            : Math.max(6, stageContainer.y + Theme.shaderPad + Theme.islandHeight + 10)
    }

    Item {
        id: stageContainer
        anchors.horizontalCenter: parent.horizontalCenter
        Keys.onEscapePressed: (event) => {
            if (root.isAppExpandedOnScreen) {
                root.shellState.collapseIslandApp();
                event.accepted = true;
            }
        }
        property real animatedEdgeOffset: (root.hovered || root.isPopoverOpenOnThisScreen || root.isAppExpandedOnScreen) ? Theme.topOffsetHover : Theme.topOffsetRest
        onAnimatedEdgeOffsetChanged: root.syncIslandLayoutToState()
        property real animatedHideOffset: root.isTucked ? 32 : (root.isHidden ? 26 : 0)
        property real bottomProgress: root.isBottom ? 1.0 : 0.0
        Behavior on animatedEdgeOffset {
            NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
        }
        Behavior on animatedHideOffset {
            NumberAnimation {
                duration: root.isLifecycleExiting ? Math.max(100, Math.round(170 / Math.max(0.5, Theme.speedMultiplier))) : Theme.springMs
                easing.type: root.isLifecycleExiting ? Easing.InCubic : Theme.motionEasing
                easing.overshoot: Theme.reduceMotion ? 0.0 : 1.0
            }
        }
        Behavior on bottomProgress {
            NumberAnimation {
                duration: Math.round(Theme.springMs * 1.1)
                easing.type: Theme.motionEasing
                easing.overshoot: Theme.reduceMotion ? 0.0 : 0.6
            }
        }
        readonly property real topY: animatedEdgeOffset - Theme.shaderPad - animatedHideOffset
        readonly property real bottomY: root.height - height + Theme.shaderPad - animatedEdgeOffset + animatedHideOffset
        y: topY + (bottomY - topY) * bottomProgress
        width: contentRow.width + Theme.shaderPad * 2
        height: mainPill.height + Theme.shaderPad * 2
        opacity: (root.isHidden || root.isTucked) ? 0.0 : 1.0
        scale: Theme.reduceMotion ? 1.0 : (root.isTucked ? 0.76 : (root.isHidden ? 0.65 : 1.0))
        transformOrigin: root.isBottom ? Item.Bottom : Item.Top

        Behavior on opacity {
            NumberAnimation {
                duration: root.isLifecycleExiting ? Math.max(90, Math.round(160 / Math.max(0.5, Theme.speedMultiplier))) : (Theme.reduceMotion ? Theme.smoothMs : 240)
                easing.type: root.isLifecycleExiting ? Easing.InCubic : Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.isLifecycleExiting ? Math.max(100, Math.round(170 / Math.max(0.5, Theme.speedMultiplier))) : Theme.springMs
                easing.type: root.isLifecycleExiting ? Easing.InCubic : Theme.motionEasing
                easing.overshoot: Theme.reduceMotion ? 0.0 : 1.05
            }
        }

        // Liquid Gooey Background Layer (1:1 geometry sync with foreground pills; auto-disabled when app expanded)
        Item {
            id: gooSource
            anchors.fill: parent
            layer.enabled: Theme.effectiveGooey && !root.isAppExpandedOnScreen
            layer.effect: ShaderEffect {
                fragmentShader: Qt.resolvedUrl("../assets/shaders/gooey.frag.qsb")
                property size texelSize: Qt.size(1.0 / Math.max(1, gooSource.width), 1.0 / Math.max(1, gooSource.height))
                property real threshold: 0.46
                property real softness: 0.06
                property color pillColor: Theme.pillBg
                property color pillColorMid: Theme.pillBgMid
                property color pillColor2: Theme.pillBg2
                property real angleRad: Theme.gradientAngle * Math.PI / 180.0
                property real gradEnabled: Theme.effectiveShellGradient ? 1.0 : 0.0
            }

            Rectangle {
                id: mainBg
                x: Theme.shaderPad + mainPill.x
                y: Theme.shaderPad
                width: mainPill.width
                height: mainPill.height
                radius: mainPill.radius
                color: Theme.pillBg
                ThemeGradientFill {
                    anchors.fill: parent
                    enabled: Theme.shellGradientEnabled && !gooSource.layer.enabled
                    color1: Theme.pillBg
                    colorMid: Theme.pillBgMid
                    color2: Theme.pillBg2
                    cornerRadius: mainBg.radius
                }
            }

            Rectangle {
                id: mediaBg
                x: Theme.shaderPad + mediaSlotWrap.x + mediaPill.x
                y: Theme.shaderPad + mediaSlotWrap.y + (Theme.islandHeight - height) / 2
                width: Math.max(0, Math.min(mediaPill.width, mediaSlotWrap.width - mediaPill.x))
                height: mediaPill.height
                radius: Theme.islandRadius
                color: Theme.pillBg
                scale: mediaPill.scale
                opacity: mediaSlotWrap.opacity
                visible: width > 1 && opacity > 0.01
                ThemeGradientFill {
                    anchors.fill: parent
                    enabled: Theme.shellGradientEnabled && !gooSource.layer.enabled
                    color1: Theme.pillBg
                    colorMid: Theme.pillBgMid
                    color2: Theme.pillBg2
                    cornerRadius: mediaBg.radius
                }
            }

            Rectangle {
                id: alertBg
                x: Theme.shaderPad + alertSlotWrap.x + alertPill.x
                y: Theme.shaderPad + alertSlotWrap.y + (Theme.islandHeight - height) / 2
                width: Math.max(0, Math.min(alertPill.width, alertSlotWrap.width - alertPill.x))
                height: alertPill.height
                radius: Theme.islandRadius
                color: Theme.pillBg
                scale: alertPill.scale
                opacity: alertSlotWrap.opacity
                visible: width > 1 && opacity > 0.01
                ThemeGradientFill {
                    anchors.fill: parent
                    enabled: Theme.shellGradientEnabled && !gooSource.layer.enabled
                    color1: Theme.pillBg
                    colorMid: Theme.pillBgMid
                    color2: Theme.pillBg2
                    cornerRadius: alertBg.radius
                }
            }
        }

        // Crisp Foreground Content Layer
        Row {
            id: contentRow
            x: Theme.shaderPad
            y: Theme.shaderPad
            height: mainPill.height
            spacing: 0

            // Main Status Pill (expands smoothly to host Settings / Files / Picker)
            AdaptiveClipRect {
                id: mainPill
                // Uses slots' *target* widths so the frame leads the content instead of chasing it
                readonly property real slotsTargetWidth: {
                    let w = 0;
                    const kids = centerSlotsRow.children;
                    for (let i = 0; i < kids.length; ++i) if (kids[i].targetWidth !== undefined) w += kids[i].targetWidth;
                    return w;
                }
                readonly property int compactWidth: Math.max(260, Math.ceil(weatherLabel.implicitWidth + slotsTargetWidth + clockLabel.implicitWidth + 84))
                height: root.isAppExpandedOnScreen ? Math.min(root.shellState.islandApp === "weather" ? 320 : 626, root.height - 96) : Theme.islandHeight
                width: root.isAppExpandedOnScreen ? Math.min(root.shellState.islandApp === "weather" ? 680 : 920, root.width - 48) : compactWidth
                radius: root.isAppExpandedOnScreen ? 18 : Theme.islandRadius
                color: "transparent"
                border.width: root.dropHovered ? 2 : 1
                border.color: root.dropHovered ? Theme.accent : (root.isAppExpandedOnScreen ? Theme.borderSubtle : Qt.rgba(1, 1, 1, 0.12))
                Behavior on border.color { ColorAnimation { duration: Theme.smoothMs } }

                Behavior on width {
                    enabled: !Theme.reduceMotion || !root.isAppExpandedOnScreen
                    NumberAnimation {
                        duration: root.isAppExpandedOnScreen ? Theme.springMs : Math.round(Theme.springMs * 0.6)
                        easing.type: Theme.motionEasing
                        easing.overshoot: Theme.reduceMotion ? 0.0 : (root.isAppExpandedOnScreen ? 0.85 : 1.5)
                    }
                }
                Behavior on height {
                    enabled: !Theme.reduceMotion
                    NumberAnimation {
                        duration: root.isAppExpandedOnScreen ? Theme.springMs : 110
                        easing.type: root.isAppExpandedOnScreen ? Theme.motionEasing : Easing.OutCubic
                        easing.overshoot: Theme.reduceMotion ? 0.0 : 0.75
                    }
                }
                Behavior on radius {
                    enabled: !Theme.reduceMotion
                    NumberAnimation {
                        duration: Theme.smoothMs
                        easing.type: Easing.OutCubic
                    }
                }

                // Prevent clicks inside expanded island app from hitting outside-click MouseArea
                MouseArea {
                    anchors.fill: parent
                    enabled: root.isAppExpandedOnScreen
                    onClicked: function(mouse) { mouse.accepted = true; }
                }

                Item {
                    id: pillHeader
                    x: 0
                    y: root.isBottom ? (parent.height - height) : 0
                    width: parent.width
                    height: Theme.islandHeight

                    // Left Edge: Outdoor Weather Temperature
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

                    // Center Expanding Slots (centered in remaining gap between weatherLabel and clockLabel, never overlapping)
                    Row {
                        id: centerSlotsRow
                        x: Math.round(weatherLabel.x + weatherLabel.implicitWidth + Math.max(12, (clockLabel.x - (weatherLabel.x + weatherLabel.implicitWidth) - width) / 2))
                        y: Math.round((parent.height - height) / 2)
                        width: Math.min(implicitWidth, Math.max(0, clockLabel.x - (weatherLabel.x + weatherLabel.implicitWidth) - 24))
                        height: Theme.islandHeight
                        spacing: 0
                        clip: true

                    // 1. Focused Window Title Slot
                    IslandSlot {
                        id: slotWindow
                        open: root.hasFocus && !root.anyTransientSlot
                        maxSlotWidth: 340

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "  •  "
                            color: Theme.textMuted
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.activeTitle
                            color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.9)
                            font.family: Theme.fontSans
                            font.pixelSize: 20
                            font.weight: Font.Normal
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 270)
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "  •  "
                            color: Theme.textMuted
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                        }
                    }

                    // 1b. VPN Status Slot (transient on connect/disconnect or while busy)
                    IslandSlot {
                        id: slotVpn
                        open: (root.vpnTransientOpen || VpnProxyService.busy) && !root.isSearchOnThisScreen
                        maxSlotWidth: 190

                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: vpnInlineRow.implicitWidth + 16
                            height: 30
                            scale: vpnInlineMouse.pressed ? 0.94 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: Theme.springOvershoot } }

                            Row {
                                id: vpnInlineRow
                                anchors.centerIn: parent
                                spacing: 6

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 7
                                    height: 7
                                    radius: 3.5
                                    color: VpnProxyService.busy
                                           ? Theme.warn
                                           : (VpnProxyService.activeTunnel !== "" ? Theme.ok : Theme.textMuted)
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: VpnProxyService.busy
                                          ? (VpnProxyService.busyTunnel !== "" ? root.formatVpnLabel(VpnProxyService.busyTunnel) + "…" : "VPN…")
                                          : root.formatVpnLabel(VpnProxyService.activeTunnel)
                                    color: VpnProxyService.activeTunnel !== ""
                                           ? Theme.text
                                           : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.78)
                                    font.family: Theme.fontSans
                                    font.pixelSize: 14
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, 140)
                                }
                            }

                            MouseArea {
                                id: vpnInlineMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.hovered = true
                                onExited: root.hovered = false
                                onClicked: {
                                    if (VpnProxyService.activeTunnel !== "") {
                                        VpnProxyService.toggleTunnel(VpnProxyService.activeTunnel);
                                    } else if (root.shellState) {
                                        root.shellState.settingsPage = "vpn";
                                        root.shellState.islandApp = "settings";
                                        root.shellState.islandExpanded = true;
                                    }
                                }
                            }
                        }
                    }

                    // 2. Inline Global Search Slot
                    IslandSlot {
                        id: slotSearch
                        open: root.isSearchOnThisScreen
                        maxSlotWidth: 380

                        Item { width: 12; height: 1 }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: "search"
                            iconSize: 15
                            color: Theme.text
                        }

                        Item { width: 8; height: 1 }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            height: 34
                            width: Math.min(320, Math.max(240, 240 + searchInput.text.length * 5))
                            radius: 17
                            color: Qt.rgba(1, 1, 1, searchInput.activeFocus ? 0.16 : 0.10)
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, searchInput.activeFocus ? 0.40 : 0.16)
                            clip: true

                            Behavior on width {
                                NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                            }

                            AnimatedTextInput {
                                id: searchInput
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                verticalAlignment: TextInput.AlignVCenter
                                textColor: Theme.text
                                font.family: Theme.fontSans
                                font.pixelSize: 15
                                clip: true
                                selectByMouse: true
                                onTextChanged: shellState.searchQuery = text
                                Keys.onEscapePressed: shellState.closePopovers()
                                Keys.onDownPressed: {
                                    const q = text.trim();
                                    const n = AppService.searchApps(q, "All").slice(0, 4).length
                                            + (q !== "" ? SettingsSearchService.search(q).slice(0, 4).length : 0)
                                            + 2
                                            + (q !== "" ? 1 : 0);
                                    if (n > 0) shellState.searchSel = (shellState.searchSel + 1) % n;
                                }
                                Keys.onUpPressed: {
                                    const q = text.trim();
                                    const n = AppService.searchApps(q, "All").slice(0, 4).length
                                            + (q !== "" ? SettingsSearchService.search(q).slice(0, 4).length : 0)
                                            + 2
                                            + (q !== "" ? 1 : 0);
                                    if (n > 0) shellState.searchSel = (shellState.searchSel - 1 + n) % n;
                                }
                                Keys.onReturnPressed: {
                                    const q = text.trim();
                                    const apps = AppService.searchApps(q, "All").slice(0, 4);
                                    const settings = q !== "" ? SettingsSearchService.search(q).slice(0, 4) : [];
                                    const idx = shellState.searchSel;
                                    if (idx < apps.length) {
                                        AppService.launchApp(apps[idx]);
                                        shellState.closePopovers();
                                    } else if (idx < apps.length + settings.length) {
                                        const hit = settings[idx - apps.length];
                                        shellState.settingsSpotlight = q;
                                        shellState.settingsPage = hit.page;
                                        shellState.openIslandApp("settings", null);
                                    } else if (idx < apps.length + settings.length + 2) {
                                        const qIdx = idx - apps.length - settings.length;
                                        shellState.closePopovers();
                                        if (qIdx === 0) AppService.openExternalFiles();
                                        else AppService.openExternalSettings();
                                    } else if (q !== "") {
                                        AppService.searchWeb(q);
                                        shellState.closePopovers();
                                    }
                                }

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: "Search files, apps, web..."
                                    color: Theme.textMuted
                                    font.family: Theme.fontSans
                                    font.pixelSize: 14
                                    visible: searchInput.text === ""
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Item { width: 12; height: 1 }
                    }

                    // 3. Inline Volume / Brightness OSD Slot
                    IslandSlot {
                        id: slotOsd
                        open: shellState.osdOpen && !root.isSearchOnThisScreen
                        maxSlotWidth: 290

                        Item { width: 16; height: 1 }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: shellState.osdKind === "bri" ? "sun" : "volume"
                            iconSize: 20
                            color: shellState.osdKind === "mute" ? Theme.red : Theme.text
                        }

                        Item { width: 10; height: 1 }

                        Rectangle {
                            visible: shellState.osdKind !== "mute"
                            anchors.verticalCenter: parent.verticalCenter
                            width: 170
                            height: 8
                            radius: 4
                            color: Qt.rgba(1, 1, 1, 0.18)
                            clip: true

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                radius: 4
                                color: Theme.text
                                width: Math.max(0, Math.min(parent.width, parent.width * (shellState.osdValue / 100.0)))

                                Behavior on width {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        Text {
                            visible: shellState.osdKind === "mute"
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Audio Muted"
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Item { visible: shellState.osdKind !== "mute"; width: 10; height: 1 }

                        Text {
                            visible: shellState.osdKind !== "mute"
                            anchors.verticalCenter: parent.verticalCenter
                            width: 44
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(root.shownOsdVal) + "%"
                            color: Theme.text
                            font.family: Theme.fontMono
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }

                        Item { width: 14; height: 1 }
                    }

                    // 3b. Inline Input Indicator Slot (Caps Lock & Fcitx5 IM)
                    IslandSlot {
                        id: slotInputIndicator
                        open: shellState.inputSlotOpen && !root.isSearchOnThisScreen
                        maxSlotWidth: 250

                        Item { width: 16; height: 1 }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: shellState.inputSlotKind === "fcitx" ? "globe" : "keyboard"
                            iconSize: 18
                            color: (shellState.inputSlotKind === "fcitx" || shellState.inputSlotActive) ? Theme.text : Theme.textSub
                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }

                        Item { width: 10; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: shellState.inputSlotLabel
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            width: Math.min(implicitWidth, 124)
                        }

                        Item { width: 8; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "•"
                            color: Theme.textMuted
                            font.family: Theme.fontSans
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }

                        Item { width: 8; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: shellState.inputSlotBadge
                            color: (shellState.inputSlotKind === "fcitx" || shellState.inputSlotActive) ? Theme.text : Theme.textSub
                            font.family: Theme.fontSans
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        }

                        Item { width: 16; height: 1 }
                    }

                    // 4. Inline Workspace Switcher Slot
                    IslandSlot {
                        id: slotWs
                        open: shellState.wsSlotOpen && !root.isSearchOnThisScreen
                        maxSlotWidth: 280

                        Item { width: 14; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Workspace " + root.currentWs
                            color: Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }

                        Item { width: 8; height: 1 }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Repeater {
                                model: 4
                                delegate: Rectangle {
                                    required property int index
                                    readonly property int wsNum: index + 1
                                    readonly property bool isCurrent: root.currentWs === wsNum
                                    width: isCurrent ? 34 : 26
                                    height: 26
                                    radius: 13
                                    color: isCurrent ? Theme.accent : Qt.rgba(1, 1, 1, 0.14)
                                    scale: isCurrent ? 1.06 : 1.0

                                    Behavior on width {
                                        NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.25 }
                                    }
                                    Behavior on color {
                                        ColorAnimation { duration: 180 }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: String(wsNum)
                                        color: isCurrent ? Theme.accentFg : Qt.rgba(1, 1, 1, 0.72)
                                        font.family: Theme.fontSans
                                        font.pixelSize: 13
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }

                        Item { width: 14; height: 1 }
                    }

                    // 5. Inline KDE Connect Drag-Drop Status Slot
                    IslandSlot {
                        id: slotKde
                        open: shellState.kdeSlotOpen && !root.isSearchOnThisScreen
                        maxSlotWidth: 340

                        Item { width: 14; height: 1 }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: "smartphone"
                            iconSize: 16
                            color: Theme.ok
                        }

                        Item { width: 8; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: shellState.kdeText
                            color: Theme.ok
                            font.family: Theme.fontSans
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 280)
                        }

                        Item { width: 14; height: 1 }
                    }

                    // 5.5. Inline Shell / Config Reload Status Slot (replaces Quickshell corner popup)
                    IslandSlot {
                        id: slotReload
                        open: shellState.reloadSlotOpen && !root.isSearchOnThisScreen
                        maxSlotWidth: 280

                        readonly property color reloadTint: shellState.reloadSlotState === "loading"
                            ? Theme.accent
                            : (shellState.reloadSlotState === "error" ? Theme.dangerText : Theme.ok)

                        Item { width: 14; height: 1 }

                        SvgIcon {
                            id: reloadSlotIcon
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: shellState.reloadSlotState === "loading"
                                ? "refresh"
                                : (shellState.reloadSlotState === "error" ? "alert-triangle" : "check")
                            iconSize: 16
                            color: slotReload.reloadTint

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 760
                                loops: Animation.Infinite
                                running: shellState.reloadSlotOpen && shellState.reloadSlotState === "loading" && !Theme.reduceMotion
                                onRunningChanged: if (!running) reloadSlotIcon.rotation = 0
                            }
                        }

                        Item { width: 8; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: shellState.reloadSlotText
                            color: shellState.reloadSlotState === "loading" ? Theme.text : slotReload.reloadTint
                            font.family: Theme.fontSans
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 215)
                        }

                        Item { width: 14; height: 1 }
                    }

                    // 6. Inline Charger Connected Slot
                    IslandSlot {
                        id: slotCharge
                        open: shellState.chargeSlotOpen && !root.isSearchOnThisScreen
                        maxSlotWidth: 260

                        Item { width: 14; height: 1 }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: "bolt"
                            iconSize: 16
                            color: shellState.chargeIsCharging ? Theme.ok : Theme.text
                        }

                        Item { width: 8; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: shellState.chargeText
                            color: shellState.chargeIsCharging ? Theme.ok : Theme.text
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 210)
                        }

                        Item { width: 14; height: 1 }
                    }

                    // 6.5. Dedicated Active Backup / Snapshot / Restore Progress Slot (never overwritten by transient events)
                    IslandSlot {
                        id: slotBackup
                        open: BackupService.busy && !root.isSearchOnThisScreen
                        maxSlotWidth: 320

                        Item { width: 12; height: 1 }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: "archive"
                            iconSize: 16
                            color: Theme.info
                        }

                        Item { width: 6; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: BackupService.activeStatusText
                            color: Theme.info
                            font.family: Theme.fontSans
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 265)
                        }

                        Item { width: 12; height: 1 }
                    }

                    // 7. Inline Package Update Status Slot (concise status bar event, never notification popup)
                    IslandSlot {
                        id: slotPkgUpdate
                        readonly property bool hasActiveOp: PackageService.activeOpText !== ""
                        readonly property int badgeCount: PackageService.updateCount + (PackageService.shellUpdateBehind > 0 ? 1 : 0)
                        open: ((PackageService.statusEventOpen || hasActiveOp) && !root.isSearchOnThisScreen) || (badgeCount > 0 && !root.anyTransientSlot && !root.isAppExpandedOnScreen)
                        maxSlotWidth: (PackageService.statusEventOpen || hasActiveOp) ? 340 : 76

                        readonly property color pkgTint: {
                            if (PackageService.statusEventOpen) {
                                if (PackageService.statusEventKind === "ok") return Theme.ok;
                                if (PackageService.statusEventKind === "warn") return Theme.warn;
                                if (PackageService.statusEventKind === "danger") return Theme.dangerText;
                            }
                            return Theme.info;
                        }

                        Item { width: (PackageService.statusEventOpen || slotPkgUpdate.hasActiveOp) ? 14 : 10; height: 1 }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: StorageService.activeOpText !== "" ? "hard-drive" : "package-update"
                            iconSize: 16
                            color: slotPkgUpdate.pkgTint
                        }

                        Item { width: 6; height: 1 }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: PackageService.statusEventOpen ? PackageService.statusEventText : (slotPkgUpdate.hasActiveOp ? PackageService.activeOpText : String(slotPkgUpdate.badgeCount))
                            color: slotPkgUpdate.pkgTint
                            font.family: Theme.fontSans
                            font.pixelSize: (PackageService.statusEventOpen || slotPkgUpdate.hasActiveOp) ? 15 : 14
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 275)
                        }

                        Item { width: (PackageService.statusEventOpen || slotPkgUpdate.hasActiveOp) ? 14 : 10; height: 1 }
                    }

                    // 7.5. Inline Screen Recording Status Slot (red dot + blinking approach circle + elapsed time)
                    IslandSlot {
                        id: slotScreenRecord
                        open: ScreenRecordService.recording && !root.isSearchOnThisScreen
                        maxSlotWidth: 160

                        Item {
                            id: recBadgeWrap
                            width: recRow.implicitWidth + 20
                            height: Theme.islandHeight
                            scale: recMouse.pressed ? 0.94 : 1.0

                            Behavior on scale {
                                NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                            }

                            Row {
                                id: recRow
                                anchors.centerIn: parent
                                spacing: 8

                                Item {
                                    width: 20
                                    height: 20
                                    anchors.verticalCenter: parent.verticalCenter

                                    // Blinking / pulsing approach circle
                                    Rectangle {
                                        id: recApproachCircle
                                        anchors.centerIn: parent
                                        width: 18
                                        height: 18
                                        radius: 9
                                        color: "transparent"
                                        border.width: 1.8
                                        border.color: Theme.danger
                                        scale: 0.75
                                        opacity: 0.9

                                        ParallelAnimation {
                                            running: ScreenRecordService.recording && !Theme.reduceMotion
                                            loops: Animation.Infinite

                                            SequentialAnimation {
                                                NumberAnimation {
                                                    target: recApproachCircle
                                                    property: "scale"
                                                    from: 0.65
                                                    to: 1.35
                                                    duration: 1100
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                            SequentialAnimation {
                                                NumberAnimation {
                                                    target: recApproachCircle
                                                    property: "opacity"
                                                    from: 0.95
                                                    to: 0.0
                                                    duration: 1100
                                                    easing.type: Easing.OutCubic
                                                }
                                            }
                                        }
                                    }

                                    // Solid red recording dot
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 10
                                        height: 10
                                        radius: 5
                                        color: Theme.danger
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: ScreenRecordService.formattedTime
                                    color: Theme.dangerText
                                    font.family: Theme.fontSans
                                    font.pixelSize: 16
                                    font.weight: Font.Medium
                                }
                            }

                            MouseArea {
                                id: recMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.hovered = true
                                onExited: root.hovered = false
                                onClicked: ScreenRecordService.stop()
                            }
                        }
                    }

                    // 8. Inline Notification Bell Slot
                    IslandSlot {
                        id: slotNotif
                        open: root.hasNotifBadge && !root.anyTransientSlot
                        maxSlotWidth: 64

                        Item {
                            width: 44
                            height: Theme.islandHeight
                            SvgIcon {
                                anchors.centerIn: parent
                                sourceName: "bell"
                                iconSize: 20
                                color: Theme.text
                            }
                            Rectangle {
                                width: 9
                                height: 9
                                radius: 4.5
                                color: Theme.danger
                                border.width: 2
                                border.color: Theme.pillBg
                                anchors.right: parent.right
                                anchors.rightMargin: 9
                                anchors.top: parent.top
                                anchors.topMargin: 15
                            }
                        }
                    }

                        // 8. Normal Mode Spacer
                        Item {
                            id: slotTimeSep
                            height: 1
                            width: 0
                        }
                    }

                    // Right Edge: Clock
                    Text {
                        id: clockLabel
                        anchors.right: parent.right
                        anchors.rightMargin: 24
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.clockText
                        color: Theme.text
                        font.family: Theme.fontSans
                        font.pixelSize: 22
                        font.weight: Font.Bold

                        Behavior on anchors.rightMargin {
                            NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        propagateComposedEvents: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.hovered = true
                        onExited: root.hovered = false
                        onClicked: function(mouse) {
                            if (root.isAppExpandedOnScreen) {
                                shellState.collapseIslandApp();
                                return;
                            }
                            if (root.isSearchOnThisScreen) {
                                const pt = mapToItem(slotSearch, mouse.x, mouse.y);
                                if (pt.x >= 0 && pt.x <= slotSearch.width) {
                                    mouse.accepted = false;
                                    return;
                                }
                            }
                            if (slotPkgUpdate.open && !root.isSearchOnThisScreen && mouse.button === Qt.LeftButton) {
                                const ptUpd = mapToItem(slotPkgUpdate, mouse.x, mouse.y);
                                if (ptUpd.x >= 0 && ptUpd.x <= slotPkgUpdate.width) {
                                    shellState.settingsPage = "updates";
                                    shellState.openIslandApp("settings", root.modelData);
                                    return;
                                }
                            }
                            if (mouse.button === Qt.RightButton) {
                                shellState.togglePopover("dashboard", root.modelData);
                            } else {
                                shellState.togglePopover("launcher", root.modelData);
                            }
                        }
                    }
                }

                // Hairline Divider + Attached Strip + Embedded App Body
                Rectangle {
                    id: appHeaderSep
                    x: 0
                    y: root.isBottom ? (pillHeader.y - height) : (pillHeader.y + pillHeader.height)
                    width: parent.width
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                    visible: root.isAppExpandedOnScreen
                }

                Rectangle {
                    id: appStrip
                    x: 0
                    y: root.isBottom ? (appHeaderSep.y - height) : (appHeaderSep.y + appHeaderSep.height)
                    width: parent.width
                    height: (root.isAppExpandedOnScreen && root.shellState.islandApp !== "weather") ? 26 : 0
                    color: Qt.rgba(1, 1, 1, 0.04)
                    clip: true
                    visible: height > 0

                    Text {
                        anchors.centerIn: parent
                        text: root.isBottom ? "─── Drag up / out to detach into independent window" : "─── Drag down / out to detach into independent window"
                        color: Theme.textSub
                        font.family: Theme.fontSans
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: detachMouse
                        anchors.fill: parent
                        cursorShape: Qt.OpenHandCursor
                        property real startX: 0
                        property real startY: 0
                        property bool triggered: false
                        onPressed: function(mouse) {
                            startX = mouse.x;
                            startY = mouse.y;
                            triggered = false;
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed || triggered) return;
                            const dist = Math.hypot(mouse.x - startX, mouse.y - startY);
                            if (dist > 32) {
                                triggered = true;
                                shellState.detachIslandApp(shellState.islandApp);
                            }
                        }
                        onClicked: {
                            if (!triggered) shellState.collapseIslandApp();
                        }
                    }
                }

                Rectangle {
                    id: appBody
                    x: 0
                    y: root.isBottom ? 0 : (appStrip.y + appStrip.height)
                    width: parent.width
                    height: Math.max(0, parent.height - Theme.islandHeight - appHeaderSep.height - appStrip.height)
                    color: Theme.surfaceBg
                    bottomLeftRadius: root.isBottom ? 0 : 17
                    bottomRightRadius: root.isBottom ? 0 : 17
                    topLeftRadius: root.isBottom ? 17 : 0
                    topRightRadius: root.isBottom ? 17 : 0
                    clip: true
                    opacity: root.isAppExpandedOnScreen ? 1.0 : 0.0
                    visible: opacity > 0.01

                    ThemeGradientFill {
                        anchors.fill: parent
                        enabled: Theme.surfaceGradientEnabled
                        color1: Theme.surfaceBg
                        colorMid: Theme.surfaceBgMid
                        color2: Theme.surfaceBg2
                        cornerRadius: 0
                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Theme.reduceMotion ? 110 : (root.isAppExpandedOnScreen ? 200 : 120)
                            easing.type: Easing.OutCubic
                        }
                    }

                    Loader {
                        id: settingsLoader
                        anchors.fill: parent
                        active: (Theme.reduceMotion && root._cachedSettings) || ((root.isAppExpandedOnScreen || appBody.visible) && root.shellState.islandApp === "settings")
                        visible: root.shellState.islandApp === "settings"
                        function ensureSource() {
                            if (active && source.toString() === "") setSource("SettingsView.qml", { shellState: root.shellState });
                        }
                        Component.onCompleted: ensureSource()
                        onActiveChanged: ensureSource()
                        onLoaded: if (item) item.openPage(root.shellState.settingsPage || "home")
                    }

                    Loader {
                        id: filesLoader
                        anchors.fill: parent
                        active: (Theme.reduceMotion && root._cachedFiles) || ((root.isAppExpandedOnScreen || appBody.visible) && root.shellState.islandApp === "files")
                        visible: root.shellState.islandApp === "files"
                        function ensureSource() {
                            if (active && source.toString() === "") setSource("FilesView.qml", { shellState: root.shellState });
                        }
                        Component.onCompleted: ensureSource()
                        onActiveChanged: ensureSource()
                        onLoaded: if (item && root.isAppExpandedOnScreen) Qt.callLater(() => { if (item) item.forceActiveFocus(); })
                    }

                    Loader {
                        id: musicLoader
                        anchors.fill: parent
                        active: (Theme.reduceMotion && root._cachedMusic) || ((root.isAppExpandedOnScreen || appBody.visible) && root.shellState.islandApp === "music")
                        visible: root.shellState.islandApp === "music"
                        function ensureSource() {
                            if (active && source.toString() === "") setSource("MusicView.qml", { shellState: root.shellState });
                        }
                        Component.onCompleted: ensureSource()
                        onActiveChanged: ensureSource()
                        onLoaded: if (item && root.isAppExpandedOnScreen) Qt.callLater(() => { if (item) item.forceActiveFocus(); })
                    }

                    Loader {
                        id: pickerLoader
                        anchors.fill: parent
                        active: (Theme.reduceMotion && root._cachedPicker) || ((root.isAppExpandedOnScreen || appBody.visible) && root.shellState.islandApp === "picker")
                        visible: root.shellState.islandApp === "picker"
                        function ensureSource() {
                            if (active && source.toString() === "") setSource("PickerView.qml", { shellState: root.shellState });
                        }
                        Component.onCompleted: ensureSource()
                        onActiveChanged: ensureSource()
                        onLoaded: if (item) {
                            item.initFromState();
                            if (root.isAppExpandedOnScreen) Qt.callLater(() => { if (item) item.forceActiveFocus(); });
                        }
                    }

                    Loader {
                        id: portalLoader
                        anchors.fill: parent
                        active: (root.isAppExpandedOnScreen || appBody.visible) && root.shellState.islandApp === "portal"
                        visible: root.shellState.islandApp === "portal"
                        function ensureSource() {
                            if (active && source.toString() === "") setSource("PortalView.qml", { shellState: root.shellState });
                        }
                        Component.onCompleted: ensureSource()
                        onActiveChanged: ensureSource()
                        onLoaded: if (item) item.refreshSources()
                    }

                    Loader {
                        id: weatherLoader
                        anchors.fill: parent
                        active: (Theme.reduceMotion && root._cachedWeather) || ((root.isAppExpandedOnScreen || appBody.visible) && root.shellState.islandApp === "weather")
                        visible: root.shellState.islandApp === "weather"
                        function ensureSource() {
                            if (active && source.toString() === "") setSource("WeatherForecastView.qml", { shellState: root.shellState });
                        }
                        Component.onCompleted: ensureSource()
                        onActiveChanged: ensureSource()
                    }
                }

                DropArea {
                    anchors.fill: parent
                    enabled: !root.isAppExpandedOnScreen
                    onEntered: function(drag) {
                        root.dropHovered = true;
                        drag.accepted = true;
                    }
                    onExited: root.dropHovered = false
                    onDropped: function(drop) {
                        root.dropHovered = false;
                        if (drop.hasUrls && drop.urls.length > 0) {
                            KdeConnectService.sendFile(drop.urls[0]);
                        } else if (drop.hasText && drop.text !== "") {
                            KdeConnectService.sendFile(drop.text);
                        }
                    }
                }
            }

            // Liquid Split Pill 1: Media Player
            Item {
                id: mediaSlotWrap
                y: root.isBottom ? (contentRow.height - height) : 0
                height: Theme.islandHeight
                clip: true
                width: root.hasMedia ? (Theme.splitGap + mediaPill.width) : 0
                opacity: root.hasMedia ? 1.0 : 0.0
                visible: width > 0.5 || opacity > 0.01

                Behavior on width {
                    NumberAnimation {
                        duration: root.hasMedia ? Theme.springMs : Theme.smoothMs
                        easing.type: root.hasMedia ? Theme.motionEasing : Easing.OutCubic
                        easing.overshoot: Theme.reduceMotion ? 0.0 : 0.75
                    }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.reduceMotion ? Theme.smoothMs : (root.hasMedia ? 220 : 160); easing.type: Easing.OutCubic }
                }

                Item {
                    id: mediaPill
                    x: root.hasMedia ? Theme.splitGap : 0
                    height: Theme.islandHeight
                    width: Math.min(260, Math.max(120, Math.ceil(mediaRow.implicitWidth) + 36))
                    scale: root.hasMedia ? 1.0 : 0.86

                    Behavior on x {
                        NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: Theme.springMs; easing.type: Theme.motionEasing; easing.overshoot: Theme.reduceMotion ? 0.0 : 1.2 }
                    }

                    Row {
                        id: mediaRow
                        anchors.centerIn: parent
                        spacing: 10

                        // Flat equalizer glyph: bars dance while playing, rest low when paused
                        Row {
                            id: eq
                            y: Math.round((mediaRow.height - height) / 2)
                            spacing: 2.5
                            height: 16
                            readonly property var maxH: [10, 16, 12, 15]
                            readonly property var durs: [420, 340, 480, 380]
                            Repeater {
                                model: 4
                                delegate: Rectangle {
                                    required property int index
                                    width: 2.5
                                    radius: 1.25
                                    id: bar
                                    height: eq.maxH[index]
                                    y: Math.round((eq.height - height) / 2)
                                    color: MediaService.isPlaying ? Theme.accent : Qt.rgba(1, 1, 1, 0.45)
                                    Behavior on color { ColorAnimation { duration: 220 } }
                                    // Scale only vertically, around the bar's center, so all bars stay on the pill midline
                                    transform: Scale { id: sc; origin.y: bar.height / 2; yScale: 0.3 }

                                    SequentialAnimation {
                                        running: MediaService.isPlaying && root.hasMedia && !Theme.reduceMotion
                                        loops: Animation.Infinite
                                        onStopped: sc.yScale = 0.3
                                        NumberAnimation { target: sc; property: "yScale"; to: 1.0; duration: eq.durs[index]; easing.type: Easing.InOutSine }
                                        NumberAnimation { target: sc; property: "yScale"; to: 0.3; duration: eq.durs[index]; easing.type: Easing.InOutSine }
                                    }
                                }
                            }
                        }

                        Text {
                            y: Math.round((mediaRow.height - height) / 2)
                            text: MediaService.trackTitle
                            color: Qt.rgba(1, 1, 1, 0.92)
                            font.family: Theme.fontSans
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 140)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.hovered = true
                        onExited: root.hovered = false
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.RightButton) {
                                if (MediaService.useMixcloud) {
                                    root.shellState.openIslandApp("music", root.modelData);
                                } else {
                                    root.shellState.togglePopover("dashboard", root.modelData);
                                }
                            } else {
                                MediaService.togglePlay();
                            }
                        }
                    }
                }
            }

            // Liquid Split Pill 2: Hardware / Thermal / Battery Alert
            Item {
                id: alertSlotWrap
                y: root.isBottom ? (contentRow.height - height) : 0
                height: Theme.islandHeight
                clip: true
                width: root.hasAlert ? (Theme.splitGap + alertPill.width) : 0
                opacity: root.hasAlert ? 1.0 : 0.0
                visible: width > 0.5 || opacity > 0.01

                Behavior on width {
                    NumberAnimation {
                        duration: root.hasAlert ? Theme.springMs : Theme.smoothMs
                        easing.type: root.hasAlert ? Theme.motionEasing : Easing.OutCubic
                        easing.overshoot: Theme.reduceMotion ? 0.0 : 0.75
                    }
                }
                Behavior on opacity {
                    NumberAnimation { duration: Theme.reduceMotion ? Theme.smoothMs : (root.hasAlert ? 220 : 160); easing.type: Easing.OutCubic }
                }

                Item {
                    id: alertPill
                    x: root.hasAlert ? Theme.splitGap : 0
                    height: Theme.islandHeight
                    width: Math.min(240, Math.max(140, Math.ceil(alertRow.implicitWidth) + 38))
                    scale: root.hasAlert ? 1.0 : 0.86

                    Behavior on x {
                        NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
                    }
                    Behavior on scale {
                        NumberAnimation { duration: Theme.springMs; easing.type: Theme.motionEasing; easing.overshoot: Theme.reduceMotion ? 0.0 : 1.2 }
                    }

                    readonly property color alertTint: root.alertMode === 1 ? Theme.dangerText : Theme.warn
                    readonly property string alertMsg: root.alertMode === 1
                        ? (TelemetryService.overheatAlert ? TelemetryService.cpuTempC + "℃ Overheat" : "92℃ Overheat")
                        : (PowerService.lowBatteryAlert ? PowerService.batteryPct + "% Low Battery" : "7% Low Battery")

                    Row {
                        id: alertRow
                        anchors.centerIn: parent
                        spacing: 9

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: root.alertMode === 1 ? "thermometer" : "battery-low"
                            iconSize: 18
                            color: alertPill.alertTint
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: alertPill.alertMsg
                            color: alertPill.alertTint
                            font.family: Theme.fontSans
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 165)
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.hovered = true
                        onExited: root.hovered = false
                        onClicked: shellState.cycleAlert()
                    }
                }
            }
        }
    }
}
