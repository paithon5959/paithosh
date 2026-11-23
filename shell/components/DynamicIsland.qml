import QtQuick
import QtQuick.Layouts
import Quickshell
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
    readonly property bool isPopoverOpenOnThisScreen: isActiveScreen && shellState.openPopover !== ""
    readonly property bool isSearchOnThisScreen: isActiveScreen && shellState.openPopover === "search"
    readonly property bool isAppExpandedOnScreen: isActiveScreen && shellState.islandApp !== ""
    readonly property bool hasActivity: anyTransientSlot || isPopoverOpenOnThisScreen || isAppExpandedOnScreen || hasAlert || ScreenRecordService.recording
    readonly property bool isHidden: (shellState.manualHideBar || (shellState.hideBarFullscreen && CompositorService.isFullscreenFor(modelData)) || (shellState.autoHideOnOverlap && CompositorService.isOverlappedFor(modelData, shellState.barPosition))) && !root.hovered && !topEdgeHover.hovered && !hasActivity && !(shellState.superPeekBar && isActiveScreen)

    readonly property string attachedTitle: {
        if (shellState.islandApp === "settings") return "Settings (Island)";
        if (shellState.islandApp === "files") return "Files (Island)";
        if (shellState.islandApp === "picker") {
            if (shellState.pickerDirectory) return "Select Folder (Island)";
            return shellState.pickerMode === "download" ? "Save Location (Island)" : "Upload Location (Island)";
        }
        if (shellState.islandApp === "portal") return "Screen Share (Island)";
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

    readonly property bool anyTransientSlot: isSearchOnThisScreen || shellState.osdOpen || shellState.wsSlotOpen || shellState.kdeSlotOpen || shellState.chargeSlotOpen || PackageService.statusEventOpen || PackageService.activeOpText !== "" || BackupService.busy

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

    onIsAppExpandedOnScreenChanged: {
        if (isAppExpandedOnScreen) {
            if (shellState.islandApp === "settings" && settingsLoader.item) {
                settingsLoader.item.openPage(shellState.settingsPage || "home");
                expandedFocusItem.forceActiveFocus();
            } else if (shellState.islandApp === "picker" && pickerLoader.item) {
                pickerLoader.item.initFromState();
                Qt.callLater(() => { if (pickerLoader.item) pickerLoader.item.forceActiveFocus(); });
            } else if (shellState.islandApp === "files" && filesLoader.item) {
                Qt.callLater(() => { if (filesLoader.item) filesLoader.item.forceActiveFocus(); });
            } else {
                expandedFocusItem.forceActiveFocus();
            }
        }
    }

    Connections {
        target: root.shellState
        function onIslandAppChanged() {
            if (root.isAppExpandedOnScreen) {
                if (root.shellState.islandApp === "settings" && settingsLoader.item) {
                    settingsLoader.item.openPage(root.shellState.settingsPage || "home");
                    expandedFocusItem.forceActiveFocus();
                } else if (root.shellState.islandApp === "picker" && pickerLoader.item) {
                    pickerLoader.item.initFromState();
                    Qt.callLater(() => { if (pickerLoader.item) pickerLoader.item.forceActiveFocus(); });
                } else if (root.shellState.islandApp === "files" && filesLoader.item) {
                    Qt.callLater(() => { if (filesLoader.item) filesLoader.item.forceActiveFocus(); });
                }
            }
        }
    }

    Connections {
        target: VpnProxyService
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
        y: root.isBottom ? (parent.height - height) : 0
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(contentRow.width + 16, 260)
        height: Theme.topOffsetRest + Theme.islandHeight

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

    mask: Region {
        item: root.isHidden ? hoverTrigger : (root.isAppExpandedOnScreen ? (root.shellState.islandApp === "files" ? filesCardMask : fullScreenMask) : hitbox)
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
        property real animatedHideOffset: root.isHidden ? 26 : 0
        property real bottomProgress: root.isBottom ? 1.0 : 0.0
        Behavior on animatedEdgeOffset {
            NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
        }
        Behavior on animatedHideOffset {
            NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
        }
        Behavior on bottomProgress {
            NumberAnimation {
                duration: Math.round(Theme.springMs * 1.1)
                easing.type: Easing.OutBack
                easing.overshoot: 0.6
            }
        }
        readonly property real topY: animatedEdgeOffset - Theme.shaderPad - animatedHideOffset
        readonly property real bottomY: root.height - height + Theme.shaderPad - animatedEdgeOffset + animatedHideOffset
        y: topY + (bottomY - topY) * bottomProgress
        width: contentRow.width + Theme.shaderPad * 2
        height: mainPill.height + Theme.shaderPad * 2
        opacity: root.isHidden ? 0.0 : 1.0
        scale: root.isHidden ? 0.65 : 1.0
        transformOrigin: root.isBottom ? Item.Bottom : Item.Top

        Behavior on opacity {
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: Theme.smoothMs; easing.type: Easing.OutCubic }
        }

        // Liquid Gooey Background Layer (1:1 geometry sync with foreground pills; auto-disabled when app expanded)
        Item {
            id: gooSource
            anchors.fill: parent
            layer.enabled: Theme.gooeyEnabled && !root.isAppExpandedOnScreen
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
                y: Theme.shaderPad + mediaSlotWrap.y + (Theme.islandHeight - height) / 2
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
                y: Theme.shaderPad + alertSlotWrap.y + (Theme.islandHeight - height) / 2
                width: Math.max(0, Math.min(alertPill.width, alertSlotWrap.width - alertPill.x))
                height: alertPill.height
                radius: Theme.islandRadius
                color: Theme.pillBg
                scale: alertPill.scale
                opacity: alertSlotWrap.opacity
                visible: width > 1 && opacity > 0.01
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
            ClippingRectangle {
                id: mainPill
                // Uses slots' *target* widths so the frame leads the content instead of chasing it
                readonly property real slotsTargetWidth: {
                    let w = 0;
                    const kids = centerSlotsRow.children;
                    for (let i = 0; i < kids.length; ++i) if (kids[i].targetWidth !== undefined) w += kids[i].targetWidth;
                    return w;
                }
                readonly property int compactWidth: Math.max(260, Math.ceil(weatherLabel.implicitWidth + slotsTargetWidth + clockLabel.implicitWidth + 84))
                height: root.isAppExpandedOnScreen ? Math.min(626, root.height - 96) : Theme.islandHeight
                width: root.isAppExpandedOnScreen ? Math.min(920, root.width - 48) : compactWidth
                radius: root.isAppExpandedOnScreen ? 18 : Theme.islandRadius
                color: "transparent"
                border.width: root.dropHovered ? 2 : 1
                border.color: root.dropHovered ? Theme.accent : (root.isAppExpandedOnScreen ? Theme.borderSubtle : Qt.rgba(1, 1, 1, 0.12))
                Behavior on border.color { ColorAnimation { duration: Theme.smoothMs } }

                Behavior on width {
                    NumberAnimation {
                        duration: root.isAppExpandedOnScreen ? Theme.springMs : Math.round(Theme.springMs * 0.6)
                        easing.type: Easing.OutBack
                        easing.overshoot: root.isAppExpandedOnScreen ? 0.85 : 1.5
                    }
                }
                Behavior on height {
                    NumberAnimation {
                        duration: root.isAppExpandedOnScreen ? Theme.springMs : 110
                        easing.type: root.isAppExpandedOnScreen ? Easing.OutBack : Easing.OutCubic
                        easing.overshoot: 0.75
                    }
                }
                Behavior on radius {
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
                                if (PackageService.statusEventKind === "danger") return Theme.dangerText;
                            }
                            return Theme.info;
                        }

                        Item { width: (PackageService.statusEventOpen || slotPkgUpdate.hasActiveOp) ? 14 : 10; height: 1 }

                        SvgIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            sourceName: "package-update"
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
                                            running: ScreenRecordService.recording
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
                    height: root.isAppExpandedOnScreen ? 26 : 0
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
                    clip: true
                    opacity: root.isAppExpandedOnScreen ? 1.0 : 0.0
                    visible: opacity > 0.01

                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.isAppExpandedOnScreen ? 200 : 120
                            easing.type: Easing.OutCubic
                        }
                    }

                    Loader {
                        id: settingsLoader
                        anchors.fill: parent
                        active: appBody.visible && root.shellState.islandApp === "settings"
                        onLoaded: if (item) item.openPage(root.shellState.settingsPage || "home")
                        sourceComponent: SettingsView {
                            shellState: root.shellState
                        }
                    }

                    Loader {
                        id: filesLoader
                        anchors.fill: parent
                        active: appBody.visible && root.shellState.islandApp === "files"
                        onLoaded: if (item && root.isAppExpandedOnScreen) Qt.callLater(() => { if (item) item.forceActiveFocus(); })
                        sourceComponent: FilesView {
                            shellState: root.shellState
                        }
                    }

                    Loader {
                        id: pickerLoader
                        anchors.fill: parent
                        active: appBody.visible && root.shellState.islandApp === "picker"
                        onLoaded: if (item) {
                            item.initFromState();
                            if (root.isAppExpandedOnScreen) Qt.callLater(() => { if (item) item.forceActiveFocus(); });
                        }
                        sourceComponent: PickerView {
                            shellState: root.shellState
                        }
                    }

                    Loader {
                        id: portalLoader
                        anchors.fill: parent
                        active: appBody.visible && root.shellState.islandApp === "portal"
                        onLoaded: if (item) item.refreshSources()
                        sourceComponent: PortalView {
                            shellState: root.shellState
                        }
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
                        easing.type: root.hasMedia ? Easing.OutBack : Easing.OutCubic
                        easing.overshoot: 0.75
                    }
                }
                Behavior on opacity {
                    NumberAnimation { duration: root.hasMedia ? 220 : 160; easing.type: Easing.OutCubic }
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
                        NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
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
                                        running: MediaService.isPlaying && root.hasMedia
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
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.hovered = true
                        onExited: root.hovered = false
                        onClicked: MediaService.togglePlay()
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
                        easing.type: root.hasAlert ? Easing.OutBack : Easing.OutCubic
                        easing.overshoot: 0.75
                    }
                }
                Behavior on opacity {
                    NumberAnimation { duration: root.hasAlert ? 220 : 160; easing.type: Easing.OutCubic }
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
                        NumberAnimation { duration: Theme.springMs; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
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
